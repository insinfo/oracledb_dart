@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _accounts = 'dart_rest_accounts';
const _transfers = 'dart_rest_transfers';
const _numbers = 'dart_rest_numbers';

/// A small REST API over a connection pool, written the way a backend
/// would be: one pooled connection per request, errors mapped to statuses.
class _Api {
  _Api(this.pool);

  final OracleConnectionPool pool;
  late final HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> stop() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final body = await utf8.decodeStream(request);
      final json = body.isEmpty ? null : jsonDecode(body);
      await pool.withConnection((conn) => _route(conn, request, json));
    } on OracleException catch (e) {
      final status = switch (e.fullCode) {
        'DPY-4005' => HttpStatus.serviceUnavailable,
        'DPY-4024' => HttpStatus.gatewayTimeout,
        _ => HttpStatus.internalServerError,
      };
      await _send(response, status, {'error': '$e'});
    } on StateError catch (e) {
      await _send(response, HttpStatus.conflict, {'error': e.message});
    } catch (e) {
      await _send(response, HttpStatus.internalServerError, {'error': '$e'});
    }
  }

  Future<void> _send(HttpResponse response, int status, Object? json) async {
    try {
      response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(json));
      await response.close();
    } catch (_) {
      // the client went away (or the streamed response already started)
    }
  }

  Future<void> _route(
      OracleConnection conn, HttpRequest request, Object? json) async {
    final response = request.response;
    final path = request.uri.pathSegments;
    final query = request.uri.queryParameters;
    switch ((request.method, path)) {
      case ('GET', ['accounts', final id]):
        final row = await conn.queryOne(
            'select id, owner, balance from $_accounts where id = :1',
            [int.parse(id)]);
        if (row == null) {
          return _send(response, HttpStatus.notFound, {'error': 'not found'});
        }
        return _send(response, HttpStatus.ok,
            {'id': row[0], 'owner': row[1], 'balance': row[2]});

      case ('POST', ['transfers']):
        final t = json as Map<String, Object?>;
        final from = t['from'] as int, to = t['to'] as int;
        final amount = t['amount'] as int;
        final id = await conn.transaction((c) async {
          // lock in id order so that concurrent transfers cannot deadlock
          final locked = await c.query(
              'select id, balance from $_accounts where id in (:1, :2) '
              'order by id for update',
              [from, to]);
          final balances = {for (final r in locked) r[0]: r[1] as int};
          if (balances[from]! < amount) {
            throw StateError('insufficient funds in $from');
          }
          await c.execute(
              'update $_accounts set balance = balance - :1 where id = :2',
              [amount, from]);
          await c.execute(
              'update $_accounts set balance = balance + :1 where id = :2',
              [amount, to]);
          final cursor = c.cursor();
          try {
            final out = cursor.variable(DbType.number);
            await cursor.execute(
                'insert into $_transfers (from_id, to_id, amount) '
                'values (:1, :2, :3) returning id into :4',
                [from, to, amount, out]);
            return (out.value as List).single;
          } finally {
            cursor.close();
          }
        });
        return _send(response, HttpStatus.created, {'id': id});

      case ('GET', ['numbers']):
        // streams a large result as JSON lines
        response.headers.contentType = ContentType('application', 'x-ndjson');
        await response.addStream(conn
            .stream('select n, rpad(\'x\', 100, \'x\') from $_numbers '
                'order by n')
            .map((r) => utf8.encode('${jsonEncode(r)}\n')));
        return response.close();

      case ('GET', ['sleep']):
        conn.callTimeout = Duration(milliseconds: int.parse(query['timeout']!));
        await conn.execute('begin dbms_session.sleep(:1); end;',
            [int.parse(query['ms']!) / 1000]);
        return _send(response, HttpStatus.ok, {'slept': true});

      case ('POST', ['accounts', final id, 'lock']):
        // waits for the row lock (held elsewhere) within the call timeout
        conn.callTimeout = Duration(milliseconds: int.parse(query['timeout']!));
        await conn.transaction((c) => c.query(
            'select balance from $_accounts where id = :1 for update',
            [int.parse(id)]));
        return _send(response, HttpStatus.ok, {'locked': true});

      case ('POST', ['broken']):
        // leaves a transaction open and fails: the pool must roll it back
        await conn.execute(
            "insert into $_accounts (id, owner, balance) values (-1, 'x', 0)");
        throw Exception('handler bug');

      case ('POST', ['careless']):
        // changes settings of the session and never restores them
        conn
          ..autocommit = true
          ..callTimeout = const Duration(milliseconds: 1);
        return _send(response, HttpStatus.ok, {});

      case ('GET', ['session']):
        final row = await conn.queryOne("select sys_context('userenv', 'sid'), "
            "sys_context('userenv', 'sessionid') from dual");
        return _send(response, HttpStatus.ok, {
          'sid': row![0],
          'audsid': row[1],
          'autocommit': conn.autocommit,
          'callTimeout': conn.callTimeout?.inMilliseconds,
          'transactionInProgress': conn.transactionInProgress,
        });

      default:
        return _send(response, HttpStatus.notFound, {'error': 'no route'});
    }
  }
}

class _Response {
  _Response(this.status, this.json);
  final int status;
  final Object? json;
}

class _Client {
  _Client(this.server) : http = HttpClient()..maxConnectionsPerHost = 64;

  final HttpServer server;
  final HttpClient http;

  Future<_Response> send(String method, String path, [Object? json]) async {
    final request =
        await http.open(method, server.address.host, server.port, path);
    if (json != null) request.write(jsonEncode(json));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final lines = response.headers.contentType?.subType == 'x-ndjson';
    return _Response(
        response.statusCode,
        body.isEmpty
            ? null
            : lines
                ? const LineSplitter().convert(body).map(jsonDecode).toList()
                : jsonDecode(body));
  }

  void close() => http.close(force: true);
}

Future<OracleConnectionPool> _createPool(
        {int min = 2,
        int max = 8,
        PoolGetMode getMode = PoolGetMode.wait,
        Duration? waitTimeout}) =>
    OracleConnectionPool.create(
        user: OracleTestConfig.user,
        password: OracleTestConfig.password,
        dsn: OracleTestConfig.dsn,
        min: min,
        max: max,
        getMode: getMode,
        waitTimeout: waitTimeout);

/// Waits until the pool has no acquired connections.
Future<void> _idle(OracleConnectionPool pool) async {
  for (var i = 0; i < 100 && pool.busy > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(pool.busy, 0, reason: 'connections leaked by the requests');
}

void main() {
  group('REST API over HttpServer', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();
    late OracleConnectionPool pool;
    late _Api api;
    late _Client client;

    setUpAll(() async {
      await dropTable(conn(), _numbers);
      await conn()
          .execute('create table $_numbers (n number(9), pad varchar2(100))');
      await conn().execute('insert into $_numbers '
          "select level, rpad('x', 100, 'x') from dual connect by level <= 20000");
      await conn().commit();
    });

    setUp(() async {
      await dropTable(conn(), _transfers);
      await dropTable(conn(), _accounts);
      await conn().execute('create table $_accounts ('
          'id number(9) primary key, owner varchar2(30), '
          'balance number(12) check (balance >= 0))');
      await conn().execute('create table $_transfers ('
          'id number generated always as identity primary key, '
          'from_id number(9), to_id number(9), amount number(12))');
      await conn().executeMany('insert into $_accounts values (:1, :2, 1000)', [
        for (var i = 1; i <= 20; i++) [i, 'owner $i']
      ]);
      await conn().commit();
    });

    tearDown(() async {
      client.close();
      await api.stop();
      await pool.close(force: true);
    });

    tearDownAll(() async {
      await dropTable(conn(), _transfers);
      await dropTable(conn(), _accounts);
      await dropTable(conn(), _numbers);
    });

    Future<void> startApi(Future<OracleConnectionPool> created) async {
      pool = await created;
      api = _Api(pool);
      await api.start();
      client = _Client(api.server);
    }

    test('concurrent transfers keep the balances consistent', () async {
      await startApi(_createPool());
      final random = Random(42);
      final responses = await Future.wait([
        for (var i = 0; i < 300; i++)
          () {
            final from = random.nextInt(20) + 1;
            final to = (from + random.nextInt(19)) % 20 + 1;
            return client.send('POST', '/transfers',
                {'from': from, 'to': to, 'amount': random.nextInt(400) + 1});
          }(),
        for (var i = 0; i < 100; i++)
          client.send('GET', '/accounts/${random.nextInt(20) + 1}'),
      ]);
      final statuses = responses.map((r) => r.status).toSet();
      expect(statuses.difference({200, 201, 409}), isEmpty,
          reason:
              '${responses.where((r) => r.status >= 500).map((r) => r.json)}');
      final created = responses.where((r) => r.status == 201).length;
      expect(created, greaterThan(0));

      expect(
          await conn()
              .queryOne('select sum(balance), min(balance) from $_accounts'),
          [20000, greaterThanOrEqualTo(0)]);
      expect(
          await conn().queryOne('select count(*) from $_transfers'), [created]);
      // replaying the committed transfers gives the same balances
      final balances = {for (var i = 1; i <= 20; i++) i: 1000};
      for (final t in await conn()
          .query('select from_id, to_id, amount from $_transfers')) {
        balances[t[0] as int] = balances[t[0]]! - (t[2] as int);
        balances[t[1] as int] = balances[t[1]]! + (t[2] as int);
      }
      expect(
          await conn().query('select id, balance from $_accounts order by id'),
          [
            for (final e in balances.entries) [e.key, e.value]
          ]);
      await _idle(pool);
    });

    test('an exhausted pool answers 503 and then recovers', () async {
      await startApi(_createPool(
          min: 1,
          max: 2,
          getMode: PoolGetMode.timedWait,
          waitTimeout: const Duration(milliseconds: 300)));
      final responses = await Future.wait([
        for (var i = 0; i < 8; i++)
          client.send('GET', '/sleep?ms=1000&timeout=5000'),
      ]);
      expect(responses.where((r) => r.status == 200).length, 2);
      expect(responses.where((r) => r.status == 503).length, 6);
      await _idle(pool);
      final after = await Future.wait(
          [for (var i = 1; i <= 10; i++) client.send('GET', '/accounts/$i')]);
      expect(after.map((r) => r.status), everyElement(200));
    });

    test('a call timeout answers 504 and the session stays usable', () async {
      await startApi(_createPool(min: 1, max: 1));
      final timedOut = await client.send('GET', '/sleep?ms=3000&timeout=200');
      expect(timedOut.status, HttpStatus.gatewayTimeout);
      final ok = await client.send('GET', '/accounts/1');
      expect(ok.status, 200);
      expect(pool.opened, 1);
      await _idle(pool);
    });

    test('a transaction left open by a failing handler is rolled back',
        () async {
      await startApi(_createPool(min: 1, max: 1));
      expect((await client.send('POST', '/broken')).status, 500);
      final session = await client.send('GET', '/session');
      expect((session.json as Map)['transactionInProgress'], isFalse);
      expect(
          await conn().queryOne('select count(*) from $_accounts where id < 0'),
          [0]);
      // a later commit on the same session does not commit it either
      expect(
          (await client.send(
                  'POST', '/transfers', {'from': 1, 'to': 2, 'amount': 1}))
              .status,
          201);
      expect(
          await conn().queryOne('select count(*) from $_accounts where id < 0'),
          [0]);
    });

    test('settings changed by one request do not leak into the next', () async {
      await startApi(_createPool(min: 1, max: 1));
      final before = (await client.send('GET', '/session')).json as Map;
      expect((await client.send('POST', '/careless')).status, 200);
      final after = (await client.send('GET', '/session')).json as Map;
      expect(after['sid'], before['sid'], reason: 'same pooled session');
      expect(after['autocommit'], isFalse);
      expect(after['callTimeout'], before['callTimeout']);
    });

    test('a client disconnecting during a streamed response', () async {
      await startApi(_createPool(min: 1, max: 1));
      // the full stream works
      final full = await client.send('GET', '/numbers');
      expect(full.status, 200);
      expect(full.json, hasLength(20000));
      expect((full.json as List).last, [20000, 'x' * 100]);

      for (var i = 0; i < 5; i++) {
        final socket =
            await Socket.connect(api.server.address, api.server.port);
        socket.write('GET /numbers HTTP/1.1\r\nHost: x\r\n\r\n');
        await socket.first;
        socket.destroy();
      }
      await _idle(pool);
      final session = await client.send('GET', '/session');
      expect(session.status, 200);
      expect((await client.send('GET', '/accounts/3')).status, 200);
    });

    Future<OracleConnection> connectAsSystem() => OracleConnection.connect(
        user: 'system',
        password: Platform.environment['ORACLE_SYSTEM_PASSWORD'] ?? 'oracle',
        dsn: OracleTestConfig.dsn);

    test('a session killed by the database is replaced', () async {
      await startApi(_createPool(min: 1, max: 1));
      final audsid =
          ((await client.send('GET', '/session')).json as Map)['audsid'];
      final system = await connectAsSystem();
      try {
        final row = await system.queryOne(
            'select sid, serial# from v\$session where audsid = :1',
            [int.parse('$audsid')]);
        await system.execute(
            "alter system kill session '${row![0]},${row[1]}' immediate");
      } finally {
        await system.close();
      }
      // give the database time to close the network connection
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final next = await client.send('GET', '/session');
      expect(next.status, 200, reason: '${next.json}');
      expect((next.json as Map)['audsid'], isNot(audsid));
      await _idle(pool);
    });

    test('a call timeout while waiting for a row lock answers 504', () async {
      await startApi(_createPool(min: 1, max: 2));
      final holder = await connect();
      try {
        await holder
            .execute('update $_accounts set balance = balance where id = 7');
        final watch = Stopwatch()..start();
        final waited =
            await client.send('POST', '/accounts/7/lock?timeout=300');
        expect(waited.status, HttpStatus.gatewayTimeout,
            reason: '${waited.json}');
        // bounded by the call timeout plus the time given to the database
        // to acknowledge the interruption
        expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
        await holder.rollback();
        // the other rows (and the replaced connection) can be used
        final ok = await client.send('POST', '/accounts/7/lock?timeout=5000');
        expect(ok.status, 200, reason: '${ok.json}');
        expect((await client.send('GET', '/accounts/7')).status, 200);
      } finally {
        await holder.close();
      }
      await _idle(pool);
    });
  });
}
