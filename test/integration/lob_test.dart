@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('LOB locators', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    setUpAll(() async {
      await dropTable(conn(), 'dart_loc_t');
      await conn().execute(
          'create table dart_loc_t (id number, c clob, b blob, nc nclob)');
    });
    tearDownAll(() => dropTable(conn(), 'dart_loc_t'));

    Future<List<Object?>> fetchLocators(int id) async {
      final cursor = conn().cursor()..fetchLobsAsValues = false;
      await cursor
          .execute('select c, b, nc from dart_loc_t where id = :1', [id]);
      final row = (await cursor.fetchOne())!;
      cursor.close();
      return row;
    }

    test('reads, streams and measures LOBs', () async {
      final text = List.generate(300000, (i) => 'çx'[i % 2]).join();
      final bytes = Uint8List.fromList(List.generate(200000, (i) => i % 256));
      await conn().execute(
          'insert into dart_loc_t values (1, :1, :2, :3)', [text, bytes, text]);
      final row = await fetchLocators(1);
      final clob = row[0] as OracleLob;
      final blob = row[1] as OracleLob;
      final nclob = row[2] as OracleLob;
      expect(clob.type, DbType.clob);
      expect(await clob.size(), text.length);
      expect(await blob.size(), bytes.length);
      expect(await clob.chunkSize(), greaterThan(0));
      expect(await clob.read(offset: 2, amount: 5), text.substring(1, 6));
      expect(await clob.readString(), text);
      expect(await blob.readBytes(), bytes);
      expect(await nclob.readString(), text);
      final pieces = await clob.stream(pieceSize: 70000).toList();
      expect(pieces.length, 5);
      expect(pieces.join(), text);
      final blobPieces = await blob.stream().toList();
      expect([for (final p in blobPieces) ...(p as Uint8List)], bytes);
    });

    test('writes and trims LOBs selected for update', () async {
      await conn().execute(
          "insert into dart_loc_t values (2, empty_clob(), empty_blob(), null)");
      final cursor = conn().cursor()..fetchLobsAsValues = false;
      await cursor
          .execute('select c, b from dart_loc_t where id = 2 for update');
      final row = (await cursor.fetchOne())!;
      final clob = row[0] as OracleLob;
      final blob = row[1] as OracleLob;
      await clob.write('hello world');
      await clob.write('HELLO', offset: 1);
      await blob.write(Uint8List.fromList([1, 2, 3, 4, 5]));
      await clob.trim(8);
      await conn().commit();
      cursor.close();
      expect(
          await conn().queryOne('select c, b from dart_loc_t where id = 2'), [
        'HELLO wo',
        Uint8List.fromList([1, 2, 3, 4, 5])
      ]);
    });

    test('temporary LOBs can be created and bound', () async {
      final lob = await conn().createLob(DbType.clob, 'temporary ' * 10000);
      expect(lob.isTemporary, isTrue);
      await conn()
          .execute('insert into dart_loc_t (id, c) values (3, :1)', [lob]);
      lob.free();
      final blob = await conn().createLob(DbType.blob);
      await blob.write(Uint8List.fromList([9, 8, 7]));
      await conn().execute('update dart_loc_t set b = :1 where id = 3', [blob]);
      blob.free();
      expect(
          await conn().queryOne(
              'select length(c), dbms_lob.getlength(b) from dart_loc_t where id = 3'),
          [100000, 3]);
    });

    test('long strings bound to PL/SQL use temporary LOBs', () async {
      final text = 'p' * 100000;
      final cursor = conn().cursor();
      final out = cursor.variable(DbType.varchar, size: 200000);
      // positional binds follow the order in which placeholders appear, so
      // named binds are used here
      await cursor.execute('begin :result := :value || :value; end;',
          {'value': text, 'result': out});
      expect(out.value, text + text);
      final bytesOut = cursor.variable(DbType.raw, size: 100000);
      await cursor.execute('''
          declare
            b blob;
          begin
            dbms_lob.createtemporary(b, true);
            for i in 1..5 loop
              dbms_lob.append(b, to_blob(utl_raw.copies(:src, 10000)));
            end loop;
            :res := b;
          end;''', {
        'src': Uint8List.fromList([1, 2]),
        'res': bytesOut,
      });
      expect((bytesOut.value as Uint8List).length, 100000);
      cursor.close();
    });
  });
}
