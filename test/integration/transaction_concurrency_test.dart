@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _table = 'dart_txn_http_t';
const _requests = 40;

/// Steps of a request whose rows must be committed.
const _kept = ['outer', 'raw_kept', 'nested', 'parallel_ok'];

/// Handles `/<n>`: one unit of work mixing nested transactions, explicit
/// savepoints and parallel nested transactions, with pauses in between so
/// that concurrent requests interleave. Every fifth request fails at the
/// end and must leave no rows.
Future<void> _work(OracleConnection c, int n) async {
  Future<void> insert(String step) async {
    await c.execute(
        'insert into $_table (request, step) values (:1, :2)', [n, step]);
    await Future<void>.delayed(
        Duration(milliseconds: (n * 7 + step.length) % 5));
  }

  await c.transaction((c) async {
    await insert('outer');
    await expectLater(c.transaction((c) async {
      await insert('nested_failed');
      throw StateError('nested');
    }), throwsStateError);
    await c.savepoint('sp_raw');
    await insert('raw_kept');
    await c.savepoint('sp_raw');
    await insert('raw_undone');
    await c.rollbackToSavepoint('sp_raw');
    await c.transaction((c) => insert('nested'));
    final results = await Future.wait<Object?>([
      c.transaction((c) => insert('parallel_ok')),
      c.transaction((c) async {
        await insert('parallel_failed');
        throw StateError('parallel');
      }).then((_) => 'ok', onError: (Object e) => 'failed'),
    ]);
    expect(results[1], 'failed');
    if (n % 5 == 0) throw StateError('request $n');
  });
}

Future<HttpServer> _serve(
    Future<void> Function(int n, Future<void> Function(OracleConnection c))
        run) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final n = int.parse(request.uri.pathSegments.single);
    try {
      await run(n, (c) => _work(c, n));
      request.response.statusCode = HttpStatus.ok;
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(e);
    }
    await request.response.close();
  });
  return server;
}

/// Sends all of the requests at once and returns their status codes.
Future<List<int>> _sendAll(HttpServer server) async {
  final client = HttpClient()..maxConnectionsPerHost = _requests;
  try {
    return await Future.wait([
      for (var n = 1; n <= _requests; n++)
        client
            .get(server.address.host, server.port, '/$n')
            .then((r) => r.close())
            .then((r) async {
          await r.drain<void>();
          return r.statusCode;
        }),
    ]);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('transactions under concurrent HTTP requests',
      skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    setUp(() async {
      await dropTable(conn(), _table);
      await conn().execute('create table $_table ('
          'request number(9), step varchar2(30), '
          'primary key (request, step))');
    });
    tearDownAll(() => dropTable(conn(), _table));

    Future<void> expectCommitted(List<int> statuses) async {
      for (var n = 1; n <= _requests; n++) {
        expect(statuses[n - 1],
            n % 5 == 0 ? HttpStatus.internalServerError : HttpStatus.ok,
            reason: 'request $n');
      }
      final rows = await conn()
          .query('select request, step from $_table order by request, step');
      expect(rows, [
        for (var n = 1; n <= _requests; n++)
          if (n % 5 != 0)
            for (final step in [..._kept]..sort()) [n, step]
      ]);
    }

    test('a pooled connection per request', () async {
      final pool = await OracleConnectionPool.create(
          user: OracleTestConfig.user,
          password: OracleTestConfig.password,
          dsn: OracleTestConfig.dsn,
          min: 2,
          max: 6);
      final server = await _serve((n, work) => pool.withConnection(work));
      try {
        await expectCommitted(await _sendAll(server));
      } finally {
        await server.close(force: true);
        await pool.close(force: true);
      }
    });

    test('one connection shared by all requests', () async {
      final shared = await connect();
      final server = await _serve((n, work) => work(shared));
      try {
        await expectCommitted(await _sendAll(server));
      } finally {
        await server.close(force: true);
        await shared.close();
      }
    });

    test('raw savepoint statements on a shared connection interfere', () async {
      // Without transaction(), the requests share the session's transaction:
      // rolling back to a savepoint of one undoes the other's work.
      final shared = await connect();
      try {
        final aSaved = Completer<void>();
        final bInserted = Completer<void>();
        final a = () async {
          await shared.execute('savepoint sp_a');
          aSaved.complete();
          await bInserted.future;
          await shared.execute('rollback to savepoint sp_a');
        }();
        final b = () async {
          await aSaved.future;
          await shared
              .execute("insert into $_table (request, step) values (1, 'b')");
          bInserted.complete();
        }();
        await Future.wait([a, b]);
        await shared.commit();
        expect(await conn().query('select * from $_table'), isEmpty);
      } finally {
        await shared.close();
      }
    });
  });
}
