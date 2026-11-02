# Changelog

All notable changes to this project are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-02

First release: a pure Dart implementation of the Oracle Database network
protocol (thin mode), modelled on python-oracledb, with no Oracle Client
libraries and no third-party runtime dependencies.

### Connections and authentication

- Connections to Oracle Database 12.1 and later, with fast authentication
  and end-of-response handling on Oracle Database 23ai.
- Password authentication with the 11g and 12c verifiers, privileged modes
  (`AuthMode`), password change while connecting, editions and application
  context.
- Token authentication: OAuth2 access tokens and OCI IAM database tokens
  signed with RSA, with refresh callbacks for expired tokens.
- TLS (`tcps`) connections, including the TLS renegotiation requested by the
  listener, wallets (`ewallet.pem`), mutual TLS and server DN matching.
- Easy Connect strings, connect descriptors and `tnsnames.ora` aliases
  (including `IFILE`), or `ConnectParams` with
  `OracleConnection.connectWithParams()`.
- Parameter, protocol and password type hooks, with a built-in
  `config-file://` configuration provider and the `base64` password type.
- Connection pools (`OracleConnectionPool`) with minimum, maximum and
  increment sizes, get modes (wait, no wait, timed wait, force get), idle
  timeout, maximum session lifetime, ping interval and session callbacks.
- Database Resident Connection Pooling (DRCP): connections with
  `SERVER=POOLED` (e.g. `host/service:pooled`) use the connection class and
  purity given, release their sessions to the database pool when returned
  to an `OracleConnectionPool` and are released instead of logged off when
  closed.
- Call timeouts and cancellation of calls in progress; the connection stays
  usable afterwards.
- Session attributes (module, action, client identifier, client info,
  database operation, current schema) and session information (server
  version, session id, service and instance names, ...).

### Statements and data

- Queries, DML, DDL and PL/SQL with binds by position, by name or with `?`
  placeholders (`PlaceholderIdentifier.onlyQuestionMark`).
- Statement cache with cursor re-execution, prefetching, batched fetching,
  row streaming and rows as maps.
- Scrollable cursors (`OracleCursor.scrollable` and `OracleCursor.scroll()`
  with relative, absolute, first and last positioning).
- `executeMany()` with batch errors and DML row counts.
- OUT and IN OUT binds, DML returning, REF CURSORs and implicit results.
- Transactions with autocommit and `transaction()` helpers.
- Two-phase commit (`tpcBegin`, `tpcEnd`, `tpcPrepare`, `tpcCommit`,
  `tpcRollback`, `tpcRecover`) with `Xid` transaction identifiers.
- Pipelining (`OraclePipeline` and `OracleConnection.runPipeline()`): many
  operations (execute, executeMany, fetches, function and procedure calls
  and commits) are sent in a single round trip on Oracle Database 23ai,
  optionally continuing after errors; older databases run the operations
  one after the other.
- Data types: character, numeric, date/time, interval, raw, rowid, boolean,
  LONG, LOBs (as values, or as locators with streaming reads, writes and
  temporary LOBs), native JSON (OSON) and VECTOR (dense, binary and sparse).
- Object types and collections (`OracleConnection.getType()`,
  `OracleDbObjectType`, `OracleDbObject`): objects, VARRAYs, nested tables,
  PL/SQL records and associative arrays can be bound (IN, OUT and IN OUT)
  and fetched, including nested objects and LOB attributes. Types used by
  queries are discovered from the query metadata. `XMLType` values are
  fetched as strings.
- Advanced Queuing (`OracleConnection.queue()`, `OracleQueue`,
  `OracleMessage`): enqueue and dequeue of RAW, JSON and object payloads,
  one at a time or many in a single round trip, with enqueue and dequeue
  options (visibility, delivery mode, browse/locked/remove modes,
  navigation, conditions, correlations, consumers and recipients).

### Internals and tooling

- Pure Dart implementations of AES, MD5, SHA-1, SHA-256, SHA-512, HMAC,
  PBKDF2 and RSA signatures.
- Benchmark against python-oracledb based on `package:benchmark_harness`.
- CI running the analyzer and the unit tests on Linux, Windows and macOS,
  and the integration tests (TCP and TCPS) against Oracle Database 23ai
  Free.

[1.0.0]: https://github.com/insinfo/oracledb_dart/releases/tag/v1.0.0
