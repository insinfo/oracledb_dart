import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Placeholder for handshake/login integration once implemented.
void main() {
  final config = OracleTestConfig.fromEnv();
  final params = ConnectParams(
    host: config.host,
    port: config.port,
    serviceName: config.service,
    user: config.user,
    password: config.password,
  );

  group('integration: thin handshake', () {
    test(
      'CONNECT/ACCEPT handshake completes',
      () async {
        final conn = ThinConnection(params);
        await conn.connect();
        addTearDown(conn.close);
      },
      skip: config.enabled
          ? null
          : 'Set ORACLE_TESTS=1 to enable Oracle integration smoke tests.',
    );
  });
}
