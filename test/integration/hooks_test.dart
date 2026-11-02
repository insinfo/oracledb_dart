@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('configuration and hooks', skip: OracleTestConfig.skipReason, () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('oracledb_cfg');
      File('${dir.path}/tnsnames.ora')
          .writeAsStringSync('test_db = (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)'
              '(HOST=${OracleTestConfig.host})(PORT=${OracleTestConfig.port}))'
              '(CONNECT_DATA=(SERVICE_NAME=${OracleTestConfig.service})))\n');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('connects using a tnsnames.ora alias', () async {
      final conn = await OracleConnection.connect(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          dsn: 'test_db',
          configDir: dir.path);
      await conn.ping();
      await conn.close();
    });

    test('config-file:// with a base64 password', () async {
      final file = File('${dir.path}/config.json')
        ..writeAsStringSync(jsonEncode({
          'prod': {
            'connect_descriptor': OracleTestConfig.dsn,
            'user': OracleTestConfig.user,
            'password': {
              'type': 'base64',
              'value': base64.encode(utf8.encode(OracleTestConfig.password)),
            },
          }
        }));
      final conn = await OracleConnection.connect(
          dsn: 'config-file://${file.path}?key=prod');
      expect((await conn.queryOne('select user from dual'))![0],
          OracleTestConfig.user.toUpperCase());
      await conn.close();
    });

    test('params hooks and custom protocols', () async {
      Future<ConnectParams> hook(ConnectParams params) async =>
          params.copyWith(password: OracleTestConfig.password);
      registerParamsHook(hook);
      registerProtocol('mydb', (protocol, argument, params) {
        expect(argument, 'primary');
        return params.withConnectString(OracleTestConfig.dsn,
            user: OracleTestConfig.user);
      });
      try {
        final conn = await OracleConnection.connect(
            password: 'replaced by the hook', dsn: 'mydb://primary');
        await conn.ping();
        await conn.close();
      } finally {
        unregisterParamsHook(hook);
        registerProtocol('mydb', null);
      }
    });
  });
}
