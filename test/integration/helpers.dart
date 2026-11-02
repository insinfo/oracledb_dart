import 'dart:io';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

/// Integration test configuration sourced from environment variables.
///
///   ORACLE_HOST (localhost), ORACLE_PORT (1521), ORACLE_SERVICE (FREEPDB1),
///   ORACLE_USER (dart_user), ORACLE_PASSWORD (dart)
///
/// Set ORACLE_TESTS=0 to skip the integration tests.
class OracleTestConfig {
  OracleTestConfig._();

  static final Map<String, String> _env = Platform.environment;

  static bool get enabled => _env['ORACLE_TESTS'] != '0';
  static String get host => _env['ORACLE_HOST'] ?? 'localhost';
  static int get port => int.parse(_env['ORACLE_PORT'] ?? '1521');
  static String get service => _env['ORACLE_SERVICE'] ?? 'FREEPDB1';
  static String get user => _env['ORACLE_USER'] ?? 'dart_user';
  static String get password => _env['ORACLE_PASSWORD'] ?? 'dart';
  static String get dsn => '$host:$port/$service';

  static String? get skipReason =>
      enabled ? null : 'ORACLE_TESTS=0: integration tests disabled';
}

Future<OracleConnection> connect() => OracleConnection.connect(
    user: OracleTestConfig.user,
    password: OracleTestConfig.password,
    dsn: OracleTestConfig.dsn);

/// Opens a connection for the tests of the enclosing group and closes it
/// when they are done.
OracleConnection Function() sharedConnection() {
  late OracleConnection conn;
  setUpAll(() async => conn = await connect());
  tearDownAll(() async => conn.close());
  return () => conn;
}

/// Drops the table if it exists.
Future<void> dropTable(OracleConnection conn, String name) async {
  await conn.execute('''
    begin
      execute immediate 'drop table $name purge';
    exception
      when others then
        if sqlcode != -942 then raise; end if;
    end;''');
}
