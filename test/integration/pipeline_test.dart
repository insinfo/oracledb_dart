@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('pipelining', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    setUpAll(() async {
      await dropTable(conn(), 'dart_pipe_t');
      await conn().execute(
          'create table dart_pipe_t (id number primary key, name varchar2(20), c clob)');
      await conn().execute('''
        create or replace function dart_pipe_f(a number) return number is
        begin
          return a * 10;
        end;''');
    });
    tearDownAll(() async {
      await dropTable(conn(), 'dart_pipe_t');
      await conn().execute('drop function dart_pipe_f');
    });

    test('runs all kinds of operations', () async {
      final pipeline = OraclePipeline()
        ..addExecute('delete from dart_pipe_t')
        ..addExecute(
            "insert into dart_pipe_t values (:1, :2, 'clob value')", [1, 'one'])
        ..addExecuteMany('insert into dart_pipe_t (id, name) values (:1, :2)', [
          for (var i = 2; i <= 3000; i++) [i, 'n$i']
        ])
        ..addFetchOne('select name from dart_pipe_t where id = :1', [1])
        ..addFetchMany('select id from dart_pipe_t order by id', numRows: 3)
        ..addFetchAll('select id from dart_pipe_t order by id', arraySize: 500)
        ..addFetchOne('select c from dart_pipe_t where id = 1')
        ..addCallFunc('dart_pipe_f', DbType.number, [4])
        ..addCallProc('dbms_output.enable')
        ..addCommit();
      final results = await conn().runPipeline(pipeline);
      expect(results.length, 10);
      expect([for (final r in results) r.error], everyElement(isNull));
      expect(results[3].rows, [
        ['one']
      ]);
      expect(results[4].rows, [
        [1],
        [2],
        [3]
      ]);
      expect(results[5].rows!.length, 3000);
      expect(results[5].rows!.last, [3000]);
      expect(results[5].columns!.single.name, 'ID');
      expect(results[6].rows, [
        ['clob value']
      ]);
      expect(results[7].returnValue, 40);
      final other = await connect();
      expect(
          (await other.queryOne('select count(*) from dart_pipe_t'))![0], 3000);
      await other.close();
    });

    test('continue on error stores the errors in the results', () async {
      final results = await conn().runPipeline(
          OraclePipeline()
            ..addFetchOne('select 1 from dual')
            ..addExecute('insert into no_such_table values (1)')
            ..addFetchOne('select 2 from dual'),
          continueOnError: true);
      expect(results[0].rows, [
        [1]
      ]);
      expect(results[1].error, isA<OracleDatabaseError>());
      expect((results[1].error as OracleDatabaseError).code, 942);
      expect(results[2].rows, [
        [2]
      ]);
    });

    test('errors abort the pipeline by default', () async {
      await expectLater(
          conn().runPipeline(OraclePipeline()
            ..addExecute('insert into no_such_table values (1)')
            ..addFetchOne('select 2 from dual')),
          throwsA(
              isA<OracleDatabaseError>().having((e) => e.code, 'code', 942)));
      // the connection remains usable
      expect(await conn().queryOne('select 3 from dual'), [3]);
    });
  });
}
