@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<OracleConnectionPool> createPool({
  int min = 1,
  int max = 3,
  int increment = 1,
  PoolGetMode getMode = PoolGetMode.wait,
  Duration? waitTimeout,
  Duration? timeout,
  SessionCallback? sessionCallback,
}) =>
    OracleConnectionPool.create(
      user: OracleTestConfig.user,
      password: OracleTestConfig.password,
      dsn: OracleTestConfig.dsn,
      min: min,
      max: max,
      increment: increment,
      getMode: getMode,
      waitTimeout: waitTimeout,
      timeout: timeout,
      sessionCallback: sessionCallback,
    );

void main() {
  group('connection pool', skip: OracleTestConfig.skipReason, () {
    test('opens the minimum and grows up to the maximum', () async {
      final pool = await createPool(min: 2, max: 4, increment: 2);
      expect(pool.opened, 2);
      final sessions = <int>{};
      await Future.wait([
        for (var i = 0; i < 20; i++)
          pool.withConnection((conn) async {
            expect(pool.busy, lessThanOrEqualTo(4));
            final row = await conn
                .queryOne("select sys_context('userenv', 'sid') from dual");
            sessions.add(int.parse(row![0] as String));
          }),
      ]);
      expect(pool.opened, lessThanOrEqualTo(4));
      expect(sessions.length, lessThanOrEqualTo(4));
      expect(pool.busy, 0);
      await pool.close();
      expect(pool.acquire, throwsA(isA<OracleException>()));
    });

    test('no wait and timed wait modes', () async {
      final pool = await createPool(max: 1, getMode: PoolGetMode.noWait);
      final conn = await pool.acquire();
      await expectLater(pool.acquire(), throwsA(isA<OracleException>()));
      await conn.close();
      await pool.close();

      final timed = await createPool(
          max: 1,
          getMode: PoolGetMode.timedWait,
          waitTimeout: const Duration(milliseconds: 200));
      final held = await timed.acquire();
      final sw = Stopwatch()..start();
      await expectLater(timed.acquire(), throwsA(isA<OracleException>()));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150));
      // a waiter is served when a connection is released
      final waiting = timed.acquire();
      await held.close();
      final next = await waiting;
      await next.close();
      await timed.close();
    });

    test('released connections are rolled back and invalidated', () async {
      final pool = await createPool(max: 1);
      await pool.withConnection((c) async {
        await dropTable(c, 'dart_pool_t');
        await c.execute('create table dart_pool_t (x number)');
      });
      final conn = await pool.acquire();
      await conn.execute('insert into dart_pool_t values (1)');
      expect(conn.transactionInProgress, isTrue);
      await conn.close();
      expect(() => conn.query('select 1 from dual'),
          throwsA(isA<OracleException>()));
      final again = await pool.acquire();
      expect((await again.queryOne('select count(*) from dart_pool_t'))![0], 0);
      await dropTable(again, 'dart_pool_t');
      await again.close();
      await pool.close();
    });

    test('session callback runs once per new session', () async {
      var calls = 0;
      final pool = await createPool(
          min: 1,
          max: 1,
          sessionCallback: (conn) async {
            calls++;
            await conn
                .execute("alter session set nls_date_format = 'YYYY-MM-DD'");
          });
      for (var i = 0; i < 3; i++) {
        await pool.withConnection((conn) async {
          final row =
              await conn.queryOne("select value from nls_session_parameters "
                  "where parameter = 'NLS_DATE_FORMAT'");
          expect(row![0], 'YYYY-MM-DD');
        });
      }
      expect(calls, 1);
      await pool.close();
    });

    test('broken connections are replaced', () async {
      final pool = await createPool(min: 1, max: 1);
      final conn = await pool.acquire();
      conn.impl.protocol.forceDisconnect();
      await conn.close();
      final fresh = await pool.acquire();
      expect(await fresh.queryOne('select 1 from dual'), [1]);
      await fresh.close();
      await pool.close();
    });

    test('idle connections above the minimum are closed', () async {
      final pool = await createPool(
          min: 1, max: 3, timeout: const Duration(milliseconds: 300));
      final conns = [for (var i = 0; i < 3; i++) await pool.acquire()];
      expect(pool.opened, 3);
      for (final c in conns) {
        await c.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(pool.opened, 1);
      await pool.close();
    });

    test('closing a pool with busy connections', () async {
      final pool = await createPool();
      final conn = await pool.acquire();
      await expectLater(pool.close(), throwsA(isA<OracleException>()));
      await pool.close(force: true);
      expect(pool.isClosed, isTrue);
      await conn.close();
    });
  });
}
