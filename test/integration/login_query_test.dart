import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Placeholder for full login + query integration once TTC auth is implemented.
void main() {
  final config = OracleTestConfig.fromEnv();
  final params = ConnectParams(
    host: config.host,
    port: config.port,
    serviceName: config.service,
    user: config.user,
    password: config.password,
  );

  group('integration: login + query', () {
    test(
      'logon and run SELECT 1 FROM dual',
      () async {
        final conn = ThinConnection(params);
        await conn.connect(); // TODO: add auth + execute query
        addTearDown(conn.close);
      },
      skip: config.enabled
          ? 'Auth/session setup not yet implemented; enable once TTC login is ready.'
          : 'Set ORACLE_TESTS=1 to enable Oracle integration smoke tests.',
    );
  });
}
