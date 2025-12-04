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
    //final env = Platform.environment;
    return OracleTestConfig(
      // Default to enabled; set ORACLE_TESTS=0 to skip integration tests.
      enabled: true,
      host: 'localhost',
      port: 1521,
      service: 'XEPDB1',
      user: 'dart_user',
      password: 'dart',
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
