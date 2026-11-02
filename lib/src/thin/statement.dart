import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import 'buffer.dart';
import 'constants.dart';
import 'types.dart';
import 'variable.dart';

/// Information about a bind placeholder found in a statement.
class BindInfo {
  BindInfo(this.name, this.isReturnBind);

  final String name;
  final bool isReturnBind;
  int oraTypeNum = 0;
  int csfrm = 0;
  int bufferSize = 0;
  int size = 0;
  int precision = 0;
  int scale = 0;
  bool isArray = false;
  int numElements = 0;
  int bindDir = TNS_BIND_DIR_INPUT;
  BindVar? variable;

  BindInfo copy() => BindInfo(name, isReturnBind);
}

/// A prepared statement; the cursor id identifies the cursor opened on the
/// server for it, which allows it to be re-executed without parsing again.
class Statement {
  Statement._();

  factory Statement.prepare(String sql) {
    final stmt = Statement._()
      ..sql = sql
      ..sqlBytes = utf8.encode(sql);
    _StatementParser(stmt).parse();
    return stmt;
  }

  String? sql;
  Uint8List? sqlBytes;
  int cursorId = 0;
  bool isQuery = false;
  bool isPlsql = false;
  bool isDml = false;
  bool isDdl = false;
  bool isReturning = false;
  List<BindInfo> bindInfoList = [];
  LinkedHashMap<String, List<BindInfo>> bindInfoDict =
      LinkedHashMap<String, List<BindInfo>>();
  List<ColumnMetadata>? fetchMetadata;
  List<BindVar>? fetchVars;
  int numColumns = 0;
  bool executed = false;
  bool bindsChanged = false;
  bool noPrefetch = false;
  bool requiresDefine = false;
  bool requiresReparse = false;
  bool returnToCache = false;
  bool isNested = false;
  bool inUse = false;

  int get sqlLength => sqlBytes?.length ?? 0;

  Statement copy() {
    final copied = Statement._()
      ..sql = sql
      ..sqlBytes = sqlBytes
      ..isQuery = isQuery
      ..isPlsql = isPlsql
      ..isDml = isDml
      ..isDdl = isDdl
      ..isReturning = isReturning;
    copied.bindInfoList = [for (final b in bindInfoList) b.copy()];
    for (final info in copied.bindInfoList) {
      copied.bindInfoDict.putIfAbsent(info.name, () => []).add(info);
    }
    return copied;
  }

  void _addBind(String name) {
    if (isPlsql && bindInfoDict.containsKey(name)) return;
    final info = BindInfo(name, isReturning);
    bindInfoList.add(info);
    final existing = bindInfoDict[name];
    if (existing != null) {
      if (isReturning && !existing.last.isReturnBind) {
        throw dpyError(ERR_DML_RETURNING_DUP_BINDS, args: {'name': name});
      }
      existing.add(info);
    } else {
      bindInfoDict[name] = [info];
    }
  }

  void _determineStatementType(String keyword) {
    switch (keyword) {
      case 'DECLARE':
      case 'BEGIN':
      case 'CALL':
        isPlsql = true;
      case 'SELECT':
      case 'WITH':
        isQuery = true;
      case 'INSERT':
      case 'UPDATE':
      case 'DELETE':
      case 'MERGE':
        isDml = true;
      case 'CREATE':
      case 'ALTER':
      case 'DROP':
      case 'GRANT':
      case 'REVOKE':
      case 'ANALYZE':
      case 'AUDIT':
      case 'COMMENT':
      case 'TRUNCATE':
        isDdl = true;
    }
  }

  /// Associates the variable with the bind; if the bind metadata changed, a
  /// full execute is required.
  void setVar(BindInfo info, BindVar variable) {
    final m = variable.metadata;
    if (m.dbType.oraTypeNum == ORA_TYPE_NUM_CURSOR) bindsChanged = true;
    if (m.dbType.oraTypeNum != info.oraTypeNum ||
        m.maxSize != info.size ||
        m.bufferSize != info.bufferSize ||
        m.precision != info.precision ||
        m.scale != info.scale ||
        variable.isArray != info.isArray ||
        variable.numElements != info.numElements ||
        m.dbType.csfrm != info.csfrm) {
      // a change of the type of a bind of a query that has already been
      // parsed requires a new parse, as the server would otherwise convert
      // values to the types determined by the original parse
      if (isQuery &&
          cursorId != 0 &&
          info.oraTypeNum != 0 &&
          (info.oraTypeNum != m.dbType.oraTypeNum ||
              info.csfrm != m.dbType.csfrm)) {
        requiresReparse = true;
      }
      info
        ..oraTypeNum = m.dbType.oraTypeNum
        ..csfrm = m.dbType.csfrm
        ..isArray = variable.isArray
        ..numElements = variable.numElements
        ..size = m.maxSize
        ..bufferSize = m.bufferSize
        ..precision = m.precision
        ..scale = m.scale;
      bindsChanged = true;
    }
    info.variable = variable;
  }

  void clearAllState() {
    fetchVars = null;
    fetchMetadata = null;
    executed = false;
    bindsChanged = false;
    requiresDefine = false;
    noPrefetch = false;
    cursorId = 0;
  }

  bool get requiresSingleExecute => isPlsql && (cursorId == 0 || bindsChanged);
}

bool _isSpace(int c) =>
    c == 32 || (c >= 9 && c <= 13) || c == 0xa0 || c == 0x2028 || c == 0x2029;
bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isAlpha(int c) =>
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122) ||
    (c >= 0xc0 && c != 0xd7 && c != 0xf7 && !_isSpace(c));
bool _isAlnum(int c) => _isAlpha(c) || _isDigit(c);
bool _isLineBreak(int c) =>
    c == 10 || c == 13 || c == 11 || c == 12 || c == 0x85 || c == 0x2028;

/// Scans SQL to determine the statement type and the bind variable names.
class _StatementParser {
  _StatementParser(this.stmt)
      : sql = stmt.sql!,
        numChars = stmt.sql!.length;

  final Statement stmt;
  final String sql;
  final int numChars;
  int pos = 0;
  int tempPos = 0;
  bool returningKeywordFound = false;

  int get _ch => sql.codeUnitAt(tempPos);

  void _parseQuotedString(int quote) {
    while (tempPos < numChars) {
      final ch = _ch;
      tempPos++;
      if (ch == quote) {
        pos = tempPos;
        return;
      }
    }
    throw dpyError(quote == 39
        ? ERR_MISSING_ENDING_SINGLE_QUOTE
        : ERR_MISSING_ENDING_DOUBLE_QUOTE);
  }

  void _parseBindName() {
    var quotedName = false, inBind = false, digitsOnly = false;
    var startPos = 0;
    tempPos = pos + 1;
    while (tempPos < numChars) {
      final ch = _ch;
      if (!inBind) {
        if (_isSpace(ch)) {
          tempPos++;
          continue;
        } else if (ch == 34) {
          quotedName = true;
        } else if (_isDigit(ch)) {
          digitsOnly = true;
        } else if (!_isAlpha(ch)) {
          break;
        }
        inBind = true;
        startPos = tempPos;
      } else if (digitsOnly && !_isDigit(ch)) {
        pos = tempPos - 1;
        break;
      } else if (quotedName && ch == 34) {
        pos = tempPos;
        break;
      } else if (!digitsOnly &&
          !quotedName &&
          !_isAlnum(ch) &&
          ch != 95 &&
          ch != 36 &&
          ch != 35) {
        pos = tempPos - 1;
        break;
      }
      tempPos++;
    }
    if (inBind) {
      String name;
      if (quotedName) {
        name = sql.substring(startPos + 1, tempPos);
      } else if (digitsOnly) {
        name = sql.substring(startPos, tempPos);
      } else {
        name = sql.substring(startPos, tempPos).toUpperCase();
      }
      stmt._addBind(name);
    }
  }

  void _parseMultipleLineComment() {
    var inComment = false, exitingComment = false;
    tempPos = pos + 1;
    while (tempPos < numChars) {
      final ch = _ch;
      if (!inComment) {
        if (ch != 42) break;
        inComment = true;
      } else if (ch == 42) {
        exitingComment = true;
      } else if (exitingComment) {
        if (ch == 47) {
          pos = tempPos;
          break;
        }
        exitingComment = false;
      }
      tempPos++;
    }
  }

  void _parseQString() {
    var exitingQString = false, inQString = false;
    var sep = 0;
    tempPos++;
    while (tempPos < numChars) {
      final ch = _ch;
      if (!inQString) {
        sep = switch (ch) { 91 => 93, 123 => 125, 60 => 62, 40 => 41, _ => ch };
        inQString = true;
      } else if (!exitingQString && ch == sep) {
        exitingQString = true;
      } else if (exitingQString) {
        if (ch == 39) {
          pos = tempPos;
          return;
        } else if (ch != sep) {
          exitingQString = false;
        }
      }
      tempPos++;
    }
    throw dpyError(ERR_MISSING_ENDING_SINGLE_QUOTE);
  }

  void _parseSingleLineComment() {
    var inComment = false;
    tempPos = pos + 1;
    while (tempPos < numChars) {
      final ch = _ch;
      if (!inComment) {
        if (ch != 45) return;
        inComment = true;
      } else if (_isLineBreak(ch)) {
        break;
      }
      tempPos++;
    }
    pos = tempPos;
  }

  void parse() {
    var initialKeywordFound = false, lastWasString = false;
    var lastCh = 0, alphaStartCh = 0, alphaStartPos = 0;
    var lastWasAlpha = false;
    while (pos < numChars) {
      tempPos = pos;
      final ch = _ch;
      final isAlpha = _isAlpha(ch);
      if (isAlpha && !lastWasAlpha) {
        alphaStartPos = pos;
        alphaStartCh = ch;
      } else if (!isAlpha && lastWasAlpha) {
        final alphaLen = pos - alphaStartPos;
        if (!initialKeywordFound) {
          stmt._determineStatementType(
              sql.substring(alphaStartPos, pos).toUpperCase());
          if (stmt.isDdl) break;
          initialKeywordFound = true;
        } else if (stmt.isDml &&
            !returningKeywordFound &&
            alphaLen == 9 &&
            (alphaStartCh == 114 || alphaStartCh == 82)) {
          if (sql.substring(alphaStartPos, pos).toUpperCase() == 'RETURNING') {
            returningKeywordFound = true;
          }
        } else if (returningKeywordFound &&
            alphaLen == 4 &&
            (alphaStartCh == 105 || alphaStartCh == 73)) {
          if (sql.substring(alphaStartPos, pos).toUpperCase() == 'INTO') {
            stmt.isReturning = true;
          }
        }
      }
      if (ch == 39) {
        lastWasString = true;
        if (lastCh == 113 || lastCh == 81) {
          _parseQString();
        } else {
          tempPos++;
          _parseQuotedString(ch);
          pos--;
        }
      } else if (!_isSpace(ch)) {
        if (ch == 45) {
          _parseSingleLineComment();
        } else if (ch == 47) {
          _parseMultipleLineComment();
        } else if (ch == 34) {
          tempPos++;
          _parseQuotedString(ch);
          pos--;
        } else if (ch == 58 && !lastWasString) {
          _parseBindName();
        }
        lastWasString = false;
      }
      pos++;
      lastWasAlpha = isAlpha;
      lastCh = ch;
    }
    // a statement consisting only of a keyword (e.g. "commit") ends without
    // a trailing non-alphabetic character
    if (!initialKeywordFound && lastWasAlpha) {
      stmt._determineStatementType(
          sql.substring(alphaStartPos, numChars).toUpperCase());
    }
  }
}

/// LRU cache of statements; cursors of statements evicted from the cache are
/// closed on the next round trip (piggybacked on the next request).
class StatementCache {
  StatementCache(int maxSize, int maxCursors) {
    if (maxCursors == 0) {
      _maxSize = 0;
      _maxCursors = 1;
    } else {
      _maxSize = maxSize;
      _maxCursors = maxCursors;
    }
    _cursorsToClose = Uint32List(_maxCursors);
  }

  late int _maxSize;
  late int _maxCursors;
  final LinkedHashMap<String, Statement> _cached =
      LinkedHashMap<String, Statement>();
  final Set<Statement> _openCursors = <Statement>{};
  late Uint32List _cursorsToClose;
  int numCursorsToClose = 0;

  int get maxSize => _maxSize;

  void _queueCursorToClose(int cursorId) {
    if (numCursorsToClose >= _cursorsToClose.length) {
      final grown = Uint32List(_cursorsToClose.length * 2)
        ..setRange(0, numCursorsToClose, _cursorsToClose);
      _cursorsToClose = grown;
    }
    _cursorsToClose[numCursorsToClose++] = cursorId;
  }

  void _addCursorToClose(Statement stmt) {
    if (stmt.cursorId != 0 && !stmt.isNested) {
      _queueCursorToClose(stmt.cursorId);
    }
    _openCursors.remove(stmt);
  }

  void _adjustCache() {
    while (_cached.length > _maxSize) {
      final key = _cached.keys.first;
      final stmt = _cached.remove(key)!;
      if (stmt.inUse) {
        stmt.returnToCache = false;
      } else {
        _addCursorToClose(stmt);
      }
    }
  }

  void clearCursor(Statement stmt) {
    _queueCursorToClose(stmt.cursorId);
    stmt.cursorId = 0;
    stmt.fetchVars = null;
    stmt.executed = false;
  }

  void clearOpenCursors() {
    final newOpen = <Statement>{};
    for (final stmt in _openCursors) {
      stmt.clearAllState();
      if (stmt.inUse || stmt.returnToCache) newOpen.add(stmt);
    }
    _openCursors
      ..clear()
      ..addAll(newOpen);
    numCursorsToClose = 0;
  }

  Statement getStatement(String? sql, bool cacheStatement) {
    Statement? stmt;
    if (sql != null) stmt = _cached[sql];
    if (stmt == null) {
      stmt = sql != null ? Statement.prepare(sql) : Statement._();
      if (cacheStatement && !stmt.isDdl && _maxSize > 0 && sql != null) {
        stmt.returnToCache = true;
        _cached[sql] = stmt;
        _adjustCache();
      }
      _openCursors.add(stmt);
    } else if (stmt.inUse) {
      if (!cacheStatement) {
        _addCursorToClose(stmt);
        _cached.remove(sql);
      }
      stmt = stmt.copy();
      _openCursors.add(stmt);
    } else if (!cacheStatement) {
      _cached.remove(sql);
      stmt.returnToCache = false;
    } else {
      // move to the end (most recently used)
      _cached.remove(sql);
      _cached[sql!] = stmt;
    }
    stmt.inUse = true;
    return stmt;
  }

  void returnStatement(Statement stmt) {
    for (final info in stmt.bindInfoList) {
      info.variable = null;
    }
    if (stmt.returnToCache) {
      stmt.inUse = false;
    } else {
      _addCursorToClose(stmt);
    }
  }

  void resize(int newSize) {
    _maxSize = newSize;
    _adjustCache();
  }

  void writeCursorsToClose(WriteBuffer buf) {
    buf.writeUB4(numCursorsToClose);
    for (var i = 0; i < numCursorsToClose; i++) {
      buf.writeUB4(_cursorsToClose[i]);
    }
    numCursorsToClose = 0;
  }
}
