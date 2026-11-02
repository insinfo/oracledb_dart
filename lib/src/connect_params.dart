import 'dart:io';

import 'exceptions.dart';
import 'thin/constants.dart';
import 'tnsnames.dart';

/// Privileged authentication modes.
abstract final class AuthMode {
  static const int defaultMode = 0;
  static const int sysdba = TNS_AUTH_MODE_SYSDBA;
  static const int sysoper = TNS_AUTH_MODE_SYSOPER;
  static const int sysasm = TNS_AUTH_MODE_SYSASM;
  static const int sysbkp = TNS_AUTH_MODE_SYSBKP;
  static const int sysdgd = TNS_AUTH_MODE_SYSDGD;
  static const int syskmt = TNS_AUTH_MODE_SYSKMT;
  static const int sysrac = TNS_AUTH_MODE_SYSRAC;
}

/// Supplies an access token (OAuth2 or OCI IAM) for token authentication.
/// [refresh] is true when a previously returned token has expired.
typedef AccessTokenCallback = Future<String> Function(bool refresh);

/// Parameters used to establish a connection.
class ConnectParams {
  ConnectParams({
    this.host = 'localhost',
    this.port = 1521,
    this.protocol = 'tcp',
    this.serviceName,
    this.sid,
    this.user,
    this.password,
    this.newPassword,
    this.mode = AuthMode.defaultMode,
    this.sdu = 8192,
    this.connectTimeout = const Duration(seconds: 20),
    this.callTimeout,
    this.stmtCacheSize = 20,
    this.edition,
    this.proxyUser,
    this.appContext = const [],
    this.sslServerDnMatch = true,
    this.sslServerCertDn,
    this.walletLocation,
    this.walletPassword,
    this.securityContext,
    this.accessToken,
    this.accessTokenCallback,
    this.privateKey,
    this.cclass,
    this.purity = Purity.defaultPurity,
    this.serverType,
    String? program,
    String? machine,
    String? osUser,
    this.terminal = 'unknown',
    this.connectString,
    this.connectDescriptor,
  })  : program = program ?? _defaultProgram(),
        machine = machine ?? _defaultMachine(),
        osUser = osUser ?? _defaultOsUser();

  /// Creates the parameters from a connect string, which may be an Easy
  /// Connect string (`[tcp[s]://]host[:port][/service_name][?options]`), a
  /// full connect descriptor (`(DESCRIPTION=...)`) or a net service name
  /// (alias) defined in a `tnsnames.ora` file found in [configDir] or in the
  /// directory given by the `TNS_ADMIN` environment variable.
  factory ConnectParams.fromDsn(
    String dsn, {
    String? user,
    String? password,
    String? newPassword,
    int mode = AuthMode.defaultMode,
    int sdu = 8192,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? callTimeout,
    int stmtCacheSize = 20,
    String? edition,
    String? proxyUser,
    List<List<String>> appContext = const [],
    String? configDir,
    bool? sslServerDnMatch,
    String? sslServerCertDn,
    String? walletLocation,
    String? walletPassword,
    SecurityContext? securityContext,
    String? accessToken,
    AccessTokenCallback? accessTokenCallback,
    String? privateKey,
    String? cclass,
    Purity purity = Purity.defaultPurity,
  }) {
    var trimmed = dsn.trim();
    if (isTnsAlias(trimmed)) {
      // without a tnsnames.ora file a simple name is an Easy Connect host
      trimmed = resolveTnsAlias(trimmed, configDir: configDir) ?? trimmed;
    }
    final parsed = _ParsedDsn.parse(trimmed);
    return ConnectParams(
      host: parsed.host,
      port: parsed.port,
      protocol: parsed.protocol,
      serviceName: parsed.serviceName,
      sid: parsed.sid,
      serverType: parsed.serverType,
      user: user,
      password: password,
      newPassword: newPassword,
      mode: mode,
      sdu: parsed.sdu ?? sdu,
      connectTimeout: parsed.connectTimeout ?? connectTimeout,
      callTimeout: callTimeout,
      stmtCacheSize: stmtCacheSize,
      edition: edition,
      proxyUser: proxyUser,
      appContext: appContext,
      sslServerDnMatch: sslServerDnMatch ?? parsed.sslServerDnMatch ?? true,
      sslServerCertDn: sslServerCertDn ?? parsed.sslServerCertDn,
      walletLocation: walletLocation ?? parsed.walletLocation,
      walletPassword: walletPassword,
      securityContext: securityContext,
      accessToken: accessToken,
      accessTokenCallback: accessTokenCallback,
      privateKey: privateKey,
      cclass: cclass ?? parsed.cclass,
      purity: purity != Purity.defaultPurity ? purity : parsed.purity,
      connectString: dsn,
      connectDescriptor: parsed.descriptor,
    );
  }

  final String host;
  final int port;

  /// `tcp` or `tcps` (TLS).
  final String protocol;
  final String? serviceName;
  final String? sid;

  /// `dedicated`, `shared` or `pooled` (DRCP).
  final String? serverType;
  final String? user;
  final String? password;
  final String? newPassword;
  final int mode;

  /// Session data unit size requested (the server may negotiate a smaller
  /// one). Larger values reduce the number of packets for big responses.
  final int sdu;
  final Duration connectTimeout;

  /// Maximum time each round trip to the database may take; when exceeded
  /// the call is interrupted and DPY-4024 is raised.
  final Duration? callTimeout;

  /// Number of statements kept open on the server for re-execution.
  final int stmtCacheSize;
  final String? edition;
  final String? proxyUser;

  /// Application context entries: (namespace, name, value) triples.
  final List<List<String>> appContext;

  /// Whether the host name (or [sslServerCertDn]) is checked against the
  /// server certificate when using TLS (default true).
  final bool sslServerDnMatch;

  /// The distinguished name expected for the server certificate.
  final String? sslServerCertDn;

  /// Directory containing an `ewallet.pem` file with the trusted
  /// certificates and, for mutual TLS, the client certificate and key.
  final String? walletLocation;

  /// Password of the private key in the wallet, if it is encrypted.
  final String? walletPassword;

  /// A security context to use for TLS instead of one built from the wallet
  /// and the system trusted roots.
  final SecurityContext? securityContext;

  /// Access token for token based authentication (requires TLS).
  final String? accessToken;

  /// Callback returning access tokens for token based authentication.
  final AccessTokenCallback? accessTokenCallback;

  /// PEM private key used to sign OCI IAM database tokens.
  final String? privateKey;

  /// Connection class used with DRCP.
  final String? cclass;

  /// Session purity used with DRCP.
  final Purity purity;
  final String program;
  final String machine;
  final String osUser;
  final String terminal;

  /// The connect string as supplied by the user (sent to the server).
  final String? connectString;

  /// A full connect descriptor, if one was supplied.
  final String? connectDescriptor;

  bool get usesTls => protocol.toLowerCase() == 'tcps';

  bool get usesTokenAuth => accessToken != null || accessTokenCallback != null;

  /// Returns a copy whose database address is given by [dsn] (an Easy
  /// Connect string, connect descriptor or alias); the other parameters are
  /// retained unless replaced.
  ConnectParams withConnectString(String dsn,
      {String? user, String? password}) {
    final parsed = ConnectParams.fromDsn(dsn);
    return ConnectParams(
      host: parsed.host,
      port: parsed.port,
      protocol: parsed.protocol,
      serviceName: parsed.serviceName,
      sid: parsed.sid,
      serverType: parsed.serverType ?? serverType,
      user: user ?? this.user,
      password: password ?? this.password,
      newPassword: newPassword,
      mode: mode,
      sdu: parsed.sdu != 8192 ? parsed.sdu : sdu,
      connectTimeout: connectTimeout,
      callTimeout: callTimeout,
      stmtCacheSize: stmtCacheSize,
      edition: edition,
      proxyUser: proxyUser,
      appContext: appContext,
      sslServerDnMatch: sslServerDnMatch && parsed.sslServerDnMatch,
      sslServerCertDn: parsed.sslServerCertDn ?? sslServerCertDn,
      walletLocation: parsed.walletLocation ?? walletLocation,
      walletPassword: walletPassword,
      securityContext: securityContext,
      accessToken: accessToken,
      accessTokenCallback: accessTokenCallback,
      privateKey: privateKey,
      cclass: parsed.cclass ?? cclass,
      purity: parsed.purity != Purity.defaultPurity ? parsed.purity : purity,
      program: program,
      machine: machine,
      osUser: osUser,
      terminal: terminal,
      connectString: dsn,
      connectDescriptor: parsed.connectDescriptor,
    );
  }

  /// Returns a copy with the given values replaced.
  ConnectParams copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? accessToken,
    String? cclass,
    Purity? purity,
    String? serverType,
    String? connectDescriptor,
  }) =>
      ConnectParams(
        host: host ?? this.host,
        port: port ?? this.port,
        protocol: protocol,
        serviceName: serviceName,
        sid: sid,
        serverType: serverType ?? this.serverType,
        user: user ?? this.user,
        password: password ?? this.password,
        newPassword: newPassword,
        mode: mode,
        sdu: sdu,
        connectTimeout: connectTimeout,
        callTimeout: callTimeout,
        stmtCacheSize: stmtCacheSize,
        edition: edition,
        proxyUser: proxyUser,
        appContext: appContext,
        sslServerDnMatch: sslServerDnMatch,
        sslServerCertDn: sslServerCertDn,
        walletLocation: walletLocation,
        walletPassword: walletPassword,
        securityContext: securityContext,
        accessToken: accessToken ?? this.accessToken,
        accessTokenCallback: accessTokenCallback,
        privateKey: privateKey,
        cclass: cclass ?? this.cclass,
        purity: purity ?? this.purity,
        program: program,
        machine: machine,
        osUser: osUser,
        terminal: terminal,
        connectString: connectString,
        connectDescriptor: connectDescriptor ?? this.connectDescriptor,
      );

  /// Builds the connect descriptor sent to the listener.
  String buildConnectDescriptor(String connectionId) {
    final cid = '(PROGRAM=$program)(HOST=$machine)(USER=$osUser)';
    final descriptor = connectDescriptor;
    if (descriptor != null) {
      const marker = '(CONNECT_DATA=';
      final idx = descriptor.toUpperCase().indexOf(marker);
      if (idx >= 0) {
        final end = idx + marker.length;
        return '${descriptor.substring(0, end)}(CID=$cid)'
            '(CONNECTION_ID=$connectionId)${descriptor.substring(end)}';
      }
      return descriptor;
    }
    final connectData = StringBuffer();
    if (serviceName != null) connectData.write('(SERVICE_NAME=$serviceName)');
    if (sid != null) connectData.write('(SID=$sid)');
    if (serverType != null) connectData.write('(SERVER=$serverType)');
    connectData.write('(CID=$cid)');
    if (cclass != null) connectData.write('(POOL_CONNECTION_CLASS=$cclass)');
    if (purity == Purity.self) connectData.write('(POOL_PURITY=SELF)');
    if (purity == Purity.newPurity) connectData.write('(POOL_PURITY=NEW)');
    connectData.write('(CONNECTION_ID=$connectionId)');
    final sduPart = sdu != 8192 ? '(SDU=$sdu)' : '';
    final security = StringBuffer();
    if (usesTls) {
      if (sslServerDnMatch) security.write('(SSL_SERVER_DN_MATCH=ON)');
      if (sslServerCertDn != null) {
        security.write('(SSL_SERVER_CERT_DN=$sslServerCertDn)');
      }
    }
    final securityPart = security.isEmpty ? '' : '(SECURITY=$security)';
    return '(DESCRIPTION=$sduPart(ADDRESS=(PROTOCOL=$protocol)(HOST=$host)'
        '(PORT=$port))(CONNECT_DATA=$connectData)$securityPart)';
  }

  static String _defaultProgram() {
    final exe = Platform.resolvedExecutable;
    final sep = exe.lastIndexOf(Platform.pathSeparator);
    return sep >= 0 ? exe.substring(sep + 1) : exe;
  }

  static String _defaultMachine() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'localhost';
    }
  }

  static String _defaultOsUser() =>
      Platform.environment['USER'] ??
      Platform.environment['USERNAME'] ??
      'unknown';
}

/// Session purity used with Database Resident Connection Pooling (DRCP).
enum Purity {
  defaultPurity(0),
  newPurity(1),
  self(2);

  const Purity(this.value);

  final int value;
}

/// The components of an Easy Connect string or connect descriptor.
class _ParsedDsn {
  String host = 'localhost';
  int port = 1521;
  String protocol = 'tcp';
  String? serviceName;
  String? sid;
  String? serverType;
  String? descriptor;
  int? sdu;
  Duration? connectTimeout;
  bool? sslServerDnMatch;
  String? sslServerCertDn;
  String? walletLocation;
  String? cclass;
  Purity purity = Purity.defaultPurity;

  static bool? _parseBool(String? value) {
    if (value == null) return null;
    final v = value.toLowerCase();
    return v == 'on' || v == 'true' || v == 'yes';
  }

  static Duration? _parseDuration(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (v.endsWith('ms')) {
      return Duration(milliseconds: int.parse(v.substring(0, v.length - 2)));
    }
    final seconds = double.parse(v.endsWith('sec')
        ? v.substring(0, v.length - 3)
        : v.endsWith('s')
            ? v.substring(0, v.length - 1)
            : v);
    return Duration(microseconds: (seconds * 1e6).round());
  }

  static Purity _parsePurity(String? value) => switch (value?.toUpperCase()) {
        'SELF' => Purity.self,
        'NEW' => Purity.newPurity,
        _ => Purity.defaultPurity,
      };

  static _ParsedDsn parse(String dsn) {
    final p = _ParsedDsn();
    if (dsn.startsWith('(')) {
      p.descriptor = dsn;
      String? find(String key) =>
          RegExp('\\(\\s*$key\\s*=\\s*([^)]+?)\\s*\\)', caseSensitive: false)
              .firstMatch(dsn)
              ?.group(1);
      p.host = find('HOST') ?? p.host;
      p.port = int.tryParse(find('PORT') ?? '') ?? p.port;
      p.protocol = (find('PROTOCOL') ?? p.protocol).toLowerCase();
      p.serviceName = find('SERVICE_NAME');
      p.sid = find('SID');
      p.serverType = find('SERVER');
      p.sslServerDnMatch = _parseBool(find('SSL_SERVER_DN_MATCH'));
      final certDn = RegExp(r'\(\s*SSL_SERVER_CERT_DN\s*=\s*"?([^")]+)"?\s*\)',
              caseSensitive: false)
          .firstMatch(dsn)
          ?.group(1);
      p.sslServerCertDn = certDn;
      p.walletLocation = find('MY_WALLET_DIRECTORY') ?? find('DIRECTORY');
      p.cclass = find('POOL_CONNECTION_CLASS');
      p.purity = _parsePurity(find('POOL_PURITY'));
      return p;
    }
    var rest = dsn;
    final schemeIdx = rest.indexOf('://');
    if (schemeIdx >= 0) {
      final scheme = rest.substring(0, schemeIdx).toLowerCase();
      if (scheme != 'tcp' && scheme != 'tcps') {
        throw dpyError(ERR_FEATURE_NOT_SUPPORTED,
            args: {'feature': 'protocol $scheme', 'driver_type': 'thick'});
      }
      p.protocol = scheme;
      rest = rest.substring(schemeIdx + 3);
    }
    final queryIdx = rest.indexOf('?');
    if (queryIdx >= 0) {
      final query = rest.substring(queryIdx + 1);
      rest = rest.substring(0, queryIdx);
      for (final part in query.split('&')) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        final key = part.substring(0, eq).trim().toLowerCase();
        final value = Uri.decodeComponent(part.substring(eq + 1).trim());
        switch (key) {
          case 'ssl_server_dn_match':
            p.sslServerDnMatch = _parseBool(value);
          case 'ssl_server_cert_dn':
            p.sslServerCertDn = value.replaceAll('"', '');
          case 'wallet_location':
          case 'my_wallet_directory':
            p.walletLocation = value;
          case 'sdu':
            p.sdu = int.tryParse(value);
          case 'transport_connect_timeout':
          case 'connect_timeout':
            p.connectTimeout = _parseDuration(value);
          case 'pool_connection_class':
            p.cclass = value;
          case 'pool_purity':
            p.purity = _parsePurity(value);
        }
      }
    }
    final slash = rest.indexOf('/');
    var hostPort = rest;
    if (slash >= 0) {
      hostPort = rest.substring(0, slash);
      var service = rest.substring(slash + 1);
      final colon = service.indexOf(':');
      if (colon >= 0) {
        p.serverType = service.substring(colon + 1);
        service = service.substring(0, colon);
      }
      if (service.isNotEmpty) p.serviceName = service;
    }
    if (hostPort.startsWith('[')) {
      // IPv6 literal
      final end = hostPort.indexOf(']');
      p.host = hostPort.substring(1, end);
      final after = hostPort.substring(end + 1);
      if (after.startsWith(':')) p.port = int.parse(after.substring(1));
    } else {
      final parts = hostPort.split(':');
      if (parts[0].isNotEmpty) p.host = parts[0];
      if (parts.length > 1) p.port = int.parse(parts[1]);
      if (parts.length > 2 && p.serviceName == null) p.sid = parts[2];
    }
    if (p.protocol == 'tcps' && schemeIdx >= 0 && !hostPort.contains(':')) {
      p.port = 2484;
    }
    return p;
  }
}
