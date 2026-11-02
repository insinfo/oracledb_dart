# Changelog

All notable changes to this project are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
