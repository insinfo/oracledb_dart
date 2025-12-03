# Thin handshake porting plan

Based on `python-oracledb/src/oracledb/impl/thin/messages/connect.pyx`:

1) Build CONNECT packet
   - Header: packet type = `TNS_PACKET_TYPE_CONNECT`, flags from description (e.g., NA disable).
   - Body fields to write (in order): desired/min versions, service options, SDU/TDU, protocol characteristics, connect data length/offsets, NSI flags, and connect data bytes.
   - Respect `TNS_MAX_CONNECT_DATA` by splitting into DATA packet if too large.
2) Send CONNECT, read ACCEPT/REDIRECT/REFUSE
   - On ACCEPT: adjust capabilities `_adjustForProtocol`, set SDU, enable full packet size when requested, check encryption flags (`TNS_NSI_NA_REQUIRED`).
   - On REDIRECT: capture redirect data and re-issue CONNECT to the redirected address.
   - On REFUSE: map listener error codes to driver errors (`ERR_INVALID_SERVICE_NAME`, `ERR_INVALID_SID`, `ERR_LISTENER_REFUSED_CONNECTION`).
3) Proceed with TTC handshake/login messages (auth, capabilities, session setup).
4) Wire into `ThinConnection.connect()` using `Transport` for send/recv and `ConnectMessage` for parsing.

Env for local XE testing (defaults already baked into helpers):
```
ORACLE_TESTS=1
ORACLE_HOST=localhost
ORACLE_PORT=1521
ORACLE_SERVICE=XEPDB1
ORACLE_USER=dart_user
ORACLE_PASSWORD=dart
```
