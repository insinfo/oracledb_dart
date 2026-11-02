import 'dart:convert';
import 'dart:typed_data';

import '../connect_params.dart';
import '../exceptions.dart';
import '../utils.dart';
import 'constants.dart';
import 'messages/auth.dart';
import 'messages/base.dart';
import 'protocol.dart';
import 'statement.dart';
import 'tls.dart';

/// Internal state of a connection to the database.
class ThinConnImpl {
  ThinConnImpl(this.params)
      : statementCache = StatementCache(params.stmtCacheSize, 0) {
    protocol = Protocol(this);
  }

  final ConnectParams params;
  late final Protocol protocol;

  /// Maximum time each round trip may take (null for no limit).
  late Duration? callTimeout = params.callTimeout;
  StatementCache statementCache;

  Uint8List? comboKey;
  Uint8List? ltxid;
  int sessionId = 0;
  int serialNum = 0;
  String? dbDomain;
  String? dbName;
  String? serviceName;
  String? instanceName;
  int maxOpenCursors = 0;
  int maxIdentifierLength = 30;
  List<int> serverVersion = const [];
  bool supportsBool = false;
  String? edition;
  String? currentSchema;
  bool currentSchemaModified = false;
  bool autocommit = false;
  bool drcpEstablishSession = false;
  int sessionStateDesired = 0;
  int osonMaxFnameSize = 255;

  /// Locators of temporary LOBs to free on the next round trip.
  final List<Uint8List> tempLobsToClose = [];
  int tempLobsTotalSize = 0;
  OracleException? warning;

  // end-to-end attributes
  String? action, module, clientIdentifier, clientInfo, dbop;
  bool actionModified = false,
      moduleModified = false,
      clientIdentifierModified = false,
      clientInfoModified = false,
      dbopModified = false;

  bool get endToEndModified =>
      actionModified ||
      moduleModified ||
      clientIdentifierModified ||
      clientInfoModified ||
      dbopModified;

  void resetEndToEnd() {
    actionModified = moduleModified =
        clientIdentifierModified = clientInfoModified = dbopModified = false;
    action = module = clientIdentifier = clientInfo = dbop = null;
  }

  bool get isHealthy => protocol.isHealthy;

  /// Whether the connection uses Database Resident Connection Pooling.
  bool get drcpEnabled => params.serverType?.toLowerCase() == 'pooled';

  /// Whether the connection belongs to an [OracleConnectionPool].
  bool isPooled = false;

  /// The purity requested; with DRCP the default is NEW for standalone
  /// connections and SELF for pooled ones.
  Purity get effectivePurity {
    if (params.purity != Purity.defaultPurity || !drcpEnabled) {
      return params.purity;
    }
    return isPooled ? Purity.self : Purity.newPurity;
  }
  bool get txnInProgress => protocol.txnInProgress;

  Future<void> connect() async {
    final connectionId = base64.encode(randomBytes(16));
    var connectString = params.buildConnectDescriptor(connectionId);
    var host = params.host, port = params.port;
    final p = protocol;
    if (params.usesTokenAuth && !params.usesTls) {
      throw dpyError(ERR_ACCESS_TOKEN_REQUIRES_TCPS);
    }
    if (params.usesTls) p.transport.tls = TlsConfig.fromParams(params, host);
    try {
      await p.transport.connect(host, port, params.connectTimeout);
    } on OracleException {
      rethrow;
    } on Exception catch (e) {
      throw dpyError(ERR_CONNECTION_FAILED,
          args: {'connection_id': connectionId}, message: '$e', cause: e);
    }

    // connect phase one: CONNECT -> ACCEPT (following any redirects)
    p.caps.supportsOob = false;
    ConnectMessage? message;
    var packetFlags = 0;
    while (true) {
      message ??= ConnectMessage(this, connectString, params.sdu,
          packetFlags: packetFlags);
      await p.processMessage(message);
      final redirect = message.redirectData;
      if (redirect != null) {
        final pos = redirect.indexOf('\x00');
        if (pos < 0) {
          throw dpyError(ERR_INVALID_REDIRECT_DATA, args: {'data': redirect});
        }
        final address = ConnectParams.fromDsn(redirect.substring(0, pos));
        host = address.host;
        port = address.port;
        connectString = redirect.substring(pos + 1);
        await p.transport.reconnect(host, port, params.connectTimeout);
        message = null;
        packetFlags = TNS_PACKET_FLAG_REDIRECT;
      } else if (p.lastPacketType == TNS_PACKET_TYPE_ACCEPT) {
        p.writeBuf.resizeForSdu();
        break;
      } else if (params.usesTls &&
          p.lastPacketFlags & TNS_PACKET_FLAG_TLS_RENEG != 0) {
        // the listener requests a new TLS handshake on the same socket
        await p.transport.renegotiateTls(params.connectTimeout);
      }
    }

    // connect phase two: protocol, data types and authentication
    final protocolMessage = ProtocolMessage(this);
    final dataTypesMessage = DataTypesMessage(this);
    final authMessage = AuthMessage(this, token: await _accessToken());
    if (p.caps.supportsFastAuth) {
      final fastAuth =
          FastAuthMessage(this, protocolMessage, dataTypesMessage, authMessage);
      await p.processMessage(fastAuth);
    } else {
      final supportsEndOfResponse = p.caps.supportsEndOfResponse;
      p.caps.supportsEndOfResponse = false;
      await p.processMessage(protocolMessage);
      await p.processMessage(dataTypesMessage);
      p.caps.supportsEndOfResponse = supportsEndOfResponse;
      await p.processMessage(authMessage);
    }
    if (authMessage.resend) await p.processMessage(authMessage);
    _postConnect(authMessage);
  }

  /// Returns the access token to use for token authentication (refreshing
  /// it through the callback when it has expired), or null.
  Future<String?> _accessToken() async {
    if (!params.usesTokenAuth) return null;
    final callback = params.accessTokenCallback;
    var token = params.accessToken ?? await callback!(false);
    if (_tokenExpired(token)) {
      if (callback == null) throw dpyError(ERR_EXPIRED_ACCESS_TOKEN);
      token = await callback(true);
      if (_tokenExpired(token)) throw dpyError(ERR_EXPIRED_ACCESS_TOKEN);
    }
    return token;
  }

  /// Checks the expiry ("exp" claim) of a JSON Web Token; tokens in other
  /// formats are assumed to be valid.
  static bool _tokenExpired(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return false;
    try {
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, Object?>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).toInt(),
              isUtc: true)
          .isBefore(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }

  void _postConnect(AuthMessage auth) {
    final data = auth.sessionData;
    sessionId = int.parse(data['AUTH_SESSION_ID'] ?? '0');
    serialNum = int.parse(data['AUTH_SERIAL_NUM'] ?? '0');
    dbDomain = data['AUTH_SC_DB_DOMAIN'];
    dbName = data['AUTH_SC_DBUNIQUE_NAME'];
    maxOpenCursors = int.parse(data['AUTH_MAX_OPEN_CURSORS'] ?? '0');
    serviceName = data['AUTH_SC_SERVICE_NAME'];
    instanceName = data['AUTH_INSTANCENAME'];
    maxIdentifierLength = int.parse(data['AUTH_MAX_IDEN_LENGTH'] ?? '30');
    serverVersion = auth.versionTuple(protocol.readBuf);
    supportsBool = protocol.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1;
    warning = auth.warning;
    statementCache = StatementCache(params.stmtCacheSize, maxOpenCursors);
    protocol.pendingErrorNum = 0;
    protocol.inConnect = false;
  }

  Statement getStatement(String? sql, bool cacheStatement) =>
      statementCache.getStatement(sql, cacheStatement,
          forceNew: drcpEstablishSession);

  /// Releases the DRCP session to the database pool (when the connection is
  /// released to the client pool); the next call attaches a session again.
  Future<void> releaseDrcpSession() async {
    final p = protocol;
    await p.lock.run(() async {
      if (p.txnInProgress) {
        await p.processMessage(SimpleMessage(this, TNS_FUNC_ROLLBACK));
      }
      p.sendOneWay(SessionReleaseMessage(this, 0));
      drcpEstablishSession = true;
    });
  }

  void returnStatement(Statement stmt) => statementCache.returnStatement(stmt);

  Future<void> _simple(int functionCode) =>
      protocol.processSingleMessage(SimpleMessage(this, functionCode));

  Future<void> commit() => _simple(TNS_FUNC_COMMIT);

  Future<void> rollback() => _simple(TNS_FUNC_ROLLBACK);

  Future<void> ping() => _simple(TNS_FUNC_PING);

  Future<void> close() async {
    final p = protocol;
    await p.lock.run(() async {
      try {
        if (p.transport.isConnected) {
          if (p.txnInProgress) {
            await p.processMessage(SimpleMessage(this, TNS_FUNC_ROLLBACK));
          }
          if (drcpEnabled) {
            // DRCP sessions are released instead of logged off
            p.sendOneWay(SessionReleaseMessage(
                this, isPooled ? 0 : DRCP_DEAUTHENTICATE));
          } else {
            await p.processMessage(SimpleMessage(this, TNS_FUNC_LOGOFF));
          }
        }
      } finally {
        await p.finalClose();
      }
    });
  }
}
