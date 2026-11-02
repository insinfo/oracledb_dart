# Changelog

All notable changes to this project are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Scrollable cursors (`OracleCursor.scrollable` and `OracleCursor.scroll()`
  with relative, absolute, first and last positioning).
- Database Resident Connection Pooling (DRCP): connections with
  `SERVER=POOLED` (e.g. `host/service:pooled`) use the connection class and
  purity given, release their sessions to the database pool when returned
  to an `OracleConnectionPool` and are released instead of logged off when
  closed.
- Two-phase commit (`tpcBegin`, `tpcEnd`, `tpcPrepare`, `tpcCommit`,
  `tpcRollback`, `tpcRecover`) with `Xid` transaction identifiers.
- Pipelining (`OraclePipeline` and `OracleConnection.runPipeline()`): many
  operations (execute, executeMany, fetches, function and procedure calls
  and commits) are sent in a single round trip on Oracle Database 23ai,
  optionally continuing after errors; older databases run the operations
  one after the other.

### Fixed

- The call timeout and cancellation tests use a query that does not exhaust
  the memory of the database on fast machines.

## [1.0.0] - 2026-11-02

First functional release: a complete rewrite of the thin protocol layer,
modelled on python-oracledb, with no third-party runtime dependencies.

### Added

- Connections to Oracle Database 12.1 and later, with fast authentication
  and end-of-response handling on Oracle Database 23ai.
- Password authentication with the 11g and 12c verifiers, privileged modes,
  password change, editions and application context.
- Token authentication (OAuth2 access tokens and OCI IAM database tokens
  signed with RSA), with refresh callbacks for expired tokens.
- TLS (`tcps`) connections, including the TLS renegotiation requested by the
  listener, wallets (`ewallet.pem`), mutual TLS and server DN matching.
- Easy Connect strings, connect descriptors and `tnsnames.ora` aliases.
- Parameter, protocol and password type hooks, with a built-in
  `config-file://` configuration provider and the `base64` password type.
- Connection pools with minimum/maximum/increment sizes, wait modes, idle
  timeout, maximum session lifetime, ping interval and session callbacks.
- Call timeouts and cancellation of calls in progress.
- Queries, DML, DDL and PL/SQL with binds by position, by name or with `?`
  placeholders (`PlaceholderIdentifier.onlyQuestionMark`).
- Statement cache with cursor re-execution, prefetching, batched fetching and
  row streaming.
- `executeMany()` with batch errors and DML row counts.
- OUT and IN OUT binds, DML returning, REF CURSORs and implicit results.
- Data types: character, numeric, date/time, interval, raw, rowid, boolean,
  LONG, LOBs (as values or as locators with streaming), native JSON (OSON)
  and VECTOR (dense, binary and sparse).
- Pure Dart implementations of AES, MD5, SHA-1, SHA-256, SHA-512, HMAC,
  PBKDF2 and RSA signatures.
- Benchmark against python-oracledb based on `package:benchmark_harness`.
- CI running the unit tests and the integration tests (TCP and TCPS) against
  Oracle Database 23ai Free.

### Changed

- The re-execution of a query whose bind types changed now parses the
  statement again, so that the results use the types of the new values.

### Removed

- The `pointycastle` dependency.
- The previous incomplete protocol implementation and the porting notes and
  scripts.
