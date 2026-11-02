import '../exceptions.dart';
import '../lob.dart';
import 'connection_impl.dart';
import 'constants.dart';
import 'messages/base.dart';
import 'messages/execute.dart';
import 'statement.dart';
import 'types.dart';
import 'variable.dart';

/// Internal state of a cursor.
class ThinCursorImpl {
  ThinCursorImpl(this.conn);

  final ThinConnImpl conn;
  Statement? statement;
  List<BindVar>? fetchVars;
  List<ColumnMetadata>? fetchMetadata;
  int numColumns = 0;

  /// Number of rows fetched per round trip after the first one.
  int arraySize = 100;

  /// Number of rows returned by the execute round trip of a query.
  int prefetchRows = 2;
  int fetchArraySize = 0;
  int rowCount = 0;
  bool moreRowsToFetch = false;

  /// Whether the cursor is scrollable (must be set before executing).
  bool scrollable = false;

  /// Row numbers (1 based) of the first row in the buffer and of the row
  /// after the last one, used by scrollable cursors.
  int _bufferMinRow = 0;
  int _bufferMaxRow = 0;

  /// Return CLOB/BLOB/NCLOB columns as String/Uint8List values.
  bool fetchLobsAsValues = true;

  /// Return NUMBER columns as decimal strings (no loss of precision).
  bool fetchNumbersAsStrings = false;

  List<List<Object?>> _rows = [];
  int _rowIndex = 0;
  List<Object?>? lastRow;

  List<BatchError>? batchErrors;
  List<int>? dmlRowCounts;
  String? lastRowid;
  List<ThinCursorImpl>? implicitResults;
  OracleException? warning;

  /// Bind variables retained between executions (by position or by name) so
  /// that unchanged bind metadata allows cheap re-executions.
  List<BindVar?> _bindVarsByPos = [];
  final Map<String, BindVar> _bindVarsByName = {};

  bool get isQuery => fetchVars != null;

  int get bufferedRows => _rows.length - _rowIndex;

  void clearRows() {
    _rows = [];
    _rowIndex = 0;
  }

  void addRow(List<Object?> row) {
    _rows.add(row);
    lastRow = row;
  }

  BindVar createFetchVar(ColumnMetadata metadata) {
    final define = metadata.copyWith();
    final variable = BindVar(define, numElements: 0)..fetchMetadata = metadata;
    final typeNum = metadata.dbType.oraTypeNum;
    if (metadata.isOson && typeNum != ORA_TYPE_NUM_JSON) {
      // binary JSON stored in a BLOB: fetched as bytes and decoded
      define.dbType = DbType.longRaw;
      metadata.dbType = DbType.longRaw;
      variable.jsonDecode = true;
    } else if (metadata.isJson && typeNum != ORA_TYPE_NUM_JSON) {
      // JSON text stored in a VARCHAR2/CLOB column
      variable.jsonDecode = true;
      if (typeNum == ORA_TYPE_NUM_CLOB) {
        define.dbType = DbType.long;
        metadata.dbType = DbType.long;
      }
    } else if (fetchLobsAsValues) {
      DbType? replacement;
      if (metadata.dbType == DbType.blob) {
        replacement = DbType.longRaw;
      } else if (metadata.dbType == DbType.clob) {
        replacement = DbType.long;
      } else if (metadata.dbType == DbType.nclob) {
        replacement = DbType.longNVarchar;
      }
      if (replacement != null) {
        define.dbType = replacement;
        metadata.dbType = replacement;
      }
    }
    if (typeNum == ORA_TYPE_NUM_NUMBER) {
      final isInteger = metadata.scale == 0 ||
          (metadata.scale == -127 && metadata.precision == 0);
      variable.numberAsDouble = !isInteger;
      variable.numberAsString = fetchNumbersAsStrings;
    }
    finalizeMetadata(define);
    return variable;
  }

  void prepare(String sql, {bool cacheStatement = true}) {
    final previous = statement;
    if (previous != null) {
      if (previous.sql == sql && !previous.isDdl) {
        // re-executing the same statement keeps the open cursor
        _resetForExecute();
        return;
      }
      conn.returnStatement(previous);
      _bindVarsByPos = [];
      _bindVarsByName.clear();
    }
    statement = conn.getStatement(sql, cacheStatement);
    _resetForExecute();
  }

  void _resetForExecute() {
    final stmt = statement!;
    fetchMetadata = stmt.fetchMetadata;
    fetchVars = stmt.fetchVars;
    numColumns = stmt.numColumns;
    rowCount = 0;
    batchErrors = null;
    dmlRowCounts = null;
    implicitResults = null;
    warning = null;
    lastRow = null;
    clearRows();
  }

  /// Returns a variable able to hold [value], reusing [existing] when the
  /// type is the same and the size is sufficient.
  BindVar _varForValue(BindVar? existing, Object? value) {
    if (value is BindVar) return value;
    final stmt = statement!;
    final m = metadataFromValue(value, conn.supportsBool, stmt.isPlsql);
    if (existing != null && !existing.isArray && existing.numElements == 1) {
      final em = existing.metadata;
      if (value == null ||
          (em.dbType == m.dbType && em.maxSize >= m.maxSize) ||
          (em.dbType == DbType.timestamp && m.dbType == DbType.date)) {
        existing.values[0] = value;
        return existing;
      }
      if (em.dbType == m.dbType && m.maxSize > em.maxSize) {
        // grow generously to avoid rebinding for slightly longer values
        m.maxSize = m.maxSize * 2 < 4000 ? m.maxSize * 2 : m.maxSize;
      }
    }
    finalizeMetadata(m);
    return BindVar(m)..values[0] = value;
  }

  String _normalizeBindName(String name) {
    if (name.startsWith('"') && name.endsWith('"') && name.length > 1) {
      return name.substring(1, name.length - 1);
    }
    var n = name.toUpperCase();
    if (n.startsWith(':')) n = n.substring(1);
    return n;
  }

  /// Binds the parameters, which may be a positional [List] or a [Map] of
  /// names to values.
  void bind(Object? params) {
    final stmt = statement!;
    if (params == null) {
      if (stmt.bindInfoList.isNotEmpty &&
          _bindVarsByPos.isEmpty &&
          _bindVarsByName.isEmpty) {
        throw dpyError(ERR_MISSING_BIND_VALUE,
            args: {'name': stmt.bindInfoList.first.name});
      }
    } else if (params is List) {
      final numBinds = stmt.bindInfoList.length;
      if (numBinds != params.length) {
        throw dpyError(ERR_WRONG_NUMBER_OF_POSITIONAL_BINDS,
            args: {'expected_num': numBinds, 'actual_num': params.length});
      }
      if (_bindVarsByPos.length != numBinds) {
        _bindVarsByPos = List<BindVar?>.filled(numBinds, null);
      }
      for (var i = 0; i < numBinds; i++) {
        final variable = _varForValue(_bindVarsByPos[i], params[i]);
        _bindVarsByPos[i] = variable;
        stmt.setVar(stmt.bindInfoList[i], variable);
      }
    } else if (params is Map) {
      for (final entry in params.entries) {
        final name = _normalizeBindName(entry.key as String);
        final infos = stmt.bindInfoDict[name];
        if (infos == null) {
          throw dpyError(ERR_INVALID_BIND_NAME, args: {'name': entry.key});
        }
        final variable = _varForValue(_bindVarsByName[name], entry.value);
        _bindVarsByName[name] = variable;
        for (final info in infos) {
          stmt.setVar(info, variable);
        }
      }
    } else {
      throw dpyError(ERR_WRONG_EXECUTE_PARAMETERS_TYPE);
    }
    for (final info in stmt.bindInfoList) {
      if (info.variable == null) {
        throw dpyError(ERR_MISSING_BIND_VALUE, args: {'name': info.name});
      }
    }
  }

  /// Binds the rows of parameters for executeMany().
  void bindMany(List<Object?> rows) {
    final stmt = statement!;
    final numRows = rows.length;
    if (rows.first is List) {
      final numBinds = stmt.bindInfoList.length;
      final vars = <BindVar>[];
      for (var pos = 0; pos < numBinds; pos++) {
        ColumnMetadata? metadata;
        final values = List<Object?>.filled(numRows, null);
        BindVar? explicit;
        for (var r = 0; r < numRows; r++) {
          final row = rows[r] as List;
          if (row.length != numBinds) {
            throw dpyError(ERR_WRONG_NUMBER_OF_POSITIONAL_BINDS,
                args: {'expected_num': numBinds, 'actual_num': row.length});
          }
          final value = row[pos];
          if (value is BindVar) {
            explicit = value;
            break;
          }
          values[r] = value;
          final m = metadataFromValue(value, conn.supportsBool, stmt.isPlsql);
          if (metadata == null) {
            metadata = m;
          } else {
            mergeMetadata(metadata, m, value);
          }
        }
        if (explicit != null) {
          vars.add(explicit);
          continue;
        }
        finalizeMetadata(metadata!);
        final variable = BindVar(metadata, numElements: numRows);
        variable.values = values;
        vars.add(variable);
      }
      for (var pos = 0; pos < numBinds; pos++) {
        stmt.setVar(stmt.bindInfoList[pos], vars[pos]);
      }
    } else if (rows.first is Map) {
      final metadataByName = <String, ColumnMetadata>{};
      final valuesByName = <String, List<Object?>>{};
      for (var r = 0; r < numRows; r++) {
        final row = rows[r] as Map;
        for (final entry in row.entries) {
          final name = _normalizeBindName(entry.key as String);
          if (!stmt.bindInfoDict.containsKey(name)) {
            throw dpyError(ERR_INVALID_BIND_NAME, args: {'name': entry.key});
          }
          final m =
              metadataFromValue(entry.value, conn.supportsBool, stmt.isPlsql);
          final existing = metadataByName[name];
          if (existing == null) {
            metadataByName[name] = m;
          } else {
            mergeMetadata(existing, m, entry.value);
          }
          (valuesByName[name] ??= List<Object?>.filled(numRows, null))[r] =
              entry.value;
        }
      }
      for (final name in metadataByName.keys) {
        final metadata = metadataByName[name]!;
        finalizeMetadata(metadata);
        final variable = BindVar(metadata, numElements: numRows)
          ..values = valuesByName[name]!;
        for (final info in stmt.bindInfoDict[name]!) {
          stmt.setVar(info, variable);
        }
      }
    } else {
      throw dpyError(ERR_WRONG_EXECUTEMANY_PARAMETERS_TYPE);
    }
    for (final info in stmt.bindInfoList) {
      if (info.variable == null) {
        throw dpyError(ERR_MISSING_BIND_VALUE, args: {'name': info.name});
      }
    }
    // variables used by executeMany are not reused by later executions
    _bindVarsByPos = [];
    _bindVarsByName.clear();
  }

  /// Discards the server cursor if a bind type change requires a new parse.
  void _checkReparse() {
    final stmt = statement!;
    if (!stmt.requiresReparse) return;
    stmt.requiresReparse = false;
    conn.statementCache.clearCursor(stmt);
    stmt.fetchMetadata = null;
    stmt.numColumns = 0;
    fetchVars = null;
    fetchMetadata = null;
    numColumns = 0;
  }

  /// PL/SQL cannot bind strings or bytes longer than 32767 bytes, so such
  /// values are bound as temporary LOBs (read back after the call).
  Future<void> _convertLargePlsqlBinds() async {
    final stmt = statement!;
    if (!stmt.isPlsql) return;
    final seen = <BindVar>{};
    for (final info in stmt.bindInfoList) {
      final variable = info.variable;
      if (variable == null || !seen.add(variable)) continue;
      if (variable.metadata.maxSize <= 32767) continue;
      final type = variable.metadata.dbType;
      DbType? lobType;
      if (type == DbType.raw || type == DbType.longRaw) {
        lobType = DbType.blob;
      } else if (type.csfrm == CS_FORM_NCHAR) {
        lobType = DbType.nclob;
      } else if (type == DbType.varchar ||
          type == DbType.char ||
          type == DbType.long) {
        lobType = DbType.clob;
      }
      if (lobType == null) continue;
      for (var i = 0; i < variable.values.length; i++) {
        final value = variable.values[i];
        if (value == null || value is OracleLob) continue;
        final lob = await OracleLob.createTemporary(conn, lobType);
        await lob.write(value);
        variable.values[i] = lob;
      }
      // only the type changes; the sizes are retained (as python-oracledb
      // does), which the server requires for OUT binds
      variable.metadata.dbType = lobType;
      variable.readLobsBack = true;
      for (final other in stmt.bindInfoList) {
        if (other.variable == variable) stmt.setVar(other, variable);
      }
    }
  }

  /// Replaces the temporary LOBs of converted binds by their values.
  Future<void> _readLobsBack() async {
    final seen = <BindVar>{};
    for (final info in statement!.bindInfoList) {
      final variable = info.variable;
      if (variable == null || !variable.readLobsBack || !seen.add(variable)) {
        continue;
      }
      for (var i = 0; i < variable.values.length; i++) {
        final value = variable.values[i];
        if (value is OracleLob) {
          variable.values[i] = await value.read();
          value.free();
        }
      }
    }
  }

  ExecuteMessage _executeMessage() {
    final message = ExecuteMessage(this)..numExecs = 1;
    if (scrollable) {
      message
        ..fetchOrientation = TNS_FETCH_ORIENTATION_CURRENT
        ..fetchPos = rowCount + 1;
    }
    return message;
  }

  Future<void> execute() async {
    _checkReparse();
    await _convertLargePlsqlBinds();
    final message = _executeMessage();
    await conn.protocol.processSingleMessage(message);
    warning = message.warning;
    _bufferMinRow = rowCount + 1;
    _bufferMaxRow = _bufferMinRow + _rows.length;
    if (conn.typeCache.hasPartialTypes) {
      await conn.typeCache.populatePartialTypes();
    }
    await _readLobsBack();
  }

  /// Moves the position of a scrollable cursor; the next fetch returns the
  /// row at the new position. [mode] is `relative` (to the current row),
  /// `absolute`, `first` or `last`.
  Future<void> scroll(int value, String mode) async {
    if (!scrollable) throw dpyError(ERR_SCROLL_NOT_SUPPORTED);
    var desiredRow = 0;
    int orientation;
    switch (mode) {
      case 'relative':
        if (rowCount + value < 1) {
          throw dpyError(ERR_SCROLL_OUT_OF_RESULT_SET);
        }
        orientation = TNS_FETCH_ORIENTATION_RELATIVE;
        desiredRow = rowCount + value;
      case 'absolute':
        orientation = TNS_FETCH_ORIENTATION_ABSOLUTE;
        desiredRow = value;
      case 'first':
        orientation = TNS_FETCH_ORIENTATION_FIRST;
        desiredRow = 1;
      case 'last':
        orientation = TNS_FETCH_ORIENTATION_LAST;
      default:
        throw dpyError(ERR_WRONG_SCROLL_MODE);
    }
    // the server is not needed if the row is already in the buffer (it is
    // always contacted for "last")
    if (orientation != TNS_FETCH_ORIENTATION_LAST &&
        desiredRow >= _bufferMinRow &&
        desiredRow < _bufferMaxRow) {
      _rowIndex = desiredRow - _bufferMinRow;
      rowCount = desiredRow - 1;
      return;
    }
    final message = ExecuteMessage(this)
      ..scrollOperation = true
      ..fetchOrientation = orientation
      ..fetchPos = desiredRow;
    await conn.protocol.processSingleMessage(message);
    final buffered = _rows.length;
    if (buffered == 0) {
      if (orientation != TNS_FETCH_ORIENTATION_FIRST &&
          orientation != TNS_FETCH_ORIENTATION_LAST) {
        throw dpyError(ERR_SCROLL_OUT_OF_RESULT_SET);
      }
      rowCount = 0;
      moreRowsToFetch = false;
      _bufferMinRow = _bufferMaxRow = 0;
    } else {
      rowCount = message.errorInfo.rowcount - buffered;
      _bufferMinRow = rowCount + 1;
      _bufferMaxRow = _bufferMinRow + buffered;
    }
    _rowIndex = 0;
  }

  Future<void> executeMany(int numExecs,
      {bool batchErrors = false, bool arrayDmlRowCounts = false}) async {
    final stmt = statement!;
    if (!stmt.isDml && (batchErrors || arrayDmlRowCounts)) {
      throw dpyError(ERR_EXECUTE_MODE_ONLY_FOR_DML);
    }
    _checkReparse();
    final message = ExecuteMessage(this)
      ..numExecs = numExecs
      ..batchErrors = batchErrors
      ..arrayDmlRowCounts = arrayDmlRowCounts;
    // a PL/SQL block executed for the first time requires a single execute
    // so the bind directions can be determined
    var remaining = numExecs;
    if (stmt.requiresSingleExecute) {
      message.numExecs = 1;
      while (remaining > 0) {
        remaining--;
        await conn.protocol.processSingleMessage(message);
        message.offset++;
        if (stmt.cursorId != 0) break;
      }
    }
    if (remaining > 0) {
      message.numExecs = remaining;
      await conn.protocol.processSingleMessage(message);
    }
    warning = message.warning;
  }

  Future<void> parse() async {
    final message = ExecuteMessage(this)..parseOnly = true;
    await conn.protocol.processSingleMessage(message);
  }

  Future<void> _fetchRows() async {
    final MessageWithData message = statement!.sql == null || scrollable
        ? _executeMessage()
        : FetchMessage(this);
    await conn.protocol.processSingleMessage(message);
    _bufferMinRow = rowCount + 1;
    _bufferMaxRow = _bufferMinRow + _rows.length;
  }

  /// Returns the next row, or null when all rows have been fetched.
  Future<List<Object?>?> fetchOne() async {
    if (_rowIndex >= _rows.length) {
      if (!moreRowsToFetch) return null;
      await _fetchRows();
      if (_rowIndex >= _rows.length) return null;
    }
    rowCount++;
    return _rows[_rowIndex++];
  }

  /// Returns up to [numRows] rows.
  Future<List<List<Object?>>> fetchMany(int numRows) async {
    final out = <List<Object?>>[];
    while (out.length < numRows) {
      if (_rowIndex >= _rows.length) {
        if (!moreRowsToFetch) break;
        await _fetchRows();
        if (_rowIndex >= _rows.length) break;
      }
      final take = _rows.length - _rowIndex < numRows - out.length
          ? _rows.length - _rowIndex
          : numRows - out.length;
      out.addAll(_rows.getRange(_rowIndex, _rowIndex + take));
      _rowIndex += take;
      rowCount += take;
    }
    return out;
  }

  /// Returns all of the remaining rows.
  Future<List<List<Object?>>> fetchAll() async {
    final out = <List<Object?>>[];
    while (true) {
      if (_rowIndex < _rows.length) {
        final take = _rows.length - _rowIndex;
        out.addAll(
            _rowIndex == 0 ? _rows : _rows.getRange(_rowIndex, _rows.length));
        _rowIndex += take;
        rowCount += take;
      }
      if (!moreRowsToFetch) break;
      await _fetchRows();
    }
    return out;
  }

  /// Takes the rows currently buffered (used for streaming).
  List<List<Object?>> takeBufferedRows() {
    if (_rowIndex == 0) {
      final rows = _rows;
      rowCount += rows.length;
      _rows = [];
      return rows;
    }
    final rows = _rows.sublist(_rowIndex);
    rowCount += rows.length;
    clearRows();
    return rows;
  }

  Future<bool> fetchNextBatch() async {
    if (!moreRowsToFetch) return false;
    await _fetchRows();
    return true;
  }

  void close() {
    final stmt = statement;
    if (stmt != null) {
      conn.returnStatement(stmt);
      statement = null;
    }
    _bindVarsByPos = [];
    _bindVarsByName.clear();
    clearRows();
  }
}
