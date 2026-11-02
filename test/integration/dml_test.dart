@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('DML and transactions', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    setUp(() async {
      await dropTable(conn(), 'dart_dml_t');
      await conn().execute('create table dart_dml_t ('
          'id number(9) primary key, name varchar2(100), amount number(12, 2), '
          'created date)');
    });
    tearDownAll(() => dropTable(conn(), 'dart_dml_t'));

    test('insert, update and delete report row counts', () async {
      var r = await conn().execute(
          'insert into dart_dml_t (id, name) values (:1, :2)', [1, 'one']);
      expect(r.rowCount, 1);
      expect(r.lastRowid, isNotNull);
      await conn().execute(
          'insert into dart_dml_t (id, name) values (:id, :name)',
          {'id': 2, 'name': 'two'});
      r = await conn().execute("update dart_dml_t set name = name || '!'");
      expect(r.rowCount, 2);
      r = await conn().execute('delete from dart_dml_t where id = :1', [1]);
      expect(r.rowCount, 1);
      expect(await conn().query('select id, name from dart_dml_t'), [
        [2, 'two!']
      ]);
    });

    test('commit and rollback', () async {
      await conn().execute('insert into dart_dml_t (id) values (1)');
      expect(conn().transactionInProgress, isTrue);
      await conn().rollback();
      expect(conn().transactionInProgress, isFalse);
      expect((await conn().queryOne('select count(*) from dart_dml_t'))![0], 0);
      await conn().execute('insert into dart_dml_t (id) values (2)');
      await conn().commit();
      final other = await connect();
      expect((await other.queryOne('select count(*) from dart_dml_t'))![0], 1);
      await other.close();
    });

    test('autocommit', () async {
      conn().autocommit = true;
      try {
        await conn().execute('insert into dart_dml_t (id) values (1)');
        expect(conn().transactionInProgress, isFalse);
        final other = await connect();
        expect(
            (await other.queryOne('select count(*) from dart_dml_t'))![0], 1);
        await other.close();
      } finally {
        conn().autocommit = false;
      }
    });

    test('transaction helper', () async {
      await conn().transaction(
          (c) => c.execute('insert into dart_dml_t (id) values (1)'));
      await expectLater(
          conn().transaction((c) async {
            await c.execute('insert into dart_dml_t (id) values (2)');
            throw StateError('fail');
          }),
          throwsStateError);
      expect(await conn().query('select id from dart_dml_t'), [
        [1]
      ]);
    });

    test('savepoints', () async {
      await conn().execute('insert into dart_dml_t (id) values (1)');
      await conn().savepoint('sp_a');
      await conn().execute('insert into dart_dml_t (id) values (2)');
      await conn().savepoint('sp_b');
      await conn().execute('insert into dart_dml_t (id) values (3)');
      await conn().rollbackToSavepoint('sp_b');
      expect(await conn().query('select id from dart_dml_t order by id'), [
        [1],
        [2]
      ]);
      await conn().rollbackToSavepoint('sp_a');
      expect(conn().transactionInProgress, isTrue);
      await conn().commit();
      expect(await conn().query('select id from dart_dml_t'), [
        [1]
      ]);
      // commit erases the savepoints
      await expectLater(
          conn().rollbackToSavepoint('sp_a'), throwsA(isA<OracleException>()));
      expect(() => conn().savepoint('bad name'), throwsArgumentError);
      expect(() => conn().rollbackToSavepoint('1sp'), throwsArgumentError);
    });

    test('nested transaction helper uses savepoints', () async {
      await conn().transaction((c) async {
        await c.execute('insert into dart_dml_t (id) values (1)');
        await expectLater(c.transaction((c) async {
          await c.execute('insert into dart_dml_t (id) values (2)');
          throw StateError('fail');
        }), throwsStateError);
        await c.transaction((c) async {
          await c.execute('insert into dart_dml_t (id) values (3)');
          await expectLater(c.transaction((c) async {
            await c.execute('insert into dart_dml_t (id) values (4)');
            throw StateError('fail');
          }), throwsStateError);
        });
      });
      expect(await conn().query('select id from dart_dml_t order by id'), [
        [1],
        [3]
      ]);
      await expectLater(
          conn().transaction((c) async {
            await c.execute('insert into dart_dml_t (id) values (5)');
            await c.transaction(
                (c) => c.execute('insert into dart_dml_t (id) values (6)'));
            throw StateError('fail');
          }),
          throwsStateError);
      expect(await conn().query('select id from dart_dml_t order by id'), [
        [1],
        [3]
      ]);
    });

    test('executeMany with positional and named binds', () async {
      final rows = [
        for (var i = 0; i < 1000; i++)
          [i, 'name $i', i * 1.5, DateTime.utc(2020, 1, 1 + i % 28)]
      ];
      final count = await conn()
          .executeMany('insert into dart_dml_t values (:1, :2, :3, :4)', rows);
      expect(count, 1000);
      await conn()
          .executeMany('update dart_dml_t set name = :name where id = :id', [
        {'id': 1, 'name': 'first'},
        {'id': 2, 'name': null},
      ]);
      final fetched = await conn().query(
          'select id, name, amount, created from dart_dml_t order by id');
      expect(fetched.length, 1000);
      expect(fetched[1], [1, 'first', 1.5, DateTime.utc(2020, 1, 2)]);
      expect(fetched[2][1], isNull);
      expect(
          fetched[999], [999, 'name 999', 1498.5, DateTime.utc(2020, 1, 20)]);
    });

    test('executeMany with nulls and mixed numeric types', () async {
      await conn().executeMany(
          'insert into dart_dml_t (id, name, amount) values (:1, :2, :3)', [
        [1, null, null],
        [2, 'x', 2],
        [3, null, 3.75],
      ]);
      expect(
          await conn()
              .query('select id, name, amount from dart_dml_t order by id'),
          [
            [1, null, null],
            [2, 'x', 2.0],
            [3, null, 3.75],
          ]);
    });

    test('executeMany with batch errors and DML row counts', () async {
      final cursor = conn().cursor();
      await cursor.executeMany(
          'insert into dart_dml_t (id) values (:1)',
          [
            [1],
            [2],
            [1],
            [3],
            [2]
          ],
          batchErrors: true);
      final errors = cursor.batchErrors!;
      expect([for (final e in errors) e.offset], [2, 4]);
      expect(errors.first.code, 1);
      expect(errors.first.message, contains('ORA-00001'));
      await conn().rollback();

      await conn()
          .executeMany('insert into dart_dml_t (id, name) values (:1, :2)', [
        for (var i = 0; i < 5; i++) [i, 'n${i % 2}']
      ]);
      await cursor.executeMany(
          'delete from dart_dml_t where name = :1',
          [
            ['n0'],
            ['n1'],
            ['zz']
          ],
          arrayDmlRowCounts: true);
      expect(cursor.dmlRowCounts, [3, 2, 0]);
      cursor.close();
    });

    test('unique constraint violation raises an integrity error', () async {
      await conn().execute('insert into dart_dml_t (id) values (1)');
      await expectLater(
          conn().execute('insert into dart_dml_t (id) values (1)'),
          throwsA(isA<OracleIntegrityError>()
              .having((e) => e.code, 'code', 1)
              .having((e) => e.message, 'message', contains('ORA-00001'))));
      // the connection remains usable afterwards
      expect((await conn().queryOne('select count(*) from dart_dml_t'))![0], 1);
    });

    test('DML returning', () async {
      final cursor = conn().cursor();
      final idVar = cursor.variable(DbType.number);
      final nameVar = cursor.variable(DbType.varchar, size: 100);
      await cursor.execute(
          "insert into dart_dml_t (id, name) values (:1, 'ret') "
          'returning id, name into :2, :3',
          [10, idVar, nameVar]);
      expect(idVar.value, [10]);
      expect(nameVar.value, ['ret']);
      await conn().executeMany('insert into dart_dml_t (id) values (:1)', [
        [11],
        [12]
      ]);
      await cursor.execute(
          "update dart_dml_t set name = 'u' where id > :1 returning id into :2",
          [10, idVar]);
      expect((idVar.value as List)..sort(), [11, 12]);
      cursor.close();
    });

    test('re-execution reuses the cursor and handles size changes', () async {
      final cursor = conn().cursor();
      for (var i = 0; i < 50; i++) {
        await cursor.execute(
            'insert into dart_dml_t (id, name) values (:1, :2)',
            [i, 'n' * (i + 1)]);
      }
      cursor.close();
      final rows = await conn()
          .query('select id, length(name) from dart_dml_t order by id');
      expect(rows.length, 50);
      expect(rows.last, [49, 50]);
    });

    test('DDL statements', () async {
      await conn().execute('alter table dart_dml_t add (extra varchar2(10))');
      await conn()
          .execute("insert into dart_dml_t (id, extra) values (1, 'e')");
      expect((await conn().queryOne('select extra from dart_dml_t'))![0], 'e');
    });
  });
}
