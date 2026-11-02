import 'dart:async';
import 'dart:collection';

import 'connect_params.dart';
import 'connection.dart';
import 'exceptions.dart';
import 'hooks.dart';
import 'placeholders.dart';
import 'thin/connection_impl.dart';

/// What [OracleConnectionPool.acquire] does when all connections are busy
/// and the pool has reached its maximum size.
enum PoolGetMode {
  /// Wait until a connection is released.
  wait,

  /// Raise an error immediately.
  noWait,

  /// Create a new connection even though the maximum has been reached.
  forceGet,

  /// Wait up to the wait timeout of the pool, then raise an error.
  timedWait,
}

/// Called the first time a newly created connection is acquired, for
/// example to set session state with ALTER SESSION.
typedef SessionCallback = FutureOr<void> Function(OracleConnection connection);

class _PooledSession {
  _PooledSession(this.impl) : created = DateTime.now() {
    lastUsed = created;
  }

  final ThinConnImpl impl;
  final DateTime created;
  late DateTime lastUsed;
  bool initialized = false;
}

/// A pool of connections to the database. Acquiring a connection from a pool
/// is much cheaper than establishing a new one, so pools should be used by
/// applications (such as servers) that perform many short units of work.
///
/// ```dart
/// final pool = await OracleConnectionPool.create(
///     user: 'scott', password: 'tiger', dsn: 'dbhost/orclpdb', min: 2, max: 10);
/// final rows = await pool.withConnection((conn) => conn.query('select ...'));
/// await pool.close();
/// ```
class OracleConnectionPool {
  OracleConnectionPool._(
    this.params, {
    required this.min,
    required this.max,
    required this.increment,
    required this.getMode,
    required this.waitTimeout,
    required this.timeout,
    required this.maxLifetimeSession,
    required this.pingInterval,
    required this.pingTimeout,
    required this.sessionCallback,
    required this.placeholderIdentifier,
  });

  /// Creates a pool and opens [min] connections. The connection parameters
  /// are the same as those of [OracleConnection.connect].
  static Future<OracleConnectionPool> create({
    String? user,
    String? password,
    String? dsn,
    String? host,
    int? port,
    String? serviceName,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? callTimeout,
    int stmtCacheSize = 20,
    String? configDir,
    String? walletLocation,
    String? walletPassword,
    ConnectParams? params,
    int min = 1,
    int max = 2,
    int increment = 1,
    PoolGetMode getMode = PoolGetMode.wait,
    Duration? waitTimeout,
    Duration? timeout,
    Duration? maxLifetimeSession,
    Duration pingInterval = const Duration(seconds: 60),
    Duration pingTimeout = const Duration(seconds: 5),
    SessionCallback? sessionCallback,
    PlaceholderIdentifier placeholderIdentifier = PlaceholderIdentifier.colon,
  }) async {
    if (min < 0 || max < 1 || min > max || increment < 1) {
      throw dpyError(ERR_INVALID_POOL_PARAMS);
    }
    params ??= dsn != null
        ? ConnectParams.fromDsn(dsn,
            user: user,
            password: password,
            connectTimeout: connectTimeout,
            callTimeout: callTimeout,
            stmtCacheSize: stmtCacheSize,
            configDir: configDir,
            walletLocation: walletLocation,
            walletPassword: walletPassword)
        : ConnectParams(
            host: host ?? 'localhost',
            port: port ?? 1521,
            serviceName: serviceName,
            user: user,
            password: password,
            connectTimeout: connectTimeout,
            callTimeout: callTimeout,
            stmtCacheSize: stmtCacheSize,
            walletLocation: walletLocation,
            walletPassword: walletPassword,
            connectString:
                '${host ?? 'localhost'}:${port ?? 1521}/${serviceName ?? ''}');
    final pool = OracleConnectionPool._(
      await applyParamsHooks(params),
      min: min,
      max: max,
      increment: increment,
      getMode: getMode,
      waitTimeout: waitTimeout,
      timeout: timeout,
      maxLifetimeSession: maxLifetimeSession,
      pingInterval: pingInterval,
      pingTimeout: pingTimeout,
      sessionCallback: sessionCallback,
      placeholderIdentifier: placeholderIdentifier,
    );
    await pool._fillToMinimum();
    pool._startHousekeeping();
    return pool;
  }

  final ConnectParams params;
  final int min;
  final int max;
  final int increment;
  final PoolGetMode getMode;
  final Duration? waitTimeout;

  /// Idle connections above [min] are closed after this time.
  final Duration? timeout;

  /// Connections older than this are closed when they are released or idle.
  final Duration? maxLifetimeSession;

  /// Connections idle for longer than this are pinged before being returned
  /// by [acquire] (a negative value disables pinging).
  final Duration pingInterval;
  final Duration pingTimeout;
  final SessionCallback? sessionCallback;
  final PlaceholderIdentifier placeholderIdentifier;

  final Queue<_PooledSession> _idle = Queue<_PooledSession>();
  final Map<ThinConnImpl, _PooledSession> _busy = {};
  final Queue<Completer<_PooledSession>> _waiters =
      Queue<Completer<_PooledSession>>();
  int _creating = 0;

  /// Sessions that exist or are being created; slots are reserved
  /// synchronously before a session is created and freed when it is closed,
  /// so concurrent callers never exceed the maximum.
  int _total = 0;
  bool _closed = false;
  Timer? _housekeeping;

  /// Number of connections currently open (idle and busy).
  int get opened => _total - _creating;

  /// Number of connections currently acquired.
  int get busy => _busy.length;

  /// Number of connections available for immediate use.
  int get idle => _idle.length;

  bool get isClosed => _closed;

  /// Creates a session; the caller must already have reserved a slot.
  Future<_PooledSession> _createSession() async {
    _creating++;
    try {
      final impl = ThinConnImpl(params);
      try {
        await impl.connect();
      } catch (_) {
        _total--;
        await impl.protocol.transport.disconnect();
        rethrow;
      }
      return _PooledSession(impl);
    } finally {
      _creating--;
    }
  }

  Future<void> _fillToMinimum() async {
    final needed = min - _total;
    if (needed <= 0) return;
    _total += needed;
    final sessions =
        await Future.wait([for (var i = 0; i < needed; i++) _createSession()]);
    // waiters (if any) are served first
    sessions.forEach(_addIdle);
  }

  void _startHousekeeping() {
    final interval = [timeout, maxLifetimeSession]
        .whereType<Duration>()
        .fold<Duration?>(null, (a, b) => a == null || b < a ? b : a);
    if (interval == null) return;
    final period = interval < const Duration(seconds: 1)
        ? interval
        : Duration(milliseconds: interval.inMilliseconds ~/ 2 + 1);
    _housekeeping = Timer.periodic(period, (_) => _closeExpiredIdle());
  }

  bool _isExpired(_PooledSession s, DateTime now) {
    final lifetime = maxLifetimeSession;
    return lifetime != null && now.difference(s.created) >= lifetime;
  }

  void _closeExpiredIdle() {
    if (_closed) return;
    final now = DateTime.now();
    final keep = <_PooledSession>[];
    final drop = <_PooledSession>[];
    for (final s in _idle) {
      final idleTooLong = timeout != null &&
          now.difference(s.lastUsed) >= timeout! &&
          _total - drop.length > min;
      if (idleTooLong || _isExpired(s, now)) {
        drop.add(s);
      } else {
        keep.add(s);
      }
    }
    if (drop.isEmpty) return;
    _idle
      ..clear()
      ..addAll(keep);
    for (final s in drop) {
      _closeSession(s);
    }
    unawaited(_fillToMinimum().catchError((_) {}));
  }

  /// Closes the session and frees its slot.
  void _closeSession(_PooledSession s) {
    _total--;
    unawaited(s.impl.close().catchError((_) {}));
  }

  /// Returns true if the session can be handed out, pinging it first if it
  /// has been idle for longer than the ping interval.
  Future<bool> _checkSession(_PooledSession s) async {
    if (!s.impl.isHealthy || _isExpired(s, DateTime.now())) return false;
    if (pingInterval.isNegative ||
        DateTime.now().difference(s.lastUsed) < pingInterval) {
      return true;
    }
    final saved = s.impl.callTimeout;
    s.impl.callTimeout = pingTimeout;
    try {
      await s.impl.ping();
      return true;
    } catch (_) {
      return false;
    } finally {
      s.impl.callTimeout = saved;
    }
  }

  /// Acquires a connection from the pool. Closing the returned connection
  /// releases it back to the pool.
  Future<OracleConnection> acquire() async {
    if (_closed) throw dpyError(ERR_POOL_NOT_OPEN);
    while (true) {
      final session = await _getSession();
      if (await _checkSession(session)) {
        _busy[session.impl] = session;
        final conn = OracleConnection.pooled(
            session.impl, placeholderIdentifier, () => _release(session));
        if (!session.initialized) {
          session.initialized = true;
          final callback = sessionCallback;
          if (callback != null) {
            try {
              await callback(conn);
            } catch (_) {
              await _release(session, drop: true);
              rethrow;
            }
          }
        }
        return conn;
      }
      _closeSession(session);
    }
  }

  Future<_PooledSession> _getSession() async {
    if (_idle.isNotEmpty) return _idle.removeLast();
    final capacity = max - _total;
    if (capacity > 0 || getMode == PoolGetMode.forceGet) {
      // create a batch of connections, returning the first one created
      final toCreate =
          capacity > 0 ? (increment < capacity ? increment : capacity) : 1;
      _total += toCreate;
      final futures = [for (var i = 0; i < toCreate; i++) _createSession()];
      for (final f in futures.skip(1)) {
        unawaited(f.then(_addIdle, onError: (_) {}));
      }
      return futures.first;
    }
    if (getMode == PoolGetMode.noWait) {
      throw dpyError(ERR_POOL_NO_CONNECTION_AVAILABLE);
    }
    final waiter = Completer<_PooledSession>();
    _waiters.add(waiter);
    final wait = getMode == PoolGetMode.timedWait ? waitTimeout : null;
    if (wait == null) return waiter.future;
    return waiter.future.timeout(wait, onTimeout: () {
      _waiters.remove(waiter);
      throw dpyError(ERR_POOL_NO_CONNECTION_AVAILABLE);
    });
  }

  /// Makes the session available, handing it to a waiter if there is one.
  void _addIdle(_PooledSession session) {
    if (_closed) {
      _closeSession(session);
      return;
    }
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete(session);
        return;
      }
    }
    _idle.addLast(session);
  }

  Future<void> _release(_PooledSession session, {bool drop = false}) async {
    if (_busy.remove(session.impl) == null) return;
    session.lastUsed = DateTime.now();
    var keep = !drop && session.impl.isHealthy && !_closed;
    if (keep && session.impl.txnInProgress) {
      try {
        // roll back any transaction left open by the application
        await session.impl.rollback();
      } catch (_) {
        keep = false;
      }
    }
    if (keep && _isExpired(session, session.lastUsed)) keep = false;
    if (keep && _total > max && _waiters.isEmpty) {
      // connections created beyond the maximum (forceGet) are not retained
      keep = false;
    }
    if (keep) {
      _addIdle(session);
      return;
    }
    _closeSession(session);
    if (_waiters.isNotEmpty && !_closed) {
      // replace the dropped connection for the waiting caller
      _total++;
      try {
        _addIdle(await _createSession());
      } catch (e) {
        if (_waiters.isNotEmpty) _waiters.removeFirst().completeError(e);
      }
    } else if (!_closed) {
      unawaited(_fillToMinimum().catchError((_) {}));
    }
  }

  /// Acquires a connection, runs [action] with it and releases it.
  Future<T> withConnection<T>(
      Future<T> Function(OracleConnection conn) action) async {
    final conn = await acquire();
    try {
      return await action(conn);
    } finally {
      await conn.close();
    }
  }

  /// Closes the pool. Unless [force] is set, an error is raised if
  /// connections are still acquired; with [force] they are closed as well.
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    if (_busy.isNotEmpty && !force) {
      throw dpyError(ERR_POOL_HAS_BUSY_CONNECTIONS);
    }
    _closed = true;
    _housekeeping?.cancel();
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(dpyError(ERR_POOL_NOT_OPEN));
    }
    final sessions = [..._idle, ..._busy.values];
    _idle.clear();
    _busy.clear();
    await Future.wait([
      for (final s in sessions) s.impl.close().catchError((_) {}),
    ]);
  }
}
