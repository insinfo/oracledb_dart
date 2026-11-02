@Tags(['integration'])
library;

import 'dart:io';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// These tests require the default DRCP pool to be started in the database
/// (dbms_connection_pool.start_pool), as done by tool/ci/startdb.
void main() {
  final pooledDsn = '${OracleTestConfig.dsn}:pooled';
  final systemPassword =
      Platform.environment['ORACLE_SYSTEM_PASSWORD'] ?? 'oracle';
  final cdbService = Platform.environment['ORACLE_CDB_SERVICE'] ?? 'FREE';

  group('DRCP', skip: OracleTestConfig.skipReason, () {
    test('standalone connections use pooled servers', () async {
      for (var i = 0; i < 3; i++) {
        final conn = await OracleConnection.connect(
            user: OracleTestConfig.user,
            password: OracleTestConfig.password,
            dsn: pooledDsn,
            cclass: 'DART_STANDALONE');
        expect(await conn.queryOne('select 1 from dual'), [1]);
        await conn.close();
      }
    });

    test('client pools release sessions to the database pool', () async {
      final pool = await OracleConnectionPool.create(
        params: ConnectParams.fromDsn(pooledDsn,
            user: OracleTestConfig.user,
            password: OracleTestConfig.password,
            cclass: 'DART_POOL'),
        min: 1,
        max: 2,
      );
      await pool.withConnection((conn) async {
        await dropTable(conn, 'dart_drcp_t');
        await conn.execute('create table dart_drcp_t (x number)');
      });
      for (var i = 0; i < 5; i++) {
        await pool.withConnection((conn) async {
          // statements cached before the session was released are parsed
          // again on the new session
          final row = await conn
              .queryOne('select count(*) from dart_drcp_t where x > :1', [-1]);
          expect(row![0], 0);
          // uncommitted changes are rolled back on release
          await conn.execute('insert into dart_drcp_t values (:1)', [i]);
        });
      }
      await pool.withConnection((conn) => dropTable(conn, 'dart_drcp_t'));
      await pool.close();

      // the DRCP statistics (visible in the root container) show that the
      // pooled servers of the connection class were reused
      final system = await OracleConnection.connect(
          user: 'system',
          password: systemPassword,
          dsn: '${OracleTestConfig.host}:${OracleTestConfig.port}/$cdbService');
      final row = await system.queryOne(
          'select sum(num_requests), sum(num_hits) from v\$cpool_cc_stats '
          "where cclass_name like '%.DART_POOL'");
      expect(row![0], greaterThanOrEqualTo(6));
      expect(row[1], greaterThan(0));
      await system.close();
    });
  });
}
