@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('data types', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    Future<Object?> roundTrip(String expr, [Object? params]) async =>
        (await conn().queryOne('select $expr from dual', params))![0];

    test('strings', () async {
      expect(await roundTrip("'abc'"), 'abc');
      expect(await roundTrip(':1', ['olá, ünïcödé ✓ 日本']), 'olá, ünïcödé ✓ 日本');
      expect(await roundTrip("cast('x' as char(5))"), 'x    ');
      expect(await roundTrip("n'çã'"), 'çã');
      expect(await roundTrip("to_nchar(:1)", ['Ωmega']), 'Ωmega');
      expect(await roundTrip("''"), isNull);
      expect(await roundTrip(':1', [null]), isNull);
      final long = 'x' * 4000;
      expect(await roundTrip(':1', [long]), long);
    });

    test('numbers', () async {
      expect(await roundTrip('42'), 42);
      expect(await roundTrip('-42'), -42);
      expect(await roundTrip('3.25'), 3.25);
      expect(await roundTrip('1/3'), closeTo(1 / 3, 1e-15));
      expect(await roundTrip('123456789012345678'), 123456789012345678);
      expect(await roundTrip('12345678901234567890123'),
          BigInt.parse('12345678901234567890123'));
      expect(await roundTrip('cast(7 as number(10, 2))'), 7.0);
      expect(await roundTrip(':1 + 1', [41]), 42);
      expect(await roundTrip(':1 * 2', [1.25]), 2.5);
      expect(await roundTrip(':1', [BigInt.parse('99999999999999999999')]),
          BigInt.parse('99999999999999999999'));
      expect(
          await roundTrip(':1', [-9223372036854775808]), -9223372036854775808);
      expect(await roundTrip('cast(1.5 as binary_double)'), 1.5);
      expect(await roundTrip('cast(2.5 as binary_float)'), 2.5);
      expect(await roundTrip('to_binary_double(:1)', [1e300]), 1e300);
    });

    test('numbers as strings', () async {
      final cursor = conn().cursor()..fetchNumbersAsStrings = true;
      await cursor.execute(
          'select 1234567890.123456789012345678901234567890, 5 from dual');
      expect(await cursor.fetchOne(),
          ['1234567890.12345678901234567890123456789', '5']);
      cursor.close();
    });

    test('dates and timestamps', () async {
      final dt = DateTime.utc(2024, 2, 29, 13, 45, 30);
      expect(await roundTrip(':1', [dt]), dt);
      final ts = DateTime.utc(2024, 2, 29, 13, 45, 30, 123, 456);
      expect(await roundTrip(':1', [ts]), ts);
      expect(await roundTrip("date '2001-02-03'"), DateTime.utc(2001, 2, 3));
      expect(await roundTrip("timestamp '2001-02-03 04:05:06.789'"),
          DateTime.utc(2001, 2, 3, 4, 5, 6, 789));
      expect(await roundTrip("timestamp '2001-02-03 04:05:06.5 -03:00'"),
          DateTime.utc(2001, 2, 3, 7, 5, 6, 500));
      final ltz = await roundTrip(
          "cast(timestamp '2001-02-03 04:05:06 +00:00' as timestamp with local time zone)");
      expect(ltz, isA<DateTime>());
    });

    test('intervals', () async {
      expect(
          await roundTrip("interval '3 04:05:06.5' day to second"),
          const Duration(
              days: 3, hours: 4, minutes: 5, seconds: 6, milliseconds: 500));
      expect(await roundTrip("interval '-2 01:00:00' day to second"),
          -const Duration(days: 2, hours: 1));
      expect(await roundTrip(':1', [const Duration(hours: 30)]),
          const Duration(hours: 30));
      expect(await roundTrip("interval '5-3' year to month"),
          const IntervalYM(5, 3));
      expect(await roundTrip(':1', [const IntervalYM(-1, -6)]),
          const IntervalYM(-1, -6));
    });

    test('raw', () async {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));
      expect(await roundTrip(':1', [bytes]), bytes);
      expect(await roundTrip("hextoraw('DEADBEEF')"),
          Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
    });

    test('boolean', () async {
      if (conn().serverVersion.first < 23) return;
      expect(await roundTrip('true'), isTrue);
      expect(await roundTrip(':1', [false]), isFalse);
      expect(await roundTrip('cast(null as boolean)'), isNull);
    });

    test('rowid', () async {
      await dropTable(conn(), 'dart_rowid_t');
      await conn().execute('create table dart_rowid_t (x number)');
      await conn().execute('insert into dart_rowid_t values (1)');
      final row = await conn()
          .queryOne('select rowid, rowidtochar(rowid) from dart_rowid_t');
      expect(row![0], row[1]);
      expect(
          (await conn().queryOne(
              'select x from dart_rowid_t where rowid = :1', [row[0]]))![0],
          1);
      await dropTable(conn(), 'dart_rowid_t');
    });

    group('LOBs', () {
      setUpAll(() async {
        await dropTable(conn(), 'dart_lob_t');
        await conn().execute(
            'create table dart_lob_t (id number, c clob, b blob, nc nclob)');
      });
      tearDownAll(() => dropTable(conn(), 'dart_lob_t'));

      for (final size in [0, 10, 4000, 32767, 100000, 1000000]) {
        test('CLOB/BLOB/NCLOB of $size bytes', () async {
          final text =
              String.fromCharCodes(List.generate(size, (i) => 65 + i % 26));
          final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
          await conn().execute('delete from dart_lob_t');
          await conn().execute('insert into dart_lob_t values (1, :c, :b, :nc)',
              {'c': text, 'b': bytes, 'nc': text});
          final row = await conn().queryOne('select c, b, nc from dart_lob_t');
          if (size == 0) {
            expect(row, [null, null, null]);
          } else {
            expect(row![0], text);
            expect(row[1], bytes);
            expect(row[2], text);
          }
        });
      }

      test('LOBs in many rows', () async {
        await conn().execute('delete from dart_lob_t');
        await conn()
            .executeMany('insert into dart_lob_t (id, c) values (:1, :2)', [
          for (var i = 0; i < 300; i++) [i, 'value $i ' * (i + 1)]
        ]);
        final rows =
            await conn().query('select id, c from dart_lob_t order by id');
        expect(rows.length, 300);
        for (var i = 0; i < 300; i++) {
          expect(rows[i], [i, 'value $i ' * (i + 1)]);
        }
      });
    });

    test('long column', () async {
      await dropTable(conn(), 'dart_long_t');
      await conn().execute('create table dart_long_t (id number, l long)');
      final value = 'L' * 70000;
      await conn().execute('insert into dart_long_t values (1, :1)', [value]);
      expect((await conn().queryOne('select l from dart_long_t'))![0], value);
      await dropTable(conn(), 'dart_long_t');
    });

    test('column metadata', () async {
      final cursor = conn().cursor();
      await cursor.execute(
          "select cast(1 as number(9, 2)) num, cast('x' as varchar2(30)) str, "
          'sysdate dt from dual');
      final d = cursor.description!;
      expect([for (final c in d) c.name], ['NUM', 'STR', 'DT']);
      expect(d[0].dbType, DbType.number);
      expect(d[0].precision, 9);
      expect(d[0].scale, 2);
      expect(d[1].dbType, DbType.varchar);
      expect(d[1].maxSize, 30);
      expect(d[2].dbType, DbType.date);
      cursor.close();
    });
  });
}
