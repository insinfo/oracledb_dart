import 'package:test/test.dart';

import 'helpers.dart';

/// Basic integration smoke test: verifies the Oracle listener is reachable.
void main() {
  final config = OracleTestConfig.fromEnv();
  group('integration: oracle listener', () {
    test(
      'listener is reachable on ${config.host}:${config.port}',
      () async {
        final socket = await config.connectSocket(timeoutSeconds: 3);
        addTearDown(socket.destroy);
      },
      skip: config.enabled
          ? false
          : 'Set ORACLE_TESTS=1 to enable Oracle integration smoke tests.',
    );
  });
}
