/// Basic connection parameters for thin mode.
class ConnectParams {
  ConnectParams({
    required this.host,
    required this.port,
    required this.serviceName,
    required this.user,
    required this.password,
  });

  final String host;
  final int port;
  final String serviceName;
  final String user;
  final String password;

  factory ConnectParams.fromEnv(Map<String, String> env) {
    return ConnectParams(
      host: env['ORACLE_HOST'] ?? 'localhost',
      port: int.tryParse(env['ORACLE_PORT'] ?? '1521') ?? 1521,
      serviceName: env['ORACLE_SERVICE'] ?? 'XEPDB1',
      user: env['ORACLE_USER'] ?? 'dart_user',
      password: env['ORACLE_PASSWORD'] ?? 'dart',
    );
  }
}
