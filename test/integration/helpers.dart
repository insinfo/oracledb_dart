import 'dart:io';

/// Simple integration config holder sourced from environment variables.
class OracleTestConfig {
  OracleTestConfig({
    required this.enabled,
    required this.host,
    required this.port,
    required this.service,
    required this.user,
    required this.password,
  });

  final bool enabled;
  final String host;
  final int port;
  final String service;
  final String user;
  final String password;

  static OracleTestConfig fromEnv() {
    final env = Platform.environment;
    return OracleTestConfig(
      enabled: env['ORACLE_TESTS'] == '1',
      host: env['ORACLE_HOST'] ?? 'localhost',
      port: int.tryParse(env['ORACLE_PORT'] ?? '1521') ?? 1521,
      service: env['ORACLE_SERVICE'] ?? 'XEPDB1',
      user: env['ORACLE_USER'] ?? 'dart_user',
      password: env['ORACLE_PASSWORD'] ?? 'dart',
    );
  }

  Future<Socket> connectSocket({int timeoutSeconds = 3}) {
    return Socket.connect(
      host,
      port,
      timeout: Duration(seconds: timeoutSeconds),
    );
  }
}
