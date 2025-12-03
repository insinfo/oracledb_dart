# TTC login/auth plan

Reference: `python-oracledb/src/oracledb/impl/thin/messages/auth.pyx` and `protocol.pyx`.

Steps to implement:
1) After CONNECT/ACCEPT, perform TTC capability negotiation and auth:
   - Build AUTH message: write client capabilities (`Capabilities.compileCaps/runtimeCaps`), charset IDs (DBCS), session info (user, password, service), and optional proxy/client id.
   - Handle server response, including password verifier negotiation (11g/12c/19c), crypto (SCRAM), and RADIUS/token path (skip for XE).
   - On success, store session state (ltxid/session signature if present).
2) Process warnings/piggybacks:
   - Parse `MESSAGE_TYPE_WARNING`, `SERVER_SIDE_PIGGYBACK` (ltxid, sync, session signature).
3) Establish session state:
   - Set session params (timezone, NLS, client identifier).
   - Handle DRCP (session pooling) if present.
4) Wire into `ThinConnection.connect()`:
   - After ACCEPT, run auth handshake; on success mark connected.
5) Expand integration:
   - Login with env defaults (dart_user/dart) and execute a simple `SELECT 1 FROM dual`.
   - Add a fixture to create/drop a temp table to test DML/commit.

Env for local XE (already used in helpers):
```
ORACLE_TESTS=1
ORACLE_HOST=localhost
ORACLE_PORT=1521
ORACLE_SERVICE=XEPDB1
ORACLE_USER=dart_user
ORACLE_PASSWORD=dart
```
