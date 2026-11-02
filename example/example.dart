// Demonstrates the main features of the driver.
//
// Connection settings are read from the environment (with defaults for a
// local Oracle Database Free container):
//
//   ORACLE_USER=dart_user ORACLE_PASSWORD=dart \
//   ORACLE_DSN=localhost:1521/FREEPDB1 dart run example/example.dart

import 'dart:io';

import 'package:oracledb_dart/oracledb_dart.dart';

Future<void> main() async {
  final env = Platform.environment;
  final conn = await OracleConnection.connect(
    user: env['ORACLE_USER'] ?? 'dart_user',
    password: env['ORACLE_PASSWORD'] ?? 'dart',
    dsn: env['ORACLE_DSN'] ?? 'localhost:1521/FREEPDB1',
  );
  print('Connected to Oracle Database ${conn.version}');

  try {
    // simple query with a bind variable
    final result = await conn.execute(
        'select :name || \' says hello\' as greeting, sysdate as now from dual',
        {'name': 'Dart'});
    print(result.maps.single);

    // create a table, insert rows in a single round trip and commit
    await conn.execute('''
      begin
        execute immediate 'drop table example_people purge';
      exception
        when others then if sqlcode != -942 then raise; end if;
      end;''');
    await conn.execute('create table example_people ('
        'id number(9) primary key, name varchar2(50), born date)');
    await conn.transaction((c) => c.executeMany(
          'insert into example_people values (:1, :2, :3)',
          [
            [1, 'Ada', DateTime.utc(1815, 12, 10)],
            [2, 'Alan', DateTime.utc(1912, 6, 23)],
            [3, 'Grace', DateTime.utc(1906, 12, 9)],
          ],
        ));

    // fetch rows with a cursor
    final cursor = conn.cursor();
    await cursor.execute(
        'select id, name, born from example_people where born < :1 order by id',
        [DateTime.utc(1910)]);
    print('columns: ${[for (final c in cursor.description!) c.name]}');
    for (var row = await cursor.fetchOne();
        row != null;
        row = await cursor.fetchOne()) {
      print('  $row');
    }

    // OUT binds with PL/SQL
    final count = cursor.variable(DbType.number);
    await cursor.execute(
        'begin select count(*) into :1 from example_people; end;', [count]);
    print('people: ${count.value}');
    cursor.close();

    // stream a large result set in batches of 1000 rows per round trip
    var total = 0;
    await for (final row
        in conn.stream('select level from dual connect by level <= 10000')) {
      total += row[0] as int;
    }
    print('sum of 1..10000 = $total');

    await conn.execute('drop table example_people purge');
  } on OracleException catch (e) {
    print('Oracle error: $e');
  } finally {
    await conn.close();
  }
}
