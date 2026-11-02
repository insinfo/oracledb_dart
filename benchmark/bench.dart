// Benchmarks of common operations using package:benchmark_harness. See
// benchmark/bench.py for the equivalent python-oracledb (thin mode) version,
// which follows the same protocol (100 ms warm up, at least 2 s measured,
// mean time per run; the median of 3 measurements is reported).
//
// Always measure an AOT compiled executable:
//
//   dart compile exe benchmark/bench.dart -o bench && ./bench
//
// Connection settings: ORACLE_USER, ORACLE_PASSWORD, ORACLE_DSN.

import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:oracledb_dart/oracledb_dart.dart';

final _env = Platform.environment;
final _user = _env['ORACLE_USER'] ?? 'dart_user';
final _password = _env['ORACLE_PASSWORD'] ?? 'dart';
final _dsn = _env['ORACLE_DSN'] ?? 'localhost:1521/FREEPDB1';

/// Results are stored here so that no work can be optimized away.
Object? sink;

Future<OracleConnection> _connect() =>
    OracleConnection.connect(user: _user, password: _password, dsn: _dsn);

/// Base class holding a connection opened during setup.
abstract class _DbBenchmark extends AsyncBenchmarkBase {
  _DbBenchmark(super.name, this.units);

  /// Number of units (rows, round trips) processed by each run.
  final int units;
  late OracleConnection conn;

  @override
  Future<void> setup() async => conn = await _connect();

  @override
  Future<void> teardown() => conn.close();
}

class ConnectBenchmark extends AsyncBenchmarkBase {
  ConnectBenchmark() : super('connect + close');

  @override
  Future<void> run() async {
    final conn = await _connect();
    sink = conn.sessionId;
    await conn.close();
  }
}

class PingBenchmark extends _DbBenchmark {
  PingBenchmark() : super('ping (round trip)', 1);

  @override
  Future<void> run() => conn.ping();
}

class QueryWithBindBenchmark extends _DbBenchmark {
  QueryWithBindBenchmark() : super('query with bind (1 row)', 1);

  late OracleCursor cursor;
  int i = 0;

  @override
  Future<void> setup() async {
    await super.setup();
    cursor = conn.cursor();
  }

  @override
  Future<void> run() async {
    await cursor.execute('select :1 + 1 from dual', [i++]);
    sink = await cursor.fetchOne();
  }
}

class FetchBenchmark extends _DbBenchmark {
  FetchBenchmark() : super('fetch 100k rows x 4 cols', 100000);

  static const sql = "select level, 'name ' || level, "
      "date '2020-01-01' + mod(level, 1000), level / 7 "
      'from dual connect by level <= 100000';

  @override
  Future<void> run() async {
    final cursor = conn.cursor()
      ..arraySize = 1000
      ..prefetchRows = 1000;
    await cursor.execute(sql);
    final rows = await cursor.fetchAll();
    if (rows.length != units) throw StateError('unexpected row count');
    sink = rows.last;
    cursor.close();
  }
}

class InsertManyBenchmark extends _DbBenchmark {
  InsertManyBenchmark() : super('executeMany insert 10k rows', 10000);

  final rows = [
    for (var i = 0; i < 10000; i++)
      [i, 'name $i', i * 1.25, DateTime.utc(2020, 1, 1 + i % 28)]
  ];

  @override
  Future<void> setup() async {
    await super.setup();
    await conn.execute('''
      begin
        execute immediate 'drop table bench_t purge';
      exception
        when others then if sqlcode != -942 then raise; end if;
      end;''');
    await conn.execute('create table bench_t (id number, name varchar2(50), '
        'amount number(12, 2), created date)');
  }

  @override
  Future<void> run() async {
    sink = await conn.executeMany(
        'insert into bench_t values (:1, :2, :3, :4)', rows);
    await conn.commit();
  }

  @override
  Future<void> teardown() async {
    await conn.execute('drop table bench_t purge');
    await super.teardown();
  }
}

Future<void> main() async {
  final benchmarks = <AsyncBenchmarkBase Function()>[
    ConnectBenchmark.new,
    PingBenchmark.new,
    QueryWithBindBenchmark.new,
    FetchBenchmark.new,
    InsertManyBenchmark.new,
  ];
  print(
      'oracledb_dart (AOT: ${const bool.fromEnvironment('dart.vm.product')})');
  for (final create in benchmarks) {
    final scores = <double>[];
    late AsyncBenchmarkBase benchmark;
    for (var i = 0; i < 3; i++) {
      benchmark = create();
      scores.add(await benchmark.measure());
    }
    scores.sort();
    final micros = scores[1];
    final units = benchmark is _DbBenchmark ? benchmark.units : 1;
    print('${benchmark.name.padRight(32)}'
        '${(micros / 1000).toStringAsFixed(3).padLeft(10)} ms/run'
        '${(units * 1e6 / micros).toStringAsFixed(0).padLeft(12)} units/s');
  }
}
