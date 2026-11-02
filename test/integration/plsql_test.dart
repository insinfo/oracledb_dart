@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PL/SQL', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    setUpAll(() async {
      await conn().execute('''
        create or replace function dart_add(a number, b number) return number is
        begin
          return a + b;
        end;''');
      await conn().execute('''
        create or replace procedure dart_proc(
            a in number, b in out varchar2, c out date) is
        begin
          b := b || ':' || a;
          c := date '2020-01-02';
        end;''');
    });

    tearDownAll(() async {
      await conn().execute('drop function dart_add');
      await conn().execute('drop procedure dart_proc');
    });

    test('OUT and IN OUT binds', () async {
      final cursor = conn().cursor();
      final b = cursor.variable(DbType.varchar, size: 100, inValue: 'x');
      final c = cursor.variable(DbType.date);
      await cursor.execute('begin dart_proc(:1, :2, :3); end;', [5, b, c]);
      expect(b.value, 'x:5');
      expect(c.value, DateTime.utc(2020, 1, 2));
      // execute again (re-execution of the same block)
      b.setValue(0, 'y');
      await cursor.execute('begin dart_proc(:1, :2, :3); end;', [6, b, c]);
      expect(b.value, 'y:6');
      cursor.close();
    });

    test('named binds in PL/SQL', () async {
      final cursor = conn().cursor();
      final out = cursor.variable(DbType.number);
      await cursor.execute('begin :out := :a * :a; end;', {'a': 7, 'out': out});
      expect(out.value, 49);
      cursor.close();
    });

    test('callFunc and callProc', () async {
      final cursor = conn().cursor();
      expect(await cursor.callFunc('dart_add', DbType.number, [2, 3]), 5);
      final b = cursor.variable(DbType.varchar, size: 50, inValue: 'p');
      final c = cursor.variable(DbType.date);
      await cursor.callProc('dart_proc', [1, b, c]);
      expect(b.value, 'p:1');
      cursor.close();
    });

    test('boolean OUT bind', () async {
      final cursor = conn().cursor();
      final out = cursor.variable(DbType.boolean);
      await cursor.execute('begin :1 := 1 < 2; end;', [out]);
      expect(out.value, isTrue);
      cursor.close();
    });

    test('REF CURSOR OUT bind', () async {
      final cursor = conn().cursor();
      final refCursor = cursor.variable(DbType.cursor);
      await cursor.execute('''
        begin
          open :1 for select level, 'row ' || level from dual
              connect by level <= 250;
        end;''', [refCursor]);
      final child = refCursor.value as OracleCursor;
      final rows = await child.fetchAll();
      expect(rows.length, 250);
      expect(rows.last, [250, 'row 250']);
      child.close();
      cursor.close();
    });

    test('implicit results', () async {
      final cursor = conn().cursor();
      await cursor.execute('''
        declare
          c1 sys_refcursor;
          c2 sys_refcursor;
        begin
          open c1 for select 1 from dual;
          dbms_sql.return_result(c1);
          open c2 for select 'a' from dual union all select 'b' from dual;
          dbms_sql.return_result(c2);
        end;''');
      final results = cursor.implicitResults;
      expect(results.length, 2);
      expect(await results[0].fetchAll(), [
        [1]
      ]);
      expect(await results[1].fetchAll(), [
        ['a'],
        ['b']
      ]);
      cursor.close();
    });

    test('PL/SQL executeMany', () async {
      await dropTable(conn(), 'dart_plsql_t');
      await conn()
          .execute('create table dart_plsql_t (id number, v varchar2(20))');
      await conn()
          .executeMany('begin insert into dart_plsql_t values (:1, :2); end;', [
        for (var i = 0; i < 10; i++) [i, 'v$i']
      ]);
      expect(
          (await conn().queryOne('select count(*) from dart_plsql_t'))![0], 10);
      await dropTable(conn(), 'dart_plsql_t');
    });
  });

  group('errors', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    test('query errors include the offset and keep the connection usable',
        () async {
      for (var i = 0; i < 3; i++) {
        await expectLater(
            conn().execute('select * from no_such_table_xyz'),
            throwsA(isA<OracleDatabaseError>()
                .having((e) => e.code, 'code', 942)
                .having((e) => e.offset, 'offset', 14)));
        expect((await conn().queryOne('select 1 from dual'))![0], 1);
      }
    });

    test('application errors from PL/SQL', () async {
      await expectLater(
          conn().execute(
              "begin raise_application_error(-20123, 'custom failure'); end;"),
          throwsA(isA<OracleDatabaseError>()
              .having((e) => e.code, 'code', 20123)
              .having(
                  (e) => e.message, 'message', contains('custom failure'))));
      await conn().ping();
    });

    test('errors raised while rows are being fetched', () async {
      final cursor = conn().cursor()..arraySize = 10;
      await cursor
          .execute('select 1 / (50 - level) from dual connect by level <= 100');
      await expectLater(
          cursor.fetchAll(),
          throwsA(
              isA<OracleDatabaseError>().having((e) => e.code, 'code', 1476)));
      cursor.close();
      expect((await conn().queryOne('select 2 from dual'))![0], 2);
    });

    test('missing and invalid binds', () async {
      expect(() => conn().execute('select :1, :2 from dual', [1]),
          throwsA(isA<OracleException>()));
      expect(() => conn().execute('select :a from dual', {'b': 1}),
          throwsA(isA<OracleException>()));
      await conn().ping();
    });

    test('compilation errors produce a warning', () async {
      final cursor = conn().cursor();
      await cursor.execute(
          'create or replace procedure dart_bad_proc as begin oops; end;');
      expect(cursor.warning, isNotNull);
      cursor.close();
      await conn().execute('drop procedure dart_bad_proc');
    });

    test('fetching from a non-query raises an error', () async {
      final cursor = conn().cursor();
      await cursor.execute('begin null; end;');
      expect(cursor.fetchOne, throwsA(isA<OracleException>()));
      cursor.close();
    });
  });

  group('fetching', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    test('large result sets with different array sizes', () async {
      for (final arraySize in [1, 7, 100, 5000]) {
        // small array sizes require one round trip per few rows
        final numRows = arraySize < 100 ? 1000 : 20000;
        final cursor = conn().cursor()..arraySize = arraySize;
        await cursor.execute(
            "select level, 'value ' || level, sysdate from dual "
            'connect by level <= :1',
            [numRows]);
        final rows = await cursor.fetchAll();
        expect(rows.length, numRows);
        expect(rows[999][0], 1000);
        expect(rows[999][1], 'value 1000');
        expect(cursor.rowCount, numRows);
        cursor.close();
      }
    });

    test('fetchOne, fetchMany and streams', () async {
      final cursor = conn().cursor()..arraySize = 3;
      await cursor.execute('select level from dual connect by level <= 10');
      expect(await cursor.fetchOne(), [1]);
      expect(await cursor.fetchMany(4), [
        [2],
        [3],
        [4],
        [5]
      ]);
      final rest = await cursor.rows().toList();
      expect(rest, [
        for (var i = 6; i <= 10; i++) [i]
      ]);
      expect(await cursor.fetchOne(), isNull);
      cursor.close();
    });

    test('duplicate column values across rows (bit vectors)', () async {
      final rows = await conn().query(
          "select 'same', mod(level, 2), level from dual connect by level <= 1000");
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i], ['same', (i + 1) % 2, i + 1]);
      }
    });

    test('statement cache re-executes queries', () async {
      final cursor = conn().cursor();
      for (var i = 0; i < 100; i++) {
        await cursor.execute('select :1 + 1 from dual', [i]);
        expect(await cursor.fetchOne(), [i + 1]);
      }
      cursor.close();
    });

    test('queries returning no rows', () async {
      expect(await conn().query('select 1 from dual where 1 = 0'), isEmpty);
      expect(await conn().queryOne('select 1 from dual where 1 = 0'), isNull);
    });

    test('parse describes a query without executing it', () async {
      final cursor = conn().cursor();
      await cursor.parse('select dummy, 1 as n from dual');
      expect([for (final c in cursor.description!) c.name], ['DUMMY', 'N']);
      cursor.close();
    });
  });
}
