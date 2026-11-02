# oracledb_dart

[![CI](https://github.com/insinfo/oracledb_dart/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/oracledb_dart/actions/workflows/dart.yml)

A pure Dart driver for Oracle Database. It implements the Oracle network
protocol directly (the "thin" mode of
[python-oracledb](https://github.com/oracle/python-oracledb), on which it is
based), so it needs **no Oracle Client libraries and no third-party
packages** — even the cryptography used for authentication (AES, SHA-1,
SHA-256, SHA-512, MD5, PBKDF2, RSA signatures) is implemented in the
package.

## Features

- Oracle Database 12.1 and later, including Oracle Database 23ai (fast
  authentication and end-of-response handling are used when available)
- TLS (`tcps`) connections with wallets (`ewallet.pem`), mutual TLS and
  server certificate DN matching
- Password (11g and 12c verifiers) and token authentication (OAuth2 and OCI
  IAM database tokens), privileged modes, password change, editions,
  application context
- Easy Connect strings, connect descriptors and `tnsnames.ora` aliases
- Connection pools and Database Resident Connection Pooling (DRCP)
- Call timeouts and cancellation of calls in progress
- Queries, DML, DDL and PL/SQL with binds by position, by name or with `?`
  placeholders
- Efficient fetching in batches, row streaming, statement caching (cursors
  are re-executed without being parsed again)
- `executeMany()` with batch errors and DML row counts
- OUT and IN OUT binds, DML `RETURNING`, REF CURSORs, implicit results,
  scrollable cursors
- Object types and collections (VARRAYs, nested tables, PL/SQL records and
  associative arrays) and `XMLType`
- Pipelining (many operations in a single round trip on Oracle Database
  23ai) and two-phase commit
- LOBs as values or as locators with streaming reads, writes and temporary
  LOBs
- Native `JSON` (OSON) and `VECTOR` types (dense, binary and sparse vectors)
- Transactions, autocommit, end-to-end tracing attributes (module, action,
  client identifier, ...)
- Hooks for parameters, protocols (configuration providers) and password
  types, with a built-in `config-file://` provider

## Installation

```yaml
dependencies:
  oracledb_dart:
    git: https://github.com/insinfo/oracledb_dart.git
```

## Usage

```dart
import 'package:oracledb_dart/oracledb_dart.dart';

Future<void> main() async {
  final conn = await OracleConnection.connect(
    user: 'scott',
    password: 'tiger',
    dsn: 'localhost:1521/FREEPDB1',
  );

  final result = await conn.execute(
      'select id, name from employees where department_id = :dept',
      {'dept': 10});
  for (final row in result.rows) {
    print('${row[0]}: ${row[1]}');
  }

  await conn.close();
}
```

### Connecting

The database can be identified by an Easy Connect string
(`[tcp[s]://]host[:port][/service_name][?options]`), a full connect
descriptor, a `tnsnames.ora` alias or by its parts:

```dart
await OracleConnection.connect(user: u, password: p, dsn: 'dbhost:1521/orclpdb');

await OracleConnection.connect(user: u, password: p,
    dsn: '(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=dbhost)(PORT=1521))'
        '(CONNECT_DATA=(SERVICE_NAME=orclpdb)))');

// alias defined in tnsnames.ora (configDir or the TNS_ADMIN directory)
await OracleConnection.connect(user: u, password: p, dsn: 'sales',
    configDir: '/opt/oracle/network/admin');

await OracleConnection.connect(user: u, password: p,
    host: 'dbhost', port: 1521, serviceName: 'orclpdb');

await OracleConnection.connect(user: 'sys', password: p, dsn: dsn,
    mode: AuthMode.sysdba);
```

Requests on a connection are serialized, so concurrent calls on the same
connection are safe; use a pool (or one connection per concurrent unit of
work) for parallelism.

#### TLS

```dart
// trusted certificates (and, for mutual TLS, the client certificate and
// key) are read from ewallet.pem in the wallet directory
await OracleConnection.connect(user: u, password: p,
    dsn: 'tcps://dbhost:2484/orclpdb?wallet_location=/path/to/wallet');

// the server certificate DN can be checked as well
await OracleConnection.connect(user: u, password: p,
    dsn: 'tcps://dbhost:2484/orclpdb',
    sslServerCertDn: 'CN=dbhost, O=Example',
    walletLocation: '/path/to/wallet',
    walletPassword: 'secret');
```

A custom `SecurityContext` can be supplied with `securityContext:`.
Without a wallet the system trusted roots are used.

#### Token authentication

```dart
// OAuth2 (e.g. Microsoft Entra ID) access token
await OracleConnection.connect(dsn: 'tcps://...', accessToken: token);

// OCI IAM database token signed with the private key
await OracleConnection.connect(dsn: 'tcps://...',
    accessToken: dbToken, privateKey: pemPrivateKey);

// or a callback (called again with refresh: true when the token expired)
await OracleConnection.connect(dsn: 'tcps://...',
    accessTokenCallback: (refresh) => fetchToken(refresh));
```

#### Configuration providers and hooks

```dart
// built-in provider: JSON file with connect_descriptor, user and password
// (the password may be {"type": "base64", "value": "..."})
await OracleConnection.connect(dsn: 'config-file:///etc/app/db.json?key=prod');

// custom protocols, parameter hooks and password types
registerProtocol('ldap', (protocol, argument, params) async =>
    params.withConnectString(await lookUpDescriptor(argument)));
registerParamsHook((params) => params.copyWith(accessToken: currentToken));
registerPasswordType('vault', (args) => readSecret(args['id'] as String));
```

### Connection pools

```dart
final pool = await OracleConnectionPool.create(
  user: 'scott', password: 'tiger', dsn: 'dbhost/orclpdb',
  min: 2, max: 10, increment: 2,
  timeout: const Duration(minutes: 5),          // close idle connections
  sessionCallback: (conn) =>                    // initialize new sessions
      conn.execute("alter session set nls_date_format = 'YYYY-MM-DD'"),
);

final rows = await pool.withConnection((conn) => conn.query('select ...'));

final conn = await pool.acquire();
try {
  await conn.execute('update ...');
  await conn.commit();
} finally {
  await conn.close(); // releases the connection back to the pool
}

await pool.close();
```

When all connections are busy, `acquire()` waits (`PoolGetMode.wait`),
fails (`noWait`), waits up to `waitTimeout` (`timedWait`) or creates an
extra connection (`forceGet`). Connections idle for longer than
`pingInterval` are checked before being returned, broken connections are
replaced and open transactions are rolled back on release.

### Queries and binds

```dart
// all rows
final rows = await conn.query('select * from t where id > :1', [100]);

// the first row only
final row = await conn.queryOne('select count(*) from t');

// rows as maps and column metadata
final result = await conn.execute('select id, name from t');
print(result.columnNames);  // [ID, NAME]
print(result.maps.first);   // {ID: 1, NAME: ...}
print(result.columns.first.dbType); // <DbType DB_TYPE_NUMBER>

// stream large result sets (1000 rows per round trip by default)
await for (final row in conn.stream('select * from big_table')) {
  // ...
}
```

Binds can be given by position with a `List` (in the order in which the
placeholders appear in the statement) or by name with a `Map`.

#### Question mark placeholders

As in PHP PDO / JDBC, `?` placeholders can be used, either for the whole
connection or per cursor:

```dart
final conn = await OracleConnection.connect(
  user: u, password: p, dsn: dsn,
  placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
);
await conn.query('select * from t where id = ? and name = ?', [1, 'a']);

// or change it later / per cursor
conn.placeholderIdentifier = PlaceholderIdentifier.colon;
final cursor = conn.cursor()
  ..placeholderIdentifier = PlaceholderIdentifier.onlyQuestionMark;
```

Question marks inside string literals, quoted identifiers and comments are
left untouched.

### Cursors

```dart
final cursor = conn.cursor()
  ..arraySize = 500     // rows per fetch round trip
  ..prefetchRows = 500; // rows returned by the execute round trip
await cursor.execute('select id, name from t order by id');
print(cursor.description);
final first = await cursor.fetchOne();
final next10 = await cursor.fetchMany(10);
final rest = await cursor.fetchAll();
cursor.close();
```

### DML, batches and transactions

```dart
final inserted = await conn.executeMany(
  'insert into t (id, name) values (:1, :2)',
  [[1, 'one'], [2, 'two'], [3, 'three']],
);

await conn.commit();   // or conn.rollback()
conn.autocommit = true;

// commits when the action completes, rolls back if it throws
await conn.transaction((c) async {
  await c.execute('update accounts set balance = balance - 10 where id = 1');
  await c.execute('update accounts set balance = balance + 10 where id = 2');
});

// batch errors and DML row counts
final cursor = conn.cursor();
await cursor.executeMany('insert into t (id) values (:1)', rows,
    batchErrors: true);
for (final error in cursor.batchErrors!) {
  print('row ${error.offset}: ${error.message}');
}
```

### Timeouts and cancellation

```dart
conn.callTimeout = const Duration(seconds: 5);
try {
  await conn.execute('begin long_running_job; end;');
} on OracleException catch (e) {
  print(e.fullCode); // DPY-4024: call timeout exceeded
}

// interrupt a call from elsewhere: the call fails with ORA-01013
final call = conn.execute('select ... from huge_table');
conn.cancel();
```

The connection remains usable after a timeout or a cancellation. Breaks
are sent in-band, so the database interrupts the call when it next checks
for them (immediately for most SQL; some PL/SQL calls such as
`dbms_session.sleep` are only interrupted when they complete).

### PL/SQL

```dart
final cursor = conn.cursor();

// OUT and IN OUT binds
final total = cursor.variable(DbType.number);
final text = cursor.variable(DbType.varchar, size: 100, inValue: 'abc');
await cursor.execute('begin my_proc(:1, :2, :3); end;', [10, text, total]);
print('${text.value} ${total.value}');

// functions and procedures
final sum = await cursor.callFunc('my_add', DbType.number, [1, 2]);
await cursor.callProc('my_proc', [10, text, total]);

// DML returning
final id = cursor.variable(DbType.number);
await cursor.execute(
    'insert into t (name) values (:1) returning id into :2', ['x', id]);
print(id.value); // [42]

// REF CURSORs
final ref = cursor.variable(DbType.cursor);
await cursor.execute('begin open :1 for select * from t; end;', [ref]);
final rows = await (ref.value as OracleCursor).fetchAll();
```

Strings and bytes longer than 32767 bytes bound to PL/SQL are transparently
bound as temporary LOBs.

### LOBs

By default CLOB, NCLOB and BLOB columns are fetched as `String` and
`Uint8List` values. For large LOBs, fetch the locators instead and read or
write them in pieces:

```dart
final cursor = conn.cursor()..fetchLobsAsValues = false;
await cursor.execute('select doc from documents where id = :1', [1]);
final lob = (await cursor.fetchOne())![0] as OracleLob;
print(await lob.size());
await for (final piece in lob.stream()) {
  // pieces of about 1 MB
}

// write to a LOB selected for update, or create a temporary LOB
final temp = await conn.createLob(DbType.clob, 'initial content');
await temp.write(' and more', offset: 16);
await conn.execute('insert into documents values (:1, :2)', [2, temp]);
temp.free();
```

### JSON and VECTOR

```dart
// Map and List values are bound as JSON; JSON columns are returned as
// Dart maps, lists and scalars
await conn.execute('insert into orders (id, data) values (:1, :2)',
    [1, {'customer': 'Ada', 'items': [1, 2, 3], 'paid': true}]);
final data = (await conn.queryOne('select data from orders'))![0] as Map;

// VECTOR columns use typed lists
await conn.execute('insert into embeddings values (:1, :2)',
    [1, Float32List.fromList([0.1, 0.2, 0.3])]);
// also Float64List, Int8List, BinaryVector and SparseVector
```

Text and BLOB columns with an `IS JSON` check constraint are decoded
automatically as well.

### Objects and collections

```dart
final personType = await conn.getType('HR.PERSON_T');
final person = personType.newObject({'ID': 1, 'NAME': 'Ada'});
person['ADDRESS'] = (await conn.getType('HR.ADDRESS_T'))
    .newObject({'STREET': 'Main St', 'CITY': 'London'});
await conn.execute('insert into people values (:1)', [person]);

final row = await conn.queryOne('select p from people p');
final fetched = row![0] as OracleDbObject;
print(fetched['NAME']); // Ada
print(fetched.asMap()); // all attributes

// VARRAYs and nested tables hold lists; PL/SQL associative arrays use
// integer indexes
final tags = (await conn.getType('HR.TAGS_T')).newObject(['a', 'b']);
tags.append('c');
final table = (await conn.getType('HR.PKG.NUM_TAB')).newObject({1: 10, 5: 50});

// OUT binds and function results need the type
final cursor = conn.cursor();
final out = cursor.variable(DbType.object, objectType: personType);
await cursor.callProc('hr.pkg.get_person', [1, out]);
```

Types used by queries are discovered automatically from the query metadata.
Collections support `length`, `append()`, `extend()`, `getElement()`,
`setElement()`, `delete()`, `exists()`, `trim()`, `firstIndex`, `lastIndex`,
`nextIndex()` and `prevIndex()`. `XMLType` values are returned as strings.

### Scrollable cursors, pipelining and two-phase commit

```dart
final cursor = conn.cursor()..scrollable = true;
await cursor.execute('select id from t order by id');
await cursor.scroll(0, ScrollMode.last);
await cursor.scroll(-10); // relative to the current row
final row = await cursor.fetchOne();

// several operations in one round trip (Oracle Database 23ai)
final pipeline = OraclePipeline()
  ..addExecute('insert into t values (:1)', [1])
  ..addFetchAll('select * from t')
  ..addCommit();
final results = await conn.runPipeline(pipeline);
print(results[1].rows);

// two-phase commit
final xid = Xid(1000, 'global-id', 'branch');
await conn.tpcBegin(xid);
await conn.execute('insert into t values (2)');
if (await conn.tpcPrepare()) await conn.tpcCommit();
```

DRCP is used when the connect string asks for a pooled server (for example
`host/service:pooled`); pass `cclass` and `purity` to
`OracleConnection.connect` or `OracleConnectionPool.create`.

### Data types

| Oracle type | Dart type |
| --- | --- |
| `VARCHAR2`, `NVARCHAR2`, `CHAR`, `NCHAR`, `LONG`, `ROWID` | `String` |
| `CLOB`, `NCLOB` | `String` (or `OracleLob`) |
| `NUMBER` (integer values) | `int`, or `BigInt` beyond 64 bits |
| `NUMBER` (with a scale, or non-integer values), `BINARY_FLOAT`, `BINARY_DOUBLE` | `double` |
| `DATE`, `TIMESTAMP`, `TIMESTAMP WITH (LOCAL) TIME ZONE` | `DateTime` |
| `INTERVAL DAY TO SECOND` | `Duration` |
| `INTERVAL YEAR TO MONTH` | `IntervalYM` |
| `RAW`, `LONG RAW` | `Uint8List` |
| `BLOB` | `Uint8List` (or `OracleLob`) |
| `BFILE` | `OracleLob` |
| `BOOLEAN` | `bool` |
| `JSON` | `Map`, `List`, `String`, `num`, `bool`, ... |
| `VECTOR` | `Float32List`, `Float64List`, `Int8List`, `Uint8List` (binary), `SparseVector` |
| Object types, `VARRAY`, nested tables, PL/SQL records and collections | `OracleDbObject` |
| `XMLType` | `String` |

`DATE` and `TIMESTAMP` values have no time zone: they are returned as UTC
`DateTime` objects holding the wall-clock value (which avoids any shifting
caused by local daylight saving rules) and bound using the fields of the
`DateTime` given. `TIMESTAMP WITH TIME ZONE` values are returned as the exact
UTC instant. Set `cursor.fetchNumbersAsStrings = true` to get `NUMBER` values
as exact decimal strings.

### Errors

Errors raised by the database are `OracleDatabaseError` (or a subclass such
as `OracleIntegrityError`) with the Oracle error number in `code` and the
position in the statement in `offset`; driver errors carry a `DPY-xxxx` code
in `fullCode`.

```dart
try {
  await conn.execute('insert into t (id) values (1)');
} on OracleIntegrityError catch (e) {
  print(e.code); // 1 (ORA-00001: unique constraint violated)
}
```

## Performance notes

- Increase `arraySize` and `prefetchRows` for large result sets to reduce
  round trips (`conn.stream()` uses 1000 by default).
- Use `executeMany()` instead of executing a statement in a loop.
- Re-executing the same SQL text reuses the cursor kept open on the server
  by the statement cache (`stmtCacheSize`, default 20); prefer binds over
  literals in the SQL text.
- A larger SDU (`sdu: 65535`) reduces the number of packets for large
  responses when the server allows it.
- Use a connection pool instead of opening a connection per request.

A benchmark comparing the driver with python-oracledb (thin mode) is
available in [benchmark/](benchmark). It uses `package:benchmark_harness`
and must be compiled ahead of time:

```sh
dart compile exe benchmark/bench.dart -o bench && ./bench
pip install oracledb && python benchmark/bench.py
```

## Not supported yet

Native Network Encryption, sessionless transactions, Advanced Queuing and
SODA (SODA is only available in the thick mode of the Oracle client
libraries).

## Development

The tests expect an Oracle Database reachable with the settings below (the
defaults match the `gvenzl/oracle-free` container used by the CI):

```sh
docker run -d -p 1521:1521 -e ORACLE_PASSWORD=oracle \
  -e APP_USER=dart_user -e APP_USER_PASSWORD=dart gvenzl/oracle-free:23-slim

dart test                     # unit and integration tests
ORACLE_TESTS=0 dart test      # unit tests only
```

Environment variables: `ORACLE_HOST`, `ORACLE_PORT`, `ORACLE_SERVICE`,
`ORACLE_USER`, `ORACLE_PASSWORD`. The TLS tests run when
`ORACLE_TCPS_WALLET` names a directory with an `ewallet.pem` containing the
certificate authority of a TCPS listener (`ORACLE_TCPS_PORT`, default
2484). Set `DART_ORACLEDB_DEBUG_PACKETS=1` to print the packets exchanged
with the database.

## License

MIT — see [LICENSE](LICENSE). The implementation of the Oracle network
protocol is derived from python-oracledb (Copyright (c) 2016, 2025 Oracle
and/or its affiliates), used under the Universal Permissive License 1.0,
whose notice is included in the LICENSE file.
