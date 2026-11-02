@Tags(['integration'])
library;

import 'dart:io';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// TLS tests run when ORACLE_TCPS_WALLET points to a directory containing an
/// ewallet.pem file with the certificate authority of the server (the port
/// is given by ORACLE_TCPS_PORT, default 2484).
void main() {
  final env = Platform.environment;
  final wallet = env['ORACLE_TCPS_WALLET'];
  final port = env['ORACLE_TCPS_PORT'] ?? '2484';
  final skip = OracleTestConfig.skipReason ??
      (wallet == null ? 'ORACLE_TCPS_WALLET is not set' : null);
  final base =
      'tcps://${OracleTestConfig.host}:$port/${OracleTestConfig.service}';

  Future<OracleConnection> connectTls(String dsn) => OracleConnection.connect(
      user: OracleTestConfig.user,
      password: OracleTestConfig.password,
      dsn: dsn);

  group('TLS', skip: skip, () {
    test('connects with a wallet', () async {
      final conn = await connectTls('$base?wallet_location=$wallet');
      final row = await conn.queryOne(
          "select sys_context('userenv', 'network_protocol') from dual");
      expect(row![0], 'tcps');
      // the session works normally over TLS
      final rows =
          await conn.query('select level from dual connect by level <= 5000');
      expect(rows.length, 5000);
      await conn.close();
    });

    test('connects with a connect descriptor and wallet parameter', () async {
      final conn = await OracleConnection.connect(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          walletLocation: wallet,
          dsn: '(DESCRIPTION=(ADDRESS=(PROTOCOL=tcps)'
              '(HOST=${OracleTestConfig.host})(PORT=$port))'
              '(CONNECT_DATA=(SERVICE_NAME=${OracleTestConfig.service})))');
      await conn.ping();
      await conn.close();
    });

    test('checks the server certificate DN', () async {
      final conn = await connectTls(
          '$base?wallet_location=$wallet&ssl_server_cert_dn="CN=localhost"');
      await conn.close();
      await expectLater(
          connectTls(
              '$base?wallet_location=$wallet&ssl_server_cert_dn="CN=other"'),
          throwsA(isA<OracleException>()
              .having((e) => e.fullCode, 'fullCode', 'DPY-6002')));
    });

    test('rejects untrusted certificates', () async {
      await expectLater(connectTls(base), throwsA(isA<OracleException>()));
    });

    test('token authentication messages are validated by the server', () async {
      // a token that has not expired but is not valid for the database
      const token = 'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.';
      final key = File('test/fixtures/rsa_pkcs8.pem').readAsStringSync();
      for (final privateKey in [null, key]) {
        await expectLater(
            OracleConnection.connect(
                dsn: '$base?wallet_location=$wallet',
                accessToken: token,
                privateKey: privateKey),
            throwsA(isA<OracleDatabaseError>()
                .having((e) => e.code, 'code', 1017)));
      }
      await expectLater(
          OracleConnection.connect(
              dsn: '$base?wallet_location=$wallet',
              accessToken: 'eyJhbGciOiJub25lIn0.eyJleHAiOjEwMDB9.'),
          throwsA(isA<OracleException>()
              .having((e) => e.fullCode, 'fullCode', 'DPY-2033')));
    });
  });
}
