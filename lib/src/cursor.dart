import 'dart:async';
import 'dart:typed_data';

import 'connection.dart';
import 'exceptions.dart';
import 'placeholders.dart';
import 'thin/cursor_impl.dart';
import 'thin/messages/base.dart';
import 'thin/types.dart';
import 'thin/variable.dart';

/// How [OracleCursor.scroll] positions a scrollable cursor.
enum ScrollMode { relative, absolute, first, last }

/// A variable used for OUT and IN/OUT binds (and DML returning).
class OracleVar {
  OracleVar._(this.impl, this._connection);

  final BindVar impl;
  final OracleConnection _connection;

  DbType get type => impl.metadata.dbType;

  /// Number of elements the variable can hold.
  int get numElements => impl.numElements;

  /// Returns the value at the given position (the first by default). For
  /// DML returning statements, the value is the list of returned values.
  Object? getValue([int pos = 0]) {
    if (pos >= impl.values.length) return null;
    return _wrap(impl.values[pos]);
  }

  Object? get value => getValue(0);

  List<Object?> get values => [for (final v in impl.values) _wrap(v)];

  void setValue(int pos, Object? value) {
    impl.ensureSize(pos + 1);
    impl.values[pos] = value;
  }

  Object? _wrap(Object? v) {
    if (v is ThinCursorImpl) return OracleCursor.fromImpl(_connection, v);
    // lists hold the values returned by DML returning (bytes are values)
    if (v is List && v is! Uint8List) return [for (final e in v) _wrap(e)];
    return v;
  }

  @override
  String toString() => 'OracleVar(${type.name}, $values)';
}

/// Result of executing a statement with [OracleConnection.execute].
class OracleResult {
  OracleResult(this.columns, this.rows, this.rowCount, this.lastRowid);

  /// Metadata of the columns (empty for statements that are not queries).
  final List<ColumnMetadata> columns;

  /// The rows returned by a query.
  final List<List<Object?>> rows;

  /// Number of rows fetched (queries) or affected (DML).
  final int rowCount;

  /// The rowid of the last row affected by a DML statement.
  final String? lastRowid;

  /// The column names, in order.
  List<String> get columnNames => [for (final c in columns) c.name];

  /// The rows as maps of column name to value.
  List<Map<String, Object?>> get maps {
    final names = columnNames;
    return [
      for (final row in rows)
        {for (var i = 0; i < names.length; i++) names[i]: row[i]}
    ];
  }

  bool get isEmpty => rows.isEmpty;
  int get length => rows.length;
  List<Object?> operator [](int index) => rows[index];

  /// The first value of the first row (convenient for scalar queries).
  Object? get scalar => rows.isEmpty ? null : rows.first.first;
}

/// A cursor used to execute statements and fetch their results.
class OracleCursor {
  OracleCursor(this.connection) : _impl = ThinCursorImpl(connection.impl);

  OracleCursor.fromImpl(this.connection, ThinCursorImpl impl) : _impl = impl;

  final OracleConnection connection;
  final ThinCursorImpl _impl;
  bool _closed = false;

  /// Number of rows fetched per round trip (default 100). Larger values
  /// reduce round trips for big result sets at the cost of memory.
  int get arraySize => _impl.arraySize;
  set arraySize(int value) {
    if (value <= 0) throw dpyError(ERR_INVALID_ARRAYSIZE);
    _impl.arraySize = value;
  }

  /// Number of rows returned with the execute round trip (default 2).
  int get prefetchRows => _impl.prefetchRows;
  set prefetchRows(int value) => _impl.prefetchRows = value;

  /// Whether the cursor is scrollable; must be set before [execute]. A
  /// scrollable cursor can be positioned with [scroll].
  bool get scrollable => _impl.scrollable;
  set scrollable(bool value) => _impl.scrollable = value;

  /// Moves the position of a scrollable cursor: the next fetch returns the
  /// row at the new position. With [ScrollMode.relative] (the default),
  /// [value] is relative to the current row; with [ScrollMode.absolute] it
  /// is a row number (1 based); [ScrollMode.first] and [ScrollMode.last]
  /// ignore it.
  Future<void> scroll([int value = 0, ScrollMode mode = ScrollMode.relative]) {
    _checkOpen();
    _checkQuery();
    return _impl.scroll(value, mode.name);
  }

  /// Return CLOB/NCLOB/BLOB columns directly as String/Uint8List values
  /// (default true).
  bool get fetchLobsAsValues => _impl.fetchLobsAsValues;
  set fetchLobsAsValues(bool value) => _impl.fetchLobsAsValues = value;

  /// Return NUMBER columns as exact decimal strings (default false).
  bool get fetchNumbersAsStrings => _impl.fetchNumbersAsStrings;
  set fetchNumbersAsStrings(bool value) => _impl.fetchNumbersAsStrings = value;

  /// Metadata of the columns of the last query executed, or null.
  List<ColumnMetadata>? get description => _impl.fetchMetadata;

  /// Rows fetched so far (queries) or rows affected (DML).
  int get rowCount => _impl.rowCount;

  String? get lastRowid => _impl.rowCount > 0 ? _impl.lastRowid : null;

  /// Errors from executeMany() when batch errors are enabled.
  List<BatchError>? get batchErrors => _impl.batchErrors;

  /// Rows affected by each iteration of executeMany() when enabled.
  List<int>? get dmlRowCounts {
    final counts = _impl.dmlRowCounts;
    if (counts == null) {
      throw dpyError(ERR_ARRAY_DML_ROW_COUNTS_NOT_ENABLED);
    }
    return counts;
  }

  /// Cursors returned by DBMS_SQL.RETURN_RESULT() in a PL/SQL block.
  List<OracleCursor> get implicitResults {
    final results = _impl.implicitResults;
    if (results == null) throw dpyError(ERR_NO_STATEMENT_EXECUTED);
    return [for (final r in results) OracleCursor.fromImpl(connection, r)];
  }

  OracleException? get warning => _impl.warning;

  /// The names of the bind variables of the prepared statement.
  List<String> get bindNames =>
      _impl.statement?.bindInfoDict.keys.toList() ?? const [];

  bool get isClosed => _closed;

  /// The placeholder style of the statements executed by this cursor; when
  /// null, the style of the connection is used.
  PlaceholderIdentifier? placeholderIdentifier;

  String _prepareSql(String sql) => prepareSql(
      sql, placeholderIdentifier ?? connection.placeholderIdentifier);

  void _checkOpen() {
    if (_closed) throw dpyError(ERR_CURSOR_NOT_OPEN);
    connection.checkConnected();
  }

  Object? _unwrapParams(Object? params) {
    if (params is List) {
      return [for (final p in params) p is OracleVar ? p.impl : p];
    } else if (params is Map) {
      return {
        for (final e in params.entries)
          e.key: e.value is OracleVar ? (e.value as OracleVar).impl : e.value
      };
    }
    return params;
  }

  /// Creates a variable for OUT or IN/OUT binds.
  OracleVar variable(DbType type,
      {int size = 0,
      int arraySize = 1,
      bool isArray = false,
      Object? inValue}) {
    final v = BindVar.forType(type,
        size: size, numElements: arraySize, isArray: isArray);
    if (type == DbType.cursor) {
      for (var i = 0; i < v.values.length; i++) {
        v.values[i] = ThinCursorImpl(connection.impl);
      }
    }
    if (inValue != null) {
      if (isArray && inValue is List) {
        v.ensureSize(inValue.length);
        v.values.setRange(0, inValue.length, inValue);
        v.numElementsInArray = inValue.length;
      } else {
        v.values[0] = inValue;
      }
    }
    return OracleVar._(v, connection);
  }

  /// Executes a statement. [params] may be a positional [List] or a [Map]
  /// of bind names to values. For queries, rows can then be fetched.
  ///
  /// With [PlaceholderIdentifier.onlyQuestionMark], `?` placeholders are
  /// used and [params] must be a [List].
  Future<void> execute(String sql, [Object? params]) async {
    _checkOpen();
    _impl.prepare(_prepareSql(sql));
    _impl.bind(_unwrapParams(params));
    await _impl.execute();
  }

  /// Executes a statement once for each row of parameters.
  Future<void> executeMany(String sql, List<Object?> rows,
      {bool batchErrors = false, bool arrayDmlRowCounts = false}) async {
    _checkOpen();
    if (rows.isEmpty) return;
    _impl.prepare(_prepareSql(sql));
    _impl.bindMany([for (final r in rows) _unwrapParams(r)]);
    await _impl.executeMany(rows.length,
        batchErrors: batchErrors, arrayDmlRowCounts: arrayDmlRowCounts);
  }

  /// Parses the statement without executing it (queries are described).
  Future<void> parse(String sql) async {
    _checkOpen();
    _impl.prepare(_prepareSql(sql));
    await _impl.parse();
  }

  Future<List<Object?>?> fetchOne() {
    _checkOpen();
    _checkQuery();
    return _impl.fetchOne();
  }

  Future<List<List<Object?>>> fetchMany([int? numRows]) {
    _checkOpen();
    _checkQuery();
    return _impl.fetchMany(numRows ?? arraySize);
  }

  Future<List<List<Object?>>> fetchAll() {
    _checkOpen();
    _checkQuery();
    return _impl.fetchAll();
  }

  /// Streams the remaining rows; rows are fetched in batches of [arraySize].
  Stream<List<Object?>> rows() async* {
    _checkOpen();
    _checkQuery();
    while (true) {
      final batch = _impl.takeBufferedRows();
      for (final row in batch) {
        yield row;
      }
      if (!await _impl.fetchNextBatch()) {
        if (_impl.bufferedRows == 0) break;
      }
    }
  }

  void _checkQuery() {
    if (!_impl.isQuery) throw dpyError(ERR_NOT_A_QUERY);
  }

  /// Calls a stored procedure with positional parameters.
  Future<void> callProc(String name, [List<Object?> params = const []]) async {
    final placeholders =
        [for (var i = 0; i < params.length; i++) ':${i + 1}'].join(', ');
    await execute('begin $name($placeholders); end;', params);
  }

  /// Calls a stored function returning a value of [returnType].
  Future<Object?> callFunc(String name, DbType returnType,
      [List<Object?> params = const []]) async {
    final ret = variable(returnType);
    final placeholders =
        [for (var i = 0; i < params.length; i++) ':${i + 2}'].join(', ');
    await execute('begin :1 := $name($placeholders); end;', [ret, ...params]);
    return ret.value;
  }

  /// Closes the cursor; its statement is returned to the statement cache.
  void close() {
    if (_closed) return;
    _closed = true;
    _impl.close();
  }
}
