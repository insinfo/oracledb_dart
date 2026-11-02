@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('connection', skip: OracleTestConfig.skipReason, () {
    test('connects and reports server information', () async {
      final conn = await connect();
      expect(conn.serverVersion.first, greaterThanOrEqualTo(19));
      expect(conn.sessionId, greaterThan(0));
      expect(conn.serviceName, isNotNull);
      expect(conn.isHealthy, isTrue);
      await conn.ping();
      await conn.close();
      expect(conn.isClosed, isTrue);
      expect(conn.ping, throwsA(isA<OracleInterfaceError>()));
    });

    test('connects using host, port and service name', () async {
      final conn = await OracleConnection.connect(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          host: OracleTestConfig.host,
          port: OracleTestConfig.port,
          serviceName: OracleTestConfig.service);
      expect((await conn.queryOne('select user from dual'))![0],
          OracleTestConfig.user.toUpperCase());
      await conn.close();
    });

    test('connects using a connect descriptor', () async {
      final conn = await OracleConnection.connect(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          dsn: '(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)'
              '(HOST=${OracleTestConfig.host})(PORT=${OracleTestConfig.port}))'
              '(CONNECT_DATA=(SERVICE_NAME=${OracleTestConfig.service})))');
      await conn.ping();
      await conn.close();
    });

    test('invalid credentials raise ORA-01017', () async {
      await expectLater(
          OracleConnection.connect(
              user: OracleTestConfig.user,
              password: 'wrong-password',
              dsn: OracleTestConfig.dsn),
          throwsA(
              isA<OracleDatabaseError>().having((e) => e.code, 'code', 1017)));
    });

    test('invalid service name raises DPY-6001', () async {
      await expectLater(
          OracleConnection.connect(
              user: OracleTestConfig.user,
              password: OracleTestConfig.password,
              dsn: '${OracleTestConfig.host}:${OracleTestConfig.port}/no_such'),
          throwsA(isA<OracleException>()
              .having((e) => e.fullCode, 'fullCode', 'DPY-6001')));
    });

    test('larger SDU can be negotiated', () async {
      final conn = await OracleConnection.connect(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          dsn: OracleTestConfig.dsn,
          sdu: 65535);
      expect(conn.sdu, greaterThanOrEqualTo(8192));
      final rows =
          await conn.query('select level, rpad(\'x\', 1000, \'x\') from dual '
              'connect by level <= 500');
      expect(rows.length, 500);
      await conn.close();
    });

    test('concurrent requests on one connection are serialized', () async {
      final conn = await connect();
      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          conn.queryOne('select :1 * 2 from dual', [i]),
      ]);
      expect([for (final r in results) r![0]],
          [for (var i = 0; i < 20; i++) i * 2]);
      await conn.close();
    });

    test('end-to-end attributes are sent', () async {
      final conn = await connect();
      conn.module = 'dart-module';
      conn.action = 'dart-action';
      conn.clientIdentifier = 'dart-client';
      final row =
          await conn.queryOne("select sys_context('userenv', 'module'), "
              "sys_context('userenv', 'action'), "
              "sys_context('userenv', 'client_identifier') from dual");
      expect(row, ['dart-module', 'dart-action', 'dart-client']);
      await conn.close();
    });

    test('current schema can be changed', () async {
      final conn = await connect();
      conn.currentSchema = 'SYS';
      final row = await conn.queryOne(
          "select sys_context('userenv', 'current_schema') from dual");
      expect(row![0], 'SYS');
      await conn.close();
    });

    test('question mark placeholders', () async {
      final conn = await OracleConnection.connect(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          dsn: OracleTestConfig.dsn,
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
      expect(await conn.queryOne("select ? || '?', ? + 1 from dual", ['a', 41]),
          ['a?', 42]);
      await dropTable(conn, 'dart_qmark_t');
      await conn
          .execute('create table dart_qmark_t (id number, name varchar2(20))');
      await conn.executeMany('insert into dart_qmark_t values (?, ?)', [
        [1, 'one'],
        [2, 'two'],
      ]);
      expect(
          await conn.query(
              'select name from dart_qmark_t where id > ? order by id', [0]),
          [
            ['one'],
            ['two']
          ]);
      // the style can be overridden per cursor
      final cursor = conn.cursor()
        ..placeholderIdentifier = PlaceholderIdentifier.colon;
      await cursor
          .execute('select name from dart_qmark_t where id = :id', {'id': 2});
      expect(await cursor.fetchOne(), ['two']);
      cursor.close();
      await dropTable(conn, 'dart_qmark_t');
      await conn.close();
    });

    // a CPU bound query: the server checks for in-band breaks while it runs
    const longQuery = 'select count(*) from dual connect by level <= 300000000';

    test('call timeout interrupts long calls', () async {
      final conn = await connect();
      conn.callTimeout = const Duration(milliseconds: 500);
      await expectLater(
          conn.execute(longQuery),
          throwsA(isA<OracleException>()
              .having((e) => e.fullCode, 'fullCode', 'DPY-4024')));
      expect(await conn.queryOne('select 1 from dual'), [1]);
      conn.callTimeout = null;
      await conn.close();
    });

    test('cancel interrupts the call in progress', () async {
      final conn = await connect();
      final call = conn.execute(longQuery);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      conn.cancel();
      await expectLater(
          call,
          throwsA(
              isA<OracleDatabaseError>().having((e) => e.code, 'code', 1013)));
      expect(await conn.queryOne('select 2 from dual'), [2]);
      conn.cancel(); // no call in progress: no effect
      expect(await conn.queryOne('select 3 from dual'), [3]);
      await conn.close();
    });

    test('token authentication requires TLS', () async {
      await expectLater(
          OracleConnection.connect(dsn: OracleTestConfig.dsn, accessToken: 'x'),
          throwsA(isA<OracleException>()
              .having((e) => e.fullCode, 'fullCode', 'DPY-2034')));
    });
  });
}
