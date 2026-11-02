import 'dart:async';
import 'dart:io';

import 'connect_params.dart';
import 'cursor.dart';
import 'thin/types.dart';
import 'exceptions.dart';
import 'hooks.dart';
import 'lob.dart';
import 'placeholders.dart';
import 'thin/connection_impl.dart';
import 'thin/constants.dart';
import 'thin/messages/tpc.dart';

/// A connection to an Oracle Database (thin mode, pure Dart).
///
/// Requests on a connection are serialized: concurrent calls are queued and
/// sent one at a time. Use one connection per concurrent unit of work.
class OracleConnection {
  OracleConnection._(this.impl, this.placeholderIdentifier) : _release = null;

  /// Creates a connection object for a session acquired from a pool;
  /// closing it calls [release] instead of closing the session.
  OracleConnection.pooled(
      this.impl, this.placeholderIdentifier, Future<void> Function() release)
      : _release = release;

  final Future<void> Function()? _release;

  /// Whether the connection was acquired from a pool.
  bool get isPooled => _release != null;

  /// Internal implementation (not part of the public API).
  final ThinConnImpl impl;
  bool _closed = false;

  /// Connects to the database.
  ///
  /// The database can be identified by [dsn] (an Easy Connect string such
  /// as `localhost:1521/FREEPDB1` or a full connect descriptor) or by
  /// [host], [port] and [serviceName] / [sid]. Alternatively, a complete
  /// [params] object can be supplied.
  ///
  /// [placeholderIdentifier] selects the default bind placeholder style
  /// (see [OracleConnection.placeholderIdentifier]).
  static Future<OracleConnection> connect({
    String? user,
    String? password,
    String? dsn,
    String? host,
    int? port,
    String protocol = 'tcp',
    String? serviceName,
    String? sid,
    String? newPassword,
    int mode = AuthMode.defaultMode,
    int sdu = 8192,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? callTimeout,
    int stmtCacheSize = 20,
    String? edition,
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
    ConnectParams? params,
    PlaceholderIdentifier placeholderIdentifier = PlaceholderIdentifier.colon,
  }) async {
    final protocolHook = dsn == null ? null : protocolHookFor(dsn);
    if (params == null && protocolHook != null) {
      // the connect string is resolved by a registered protocol hook (for
      // example a configuration provider)
      final (hook, name, argument) = protocolHook;
      final base = ConnectParams(
          user: user,
          password: password,
          newPassword: newPassword,
          mode: mode,
          sdu: sdu,
          connectTimeout: connectTimeout,
          callTimeout: callTimeout,
          stmtCacheSize: stmtCacheSize,
          edition: edition,
          appContext: appContext,
          sslServerDnMatch: sslServerDnMatch ?? true,
          sslServerCertDn: sslServerCertDn,
          walletLocation: walletLocation,
          walletPassword: walletPassword,
          securityContext: securityContext,
          accessToken: accessToken,
          accessTokenCallback: accessTokenCallback,
          privateKey: privateKey,
          cclass: cclass,
          purity: purity);
      try {
        params = await hook(name, argument, base);
      } on OracleException {
        rethrow;
      } catch (e) {
        throw dpyError(ERR_PROTOCOL_HANDLER_FAILED,
            args: {'protocol': name, 'arg': argument}, message: '$e', cause: e);
      }
    }
    if (params == null) {
      if (dsn != null) {
        params = ConnectParams.fromDsn(dsn,
            user: user,
            password: password,
            newPassword: newPassword,
            mode: mode,
            sdu: sdu,
            connectTimeout: connectTimeout,
            callTimeout: callTimeout,
            stmtCacheSize: stmtCacheSize,
            edition: edition,
            appContext: appContext,
            configDir: configDir,
            sslServerDnMatch: sslServerDnMatch,
            sslServerCertDn: sslServerCertDn,
            walletLocation: walletLocation,
            walletPassword: walletPassword,
            securityContext: securityContext,
            accessToken: accessToken,
            accessTokenCallback: accessTokenCallback,
            privateKey: privateKey,
            cclass: cclass,
            purity: purity);
      } else {
        final h = host ?? 'localhost';
        final pt = port ?? (protocol == 'tcps' ? 2484 : 1521);
        params = ConnectParams(
            host: h,
            port: pt,
            protocol: protocol,
            serviceName: serviceName,
            sid: sid,
            user: user,
            password: password,
            newPassword: newPassword,
            mode: mode,
            sdu: sdu,
            connectTimeout: connectTimeout,
            callTimeout: callTimeout,
            stmtCacheSize: stmtCacheSize,
            edition: edition,
            appContext: appContext,
            sslServerDnMatch: sslServerDnMatch ?? true,
            sslServerCertDn: sslServerCertDn,
            walletLocation: walletLocation,
            walletPassword: walletPassword,
            securityContext: securityContext,
            accessToken: accessToken,
            accessTokenCallback: accessTokenCallback,
            privateKey: privateKey,
            cclass: cclass,
            purity: purity,
            connectString: '$h:$pt/${serviceName ?? sid ?? ''}');
      }
    }
    return connectWithParams(params,
        placeholderIdentifier: placeholderIdentifier);
  }

  /// Connects using a complete set of parameters.
  static Future<OracleConnection> connectWithParams(ConnectParams params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.colon}) async {
    params = await applyParamsHooks(params);
    final impl = ThinConnImpl(params);
    try {
      await impl.connect();
    } catch (_) {
      await impl.protocol.transport.disconnect();
      rethrow;
    }
    return OracleConnection._(impl, placeholderIdentifier);
  }

  void checkConnected() {
    if (_closed) throw dpyError(ERR_NOT_CONNECTED);
  }

  /// The placeholder style used by default by the statements executed on
  /// this connection: Oracle style (`:name`, `:1`) or question marks (`?`).
  ///
  /// ```dart
  /// conn.placeholderIdentifier = PlaceholderIdentifier.onlyQuestionMark;
  /// await conn.query('select * from t where id = ? and name = ?', [1, 'a']);
  /// ```
  PlaceholderIdentifier placeholderIdentifier;

  /// Maximum time each round trip to the database may take. When it is
  /// exceeded, the call is interrupted and DPY-4024 is raised (the
  /// connection remains usable). Null (the default) means no limit.
  Duration? get callTimeout => impl.callTimeout;
  set callTimeout(Duration? value) => impl.callTimeout = value;

  /// Interrupts the call currently in progress on this connection, which
  /// then fails with ORA-01013 (user requested cancel). Has no effect when
  /// no call is in progress.
  void cancel() {
    if (!_closed) impl.protocol.breakExternal();
  }

  /// Whether each statement is committed automatically (default false).
  bool get autocommit => impl.autocommit;
  set autocommit(bool value) => impl.autocommit = value;

  /// The version of the database as a list of five integers.
  List<int> get serverVersion => impl.serverVersion;

  /// The version of the database as a string, e.g. "23.26.0.0.0".
  String get version => impl.serverVersion.join('.');

  bool get isClosed => _closed;

  /// Returns true if the connection is usable as far as is known locally
  /// (no round trip is performed; use [ping] for that).
  bool get isHealthy => !_closed && impl.isHealthy;

  /// Whether a transaction is currently in progress.
  bool get transactionInProgress => impl.txnInProgress;

  int get sessionId => impl.sessionId;
  int get serialNumber => impl.serialNum;
  String? get dbName => impl.dbName;
  String? get dbDomain => impl.dbDomain;
  String? get serviceName => impl.serviceName;
  String? get instanceName => impl.instanceName;
  int get maxOpenCursors => impl.maxOpenCursors;
  int get maxIdentifierLength => impl.maxIdentifierLength;
  String? get edition => impl.edition;
  OracleException? get warning => impl.warning;

  /// The negotiated session data unit size.
  int get sdu => impl.protocol.caps.sdu;

  /// Number of statements kept in the statement cache.
  int get stmtCacheSize => impl.statementCache.maxSize;
  set stmtCacheSize(int value) => impl.statementCache.resize(value);

  /// The current schema; setting it takes effect on the next round trip.
  String? get currentSchema => impl.currentSchema;
  set currentSchema(String? value) {
    impl.currentSchema = value;
    impl.currentSchemaModified = true;
  }

  set module(String? value) {
    impl.module = value;
    impl.moduleModified = true;
  }

  set action(String? value) {
    impl.action = value;
    impl.actionModified = true;
  }

  set clientIdentifier(String? value) {
    impl.clientIdentifier = value;
    impl.clientIdentifierModified = true;
  }

  set clientInfo(String? value) {
    impl.clientInfo = value;
    impl.clientInfoModified = true;
  }

  set dbop(String? value) {
    impl.dbop = value;
    impl.dbopModified = true;
  }

  /// Flags of [tpcBegin].
  static const int tpcBeginNew = TPC_TXN_FLAGS_NEW;
  static const int tpcBeginJoin = TPC_TXN_FLAGS_JOIN;
  static const int tpcBeginResume = TPC_TXN_FLAGS_RESUME;
  static const int tpcBeginPromote = TPC_TXN_FLAGS_PROMOTE;

  /// Flags of [tpcEnd].
  static const int tpcEndNormal = 0;
  static const int tpcEndSuspend = 0x00100000;

  /// Internal and external names sent with TPC transactions.
  String? get internalName => impl.internalName;
  set internalName(String? value) => impl.internalName = value;
  String? get externalName => impl.externalName;
  set externalName(String? value) => impl.externalName = value;

  /// Begins (or joins, resumes or promotes, according to [flags]) a
  /// two-phase commit transaction identified by [xid]. [timeout] is the
  /// number of seconds the transaction can be inactive before it is rolled
  /// back.
  Future<void> tpcBegin(Xid xid, {int flags = tpcBeginNew, int timeout = 0}) {
    checkConnected();
    if (flags != tpcBeginNew &&
        flags != tpcBeginJoin &&
        flags != tpcBeginResume &&
        flags != tpcBeginPromote) {
      throw dpyError(ERR_INVALID_TPC_BEGIN_FLAGS);
    }
    return impl.tpcBegin(xid, flags, timeout);
  }

  /// Ends (or, with [tpcEndSuspend], suspends) the work on the transaction.
  Future<void> tpcEnd([Xid? xid, int flags = tpcEndNormal]) {
    checkConnected();
    if (flags != tpcEndNormal && flags != tpcEndSuspend) {
      throw dpyError(ERR_INVALID_TPC_END_FLAGS);
    }
    return impl.tpcEnd(xid, flags);
  }

  /// Prepares the transaction for commit; returns false if no commit is
  /// required (the transaction made no changes).
  Future<bool> tpcPrepare([Xid? xid]) {
    checkConnected();
    return impl.tpcPrepare(xid);
  }

  /// Commits the transaction, which must have been prepared unless
  /// [onePhase] is set.
  Future<void> tpcCommit([Xid? xid, bool onePhase = false]) {
    checkConnected();
    return impl.tpcCommit(xid, onePhase);
  }

  /// Rolls back the transaction.
  Future<void> tpcRollback([Xid? xid]) {
    checkConnected();
    return impl.tpcRollback(xid);
  }

  /// Returns the pending transactions that require recovery (requires
  /// access to the DBA_PENDING_TRANSACTIONS view).
  Future<List<Xid>> tpcRecover() async {
    final rows = await query(
        'select formatid, globalid, branchid from dba_pending_transactions');
    return [
      for (final r in rows) Xid(r[0] as int, r[1] as Object, r[2] as Object)
    ];
  }

  /// Creates a temporary LOB of the given type (CLOB, NCLOB or BLOB),
  /// optionally writing [data] to it. Temporary LOBs can be bound to
  /// statements and should be freed with [OracleLob.free] when no longer
  /// needed.
  Future<OracleLob> createLob(DbType type, [Object? data]) async {
    checkConnected();
    if (type != DbType.clob && type != DbType.nclob && type != DbType.blob) {
      throw dpyError(ERR_LOB_OF_WRONG_TYPE, args: {
        'actual_type_name': type.name,
        'expected_type_name': 'CLOB, NCLOB or BLOB',
      });
    }
    final lob = await OracleLob.createTemporary(impl, type);
    if (data != null) await lob.write(data);
    return lob;
  }

  /// Creates a cursor.
  OracleCursor cursor() {
    checkConnected();
    return OracleCursor(this);
  }

  /// Executes a statement and, for queries, fetches all of the rows.
  Future<OracleResult> execute(String sql, [Object? params]) async {
    final cursor = OracleCursor(this);
    try {
      await cursor.execute(sql, params);
      if (cursor.description != null) {
        final rows = await cursor.fetchAll();
        return OracleResult(
            cursor.description!, rows, cursor.rowCount, cursor.lastRowid);
      }
      return OracleResult(
          const [], const [], cursor.rowCount, cursor.lastRowid);
    } finally {
      cursor.close();
    }
  }

  /// Executes a query and returns all of its rows.
  Future<List<List<Object?>>> query(String sql, [Object? params]) async =>
      (await execute(sql, params)).rows;

  /// Executes a query and returns the first row, or null.
  Future<List<Object?>?> queryOne(String sql, [Object? params]) async {
    final cursor = OracleCursor(this)..prefetchRows = 1;
    try {
      await cursor.execute(sql, params);
      return await cursor.fetchOne();
    } finally {
      cursor.close();
    }
  }

  /// Streams the rows of a query, fetching [arraySize] rows per round trip.
  Stream<List<Object?>> stream(String sql,
      [Object? params, int arraySize = 1000]) async* {
    final cursor = OracleCursor(this)
      ..arraySize = arraySize
      ..prefetchRows = arraySize;
    try {
      await cursor.execute(sql, params);
      yield* cursor.rows();
    } finally {
      cursor.close();
    }
  }

  /// Executes a DML statement for each row of parameters and returns the
  /// total number of rows affected.
  Future<int> executeMany(String sql, List<Object?> rows,
      {bool batchErrors = false}) async {
    final cursor = OracleCursor(this);
    try {
      await cursor.executeMany(sql, rows, batchErrors: batchErrors);
      return cursor.rowCount;
    } finally {
      cursor.close();
    }
  }

  /// Runs [action] in a transaction: commits if it completes and rolls back
  /// if it throws.
  Future<T> transaction<T>(
      Future<T> Function(OracleConnection conn) action) async {
    try {
      final result = await action(this);
      await commit();
      return result;
    } catch (_) {
      await rollback();
      rethrow;
    }
  }

  Future<void> commit() {
    checkConnected();
    return impl.commit();
  }

  Future<void> rollback() {
    checkConnected();
    return impl.rollback();
  }

  /// Performs a round trip to check that the connection is alive.
  Future<void> ping() {
    checkConnected();
    return impl.ping();
  }

  /// Closes the connection; any open transaction is rolled back. A
  /// connection acquired from a pool is released back to the pool instead.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final release = _release;
    if (release != null) return release();
    await impl.close();
  }
}
