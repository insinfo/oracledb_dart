import 'dart:convert';
import 'dart:typed_data';

import '../../dbobject.dart';
import '../../exceptions.dart';
import '../../lob.dart';
import '../buffer.dart';
import '../codecs.dart';
import '../constants.dart';
import '../oson.dart';
import '../vector.dart';
import '../cursor_impl.dart';
import '../statement.dart';
import '../types.dart';
import '../variable.dart';
import 'base.dart';
import 'lob_op.dart';

const Utf8Decoder _utf8Decoder = Utf8Decoder(allowMalformed: true);

/// Base class for messages that send or receive data (execute and fetch).
abstract class MessageWithData extends Message {
  MessageWithData(this.cursor) : super(cursor.conn);

  final ThinCursorImpl cursor;
  Uint8List? _bitVector;
  bool arrayDmlRowCounts = false;
  bool batchErrors = false;
  int rowIndex = 0;
  int numExecs = 1;
  int numColumnsSent = 0;
  List<BindVar?>? outVars;
  bool inFetch = false;
  bool parseOnly = false;
  int offset = 0;

  Statement get statement => cursor.statement!;

  void _adjustMetadata(BindVar prevVar, ColumnMetadata metadata) {
    final typeNum = metadata.dbType.oraTypeNum;
    final prevTypeNum = prevVar.fetchMetadata!.dbType.oraTypeNum;
    if (typeNum == ORA_TYPE_NUM_CLOB &&
        (prevTypeNum == ORA_TYPE_NUM_CHAR ||
            prevTypeNum == ORA_TYPE_NUM_LONG ||
            prevTypeNum == ORA_TYPE_NUM_VARCHAR)) {
      metadata.dbType = DbType.fromOraTypeAndCsfrm(
          ORA_TYPE_NUM_LONG, prevVar.fetchMetadata!.dbType.csfrm);
    } else if (typeNum == ORA_TYPE_NUM_BLOB &&
        (prevTypeNum == ORA_TYPE_NUM_RAW ||
            prevTypeNum == ORA_TYPE_NUM_LONG_RAW)) {
      metadata.dbType = DbType.longRaw;
    }
  }

  void _getBitVector(ReadBuffer buf, int numBytes) {
    final bytes = buf.readRawBytes(numBytes);
    final bv = _bitVector;
    if (bv != null && bv.length == numBytes) {
      bv.setRange(0, numBytes, bytes);
    } else {
      _bitVector = Uint8List.fromList(bytes);
    }
  }

  @pragma('vm:prefer-inline')
  bool _isDuplicateData(int columnNum) {
    final bv = _bitVector;
    if (bv == null) return false;
    return bv[columnNum >> 3] & (1 << (columnNum & 7)) == 0;
  }

  void _writeBindParams(WriteBuffer buf, List<BindInfo> params) {
    var hasData = false;
    final vars = <BindVar>[];
    for (final info in params) {
      if (!info.isReturnBind) hasData = true;
      vars.add(info.variable!);
    }
    writeColumnMetadata(buf, vars);
    if (hasData) {
      for (var i = 0; i < numExecs; i++) {
        buf.writeUint8(TNS_MSG_TYPE_ROW_DATA);
        _writeBindParamsRow(buf, params, i);
      }
    }
  }

  void preprocessQuery() {
    inFetch = true;
    cursor.moreRowsToFetch = true;
    cursor.clearRows();
    rowIndex = 0;
    if (statement.fetchVars == null) return;
    outVars = cursor.fetchVars;
  }

  void _processBitVector(ReadBuffer buf) {
    numColumnsSent = buf.readUB2();
    var numBytes = cursor.numColumns ~/ 8;
    if (cursor.numColumns % 8 > 0) numBytes++;
    _getBitVector(buf, numBytes);
  }

  /// Decodes the value of a column (fetch) or of an out bind variable.
  Object? _processColumnData(ReadBuffer buf, BindVar variable, int pos) {
    final metadata = inFetch ? variable.fetchMetadata! : variable.metadata;
    final dbType = metadata.dbType;
    final oraTypeNum = dbType.oraTypeNum;
    Object? value;
    if (metadata.bufferSize == 0 &&
        inFetch &&
        oraTypeNum != ORA_TYPE_NUM_LONG &&
        oraTypeNum != ORA_TYPE_NUM_LONG_RAW &&
        oraTypeNum != ORA_TYPE_NUM_UROWID) {
      value = null; // column is null by describe
    } else {
      switch (oraTypeNum) {
        case ORA_TYPE_NUM_VARCHAR:
        case ORA_TYPE_NUM_CHAR:
        case ORA_TYPE_NUM_LONG:
          final n = buf.readBytesRef();
          if (n >= 0) {
            value = dbType.csfrm == CS_FORM_NCHAR
                ? decodeUtf16(buf.refData, buf.refOffset, n)
                : _utf8Decoder.convert(
                    buf.refData, buf.refOffset, buf.refOffset + n);
          }
        case ORA_TYPE_NUM_NUMBER:
        case ORA_TYPE_NUM_BINARY_INTEGER:
          final n = buf.readBytesRef();
          if (n >= 0) {
            value = variable.numberAsString
                ? decodeNumberAsString(buf.refData, buf.refOffset, n)
                : decodeNumber(
                    buf.refData, buf.refOffset, n, variable.numberAsDouble);
          }
        case ORA_TYPE_NUM_RAW:
        case ORA_TYPE_NUM_LONG_RAW:
          final n = buf.readBytesRef();
          if (n >= 0) {
            value = Uint8List.fromList(Uint8List.sublistView(
                buf.refData, buf.refOffset, buf.refOffset + n));
          }
        case ORA_TYPE_NUM_DATE:
        case ORA_TYPE_NUM_TIMESTAMP:
        case ORA_TYPE_NUM_TIMESTAMP_LTZ:
        case ORA_TYPE_NUM_TIMESTAMP_TZ:
          final n = buf.readBytesRef();
          if (n >= 0) value = decodeDate(buf.refData, buf.refOffset, n);
        case ORA_TYPE_NUM_BINARY_DOUBLE:
          final n = buf.readBytesRef();
          if (n >= 0) value = decodeBinaryDouble(buf.refData, buf.refOffset);
        case ORA_TYPE_NUM_BINARY_FLOAT:
          final n = buf.readBytesRef();
          if (n >= 0) value = decodeBinaryFloat(buf.refData, buf.refOffset);
        case ORA_TYPE_NUM_BOOLEAN:
          final n = buf.readBytesRef();
          if (n >= 0) value = buf.refData[buf.refOffset + n - 1] == 1;
        case ORA_TYPE_NUM_INTERVAL_DS:
          final n = buf.readBytesRef();
          if (n >= 0) value = decodeIntervalDS(buf.refData, buf.refOffset);
        case ORA_TYPE_NUM_INTERVAL_YM:
          final n = buf.readBytesRef();
          if (n >= 0) value = decodeIntervalYM(buf.refData, buf.refOffset);
        case ORA_TYPE_NUM_ROWID:
          if (!inFetch) {
            value = buf.readStr();
          } else {
            final n = buf.readUB1();
            if (n != 0 && n != TNS_NULL_LENGTH_INDICATOR) {
              final rba = buf.readUB4();
              final partitionId = buf.readUB2();
              buf.skipUB1();
              final blockNum = buf.readUB4();
              final slotNum = buf.readUB2();
              value = encodeRowid(rba, partitionId, blockNum, slotNum);
            }
          }
        case ORA_TYPE_NUM_UROWID:
          if (!inFetch) {
            value = buf.readStr();
          } else if (buf.readBytesRef() >= 0) {
            final n = buf.readBytesRef();
            if (n >= 0) value = decodeUrowid(buf.refData, buf.refOffset, n);
          }
        case ORA_TYPE_NUM_CLOB:
        case ORA_TYPE_NUM_BLOB:
        case ORA_TYPE_NUM_BFILE:
          if (buf.readUB4() > 0) {
            var size = 0, chunkSize = 0;
            final isFile = oraTypeNum == ORA_TYPE_NUM_BFILE;
            if (!isFile) {
              size = buf.readUB8();
              chunkSize = buf.readUB4();
            }
            final locator = buf.readBytes()!;
            value = OracleLob.fromLocator(
                conn,
                dbType,
                LobLocator(oraTypeNum, dbType.csfrm, locator,
                    size: size, chunkSize: chunkSize, hasMetadata: !isFile));
          }
        case ORA_TYPE_NUM_JSON:
        case ORA_TYPE_NUM_VECTOR:
          // sent as a LOB with all of its data prefetched
          if (buf.readUB4() > 0) {
            buf.skipUB8(); // size
            buf.skipUB4(); // chunk size
            final data = buf.readBytes();
            buf.readBytesRef(); // locator (unused)
            if (data != null && data.isNotEmpty) {
              value = oraTypeNum == ORA_TYPE_NUM_JSON
                  ? decodeOson(data)
                  : decodeVector(data);
            }
          }
        case ORA_TYPE_NUM_OBJECT:
          value = readDbObject(buf, metadata.objectType);
        case ORA_TYPE_NUM_CURSOR:
          buf.skipUB1(); // length (fixed value)
          final child = ThinCursorImpl(conn);
          child.statement = conn.statementCache.getStatement(null, false);
          child.moreRowsToFetch = true;
          child.statement!.isQuery = true;
          _processDescribeInfo(buf, child);
          child.statement!.cursorId = buf.readUB2();
          if (inFetch) child.statement!.isNested = true;
          value = child;
        default:
          throw dpyError(ERR_DB_TYPE_NOT_SUPPORTED,
              args: {'name': dbType.name});
      }
    }
    if (value != null && variable.jsonDecode) {
      value =
          value is Uint8List ? decodeOson(value) : jsonDecode(value as String);
    }
    if (!inFetch) {
      final actualNumBytes = buf.readSB4();
      if (actualNumBytes < 0 && oraTypeNum == ORA_TYPE_NUM_BOOLEAN) {
        value = null;
      } else if (actualNumBytes != 0 && value != null) {
        throw dpyError(ERR_COLUMN_TRUNCATED, args: {
          'col_value_len': value is String ? value.length : -1,
          'unit': value is Uint8List ? 'bytes' : 'characters',
          'actual_len': actualNumBytes,
        });
      }
    } else if (oraTypeNum == ORA_TYPE_NUM_LONG ||
        oraTypeNum == ORA_TYPE_NUM_LONG_RAW) {
      buf.skipSB4(); // null indicator
      buf.skipUB4(); // return code
    }
    return value;
  }

  void _processDescribeInfo(ReadBuffer buf, ThinCursorImpl cursor) {
    final stmt = cursor.statement!;
    buf.skipUB4(); // max row size
    final numColumns = buf.readUB4();
    final prevFetchVars = stmt.fetchVars;
    final metadataList = <ColumnMetadata>[];
    final fetchVars = <BindVar>[];
    if (numColumns > 0) buf.skipUB1();
    for (var i = 0; i < numColumns; i++) {
      final metadata = processMetadata(buf);
      if (prevFetchVars != null && i < prevFetchVars.length) {
        _adjustMetadata(prevFetchVars[i], metadata);
      }
      final typeNum = metadata.dbType.oraTypeNum;
      if (typeNum == ORA_TYPE_NUM_BLOB ||
          typeNum == ORA_TYPE_NUM_CLOB ||
          typeNum == ORA_TYPE_NUM_JSON ||
          typeNum == ORA_TYPE_NUM_VECTOR) {
        stmt.requiresDefine = true;
        stmt.noPrefetch = true;
      }
      metadataList.add(metadata);
      fetchVars.add(cursor.createFetchVar(metadata));
    }
    if (buf.readUB4() > 0) buf.skipRawBytesChunked(); // current date
    buf.skipUB4(); // dcbflag
    buf.skipUB4(); // dcbmdbz
    buf.skipUB4(); // dcbmnpr
    buf.skipUB4(); // dcbmxpr
    if (buf.readUB4() > 0) buf.skipRawBytesChunked(); // dcbqcky
    cursor.numColumns = numColumns;
    cursor.fetchMetadata = metadataList;
    cursor.fetchVars = fetchVars;
    stmt.fetchMetadata = metadataList;
    stmt.fetchVars = fetchVars;
    stmt.numColumns = numColumns;
  }

  @override
  void processErrorInfo(ReadBuffer buf) {
    super.processErrorInfo(buf);
    final stmt = statement;
    if (errorInfo.cursorId != 0) stmt.cursorId = errorInfo.cursorId;
    if (!stmt.isPlsql && !inFetch) {
      cursor.rowCount = errorInfo.rowcount;
    } else if (inFetch && rowIndex > 0) {
      stmt.requiresDefine = false;
    }
    cursor.lastRowid = errorInfo.rowid;
    cursor.batchErrors = errorInfo.batchErrors;
    if (batchErrors && cursor.batchErrors == null) cursor.batchErrors = [];
    if (errorInfo.num == TNS_ERR_NO_DATA_FOUND && inFetch) {
      errorInfo.num = 0;
      cursor.moreRowsToFetch = false;
      stmt.requiresDefine = false;
      errorOccurred = false;
    } else if (errorInfo.num == TNS_ERR_ARRAY_DML_ERRORS) {
      errorInfo.num = 0;
      errorOccurred = false;
    } else if (retry) {
      retry = false;
    } else if (stmt.isQuery &&
        (errorInfo.num == TNS_ERR_VAR_NOT_IN_SELECT_LIST ||
            errorInfo.num == TNS_ERR_INCONSISTENT_DATA_TYPES)) {
      retry = true;
      conn.statementCache.clearCursor(stmt);
    } else if (errorInfo.num != 0 && errorInfo.cursorId != 0) {
      if (!integrityErrorCodes.contains(errorInfo.num)) {
        conn.statementCache.clearCursor(stmt);
      }
    }
  }

  void _processImplicitResult(ReadBuffer buf) {
    final results = cursor.implicitResults = <ThinCursorImpl>[];
    final numResults = buf.readUB4();
    for (var i = 0; i < numResults; i++) {
      final numBytes = buf.readUB1();
      buf.skipRawBytes(numBytes);
      final child = ThinCursorImpl(conn);
      child.statement = conn.statementCache.getStatement(null, false);
      child.moreRowsToFetch = true;
      child.statement!.isQuery = true;
      _processDescribeInfo(buf, child);
      child.statement!.cursorId = buf.readUB2();
      results.add(child);
    }
  }

  void _processIoVector(ReadBuffer buf) {
    buf.skipUB1(); // flag
    final temp16 = buf.readUB2(); // num requests
    final temp32 = buf.readUB4(); // num iters
    final numBinds = temp32 * 256 + temp16;
    buf.skipUB4(); // num iters this time
    buf.skipUB2(); // uac buffer length
    var numBytes = buf.readUB2(); // bit vector for fast fetch
    if (numBytes > 0) buf.skipRawBytes(numBytes);
    numBytes = buf.readUB2(); // rowid
    if (numBytes > 0) buf.skipRawBytes(numBytes);
    final vars = outVars = <BindVar?>[];
    for (var i = 0; i < numBinds; i++) {
      final info = statement.bindInfoList[i];
      info.bindDir = buf.readUB1();
      if (info.bindDir == TNS_BIND_DIR_INPUT) continue;
      vars.add(info.variable);
    }
  }

  @override
  void processMessage(ReadBuffer buf, int messageType) {
    switch (messageType) {
      case TNS_MSG_TYPE_ROW_HEADER:
        _processRowHeader(buf);
      case TNS_MSG_TYPE_ROW_DATA:
        _processRowData(buf);
      case TNS_MSG_TYPE_FLUSH_OUT_BINDS:
        flushOutBinds = true;
        endOfResponse = true;
      case TNS_MSG_TYPE_DESCRIBE_INFO:
        buf.skipRawBytesChunked();
        _processDescribeInfo(buf, cursor);
        outVars = cursor.fetchVars;
      case TNS_MSG_TYPE_ERROR:
        processErrorInfo(buf);
      case TNS_MSG_TYPE_BIT_VECTOR:
        _processBitVector(buf);
      case TNS_MSG_TYPE_IO_VECTOR:
        _processIoVector(buf);
      case TNS_MSG_TYPE_IMPLICIT_RESULTSET:
        _processImplicitResult(buf);
      default:
        super.processMessage(buf, messageType);
    }
  }

  @override
  void processReturnParameters(ReadBuffer buf) {
    var numParams = buf.readUB2(); // al8o4l (ignored)
    for (var i = 0; i < numParams; i++) {
      buf.skipUB4();
    }
    var numBytes = buf.readUB2(); // al8txl (ignored)
    if (numBytes > 0) buf.skipRawBytes(numBytes);
    numParams = buf.readUB2(); // num key/value pairs
    processKeywordValuePairs(buf, numParams);
    numBytes = buf.readUB2(); // registration
    if (numBytes > 0) buf.skipRawBytes(numBytes);
    if (arrayDmlRowCounts) {
      final numRows = buf.readUB4();
      final rowCounts = cursor.dmlRowCounts = <int>[];
      for (var i = 0; i < numRows; i++) {
        rowCounts.add(buf.readUB8());
      }
    }
  }

  void _processRowData(ReadBuffer buf) {
    final vars = outVars!;
    if (inFetch) {
      // fetched rows are built directly in row-major form
      final numColumns = vars.length;
      final row = List<Object?>.filled(numColumns, null);
      final lastRow = cursor.lastRow;
      for (var i = 0; i < numColumns; i++) {
        if (_isDuplicateData(i)) {
          row[i] = lastRow?[i];
        } else {
          row[i] = _processColumnData(buf, vars[i]!, rowIndex);
        }
      }
      cursor.addRow(row);
      rowIndex++;
      _bitVector = null;
      return;
    }
    for (final variable in vars) {
      if (variable == null) continue;
      if (variable.isArray) {
        variable.numElementsInArray = buf.readUB4();
        variable.ensureSize(variable.numElementsInArray);
        for (var pos = 0; pos < variable.numElementsInArray; pos++) {
          variable.values[pos] = _processColumnData(buf, variable, pos);
        }
      } else if (statement.isReturning) {
        final numRows = buf.readUB4();
        final values = List<Object?>.filled(numRows, null);
        for (var j = 0; j < numRows; j++) {
          values[j] = _processColumnData(buf, variable, j);
        }
        variable.ensureSize(rowIndex + 1);
        variable.values[rowIndex] = values;
        variable.hasReturnedData = true;
      } else {
        variable.ensureSize(rowIndex + 1);
        variable.values[rowIndex] = _processColumnData(buf, variable, rowIndex);
      }
    }
    rowIndex++;
  }

  void _processRowHeader(ReadBuffer buf) {
    buf.skipUB1(); // flags
    buf.skipUB2(); // num requests
    buf.skipUB4(); // iteration number
    buf.skipUB4(); // num iters
    buf.skipUB2(); // buffer length
    var numBytes = buf.readUB4();
    if (numBytes > 0) {
      buf.skipUB1(); // skip repeated length
      _getBitVector(buf, numBytes);
    }
    numBytes = buf.readUB4();
    if (numBytes > 0) buf.skipRawBytesChunked(); // rxhrid
  }

  void writeColumnMetadata(WriteBuffer buf, List<BindVar> vars) {
    for (final variable in vars) {
      final metadata = variable.metadata;
      var oraTypeNum = metadata.dbType.oraTypeNum;
      var bufferSize = metadata.bufferSize;
      if (oraTypeNum == ORA_TYPE_NUM_ROWID ||
          oraTypeNum == ORA_TYPE_NUM_UROWID) {
        oraTypeNum = ORA_TYPE_NUM_VARCHAR;
        bufferSize = TNS_MAX_UROWID_LENGTH;
      }
      var flag = TNS_BIND_USE_INDICATORS;
      if (variable.isArray) flag |= TNS_BIND_ARRAY;
      var contFlag = 0;
      var lobPrefetchLength = 0;
      if (oraTypeNum == ORA_TYPE_NUM_BLOB || oraTypeNum == ORA_TYPE_NUM_CLOB) {
        contFlag = TNS_LOB_PREFETCH_FLAG;
      } else if (oraTypeNum == ORA_TYPE_NUM_JSON) {
        contFlag = TNS_LOB_PREFETCH_FLAG;
        bufferSize = lobPrefetchLength = TNS_JSON_MAX_LENGTH;
      } else if (oraTypeNum == ORA_TYPE_NUM_VECTOR) {
        contFlag = TNS_LOB_PREFETCH_FLAG;
        bufferSize = lobPrefetchLength = TNS_VECTOR_MAX_LENGTH;
      }
      buf.writeUint8(oraTypeNum);
      buf.writeUint8(flag);
      // precision and scale are always written as zero as the server
      // expects that and complains if any other value is sent!
      buf.writeUint8(0);
      buf.writeUint8(0);
      buf.writeUB4(bufferSize);
      buf.writeUB4(variable.isArray ? variable.numElements : 0);
      buf.writeUB8(contFlag);
      final objectType = metadata.objectType;
      if (objectType != null) {
        buf.writeUB4(objectType.oid!.length);
        buf.writeBytesWithLength(objectType.oid!);
        buf.writeUB4(objectType.version);
      } else {
        buf.writeUB4(0); // OID
        buf.writeUB2(0); // version
      }
      buf.writeUB2(metadata.dbType.csfrm != 0 ? TNS_CHARSET_UTF8 : 0);
      buf.writeUint8(metadata.dbType.csfrm);
      buf.writeUB4(lobPrefetchLength); // max chars (LOB prefetch)
      if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_12_2) {
        buf.writeUB4(0); // oaccolid
      }
    }
  }

  void _writeBindValue(WriteBuffer buf, BindVar variable, Object? value) {
    final dbType = variable.metadata.dbType;
    final oraTypeNum = dbType.oraTypeNum;
    if (value == null) {
      if (oraTypeNum == ORA_TYPE_NUM_BOOLEAN) {
        buf.writeUint8(TNS_ESCAPE_CHAR);
        buf.writeUint8(1);
      } else if (oraTypeNum == ORA_TYPE_NUM_OBJECT) {
        buf.writeUB4(0); // TOID
        buf.writeUB4(0); // OID
        buf.writeUB4(0); // snapshot
        buf.writeUB2(0); // version
        buf.writeUB4(0); // packed data length
        buf.writeUB4(TNS_OBJ_TOP_LEVEL); // flags
      } else {
        buf.writeUint8(0);
      }
      return;
    }
    switch (oraTypeNum) {
      case ORA_TYPE_NUM_VARCHAR:
      case ORA_TYPE_NUM_CHAR:
      case ORA_TYPE_NUM_LONG:
        final s = value is String ? value : value.toString();
        final bytes =
            dbType.csfrm == CS_FORM_NCHAR ? encodeUtf16(s) : utf8.encode(s);
        buf.writeBytesWithLength(bytes);
      case ORA_TYPE_NUM_RAW:
      case ORA_TYPE_NUM_LONG_RAW:
        if (value is! List<int>) {
          throw dpyError(ERR_UNSUPPORTED_TYPE_SET, args: {
            'type_name': value.runtimeType,
            'db_type_name': dbType.name
          });
        }
        buf.writeBytesWithLength(value);
      case ORA_TYPE_NUM_NUMBER:
      case ORA_TYPE_NUM_BINARY_INTEGER:
        Uint8List bytes;
        if (value is int) {
          bytes = encodeInt(value);
        } else if (value is bool) {
          bytes = encodeInt(value ? 1 : 0);
        } else if (value is double) {
          if (value.isNaN || value.isInfinite) {
            throw dpyError(ERR_ORACLE_NUMBER_NO_REPR);
          }
          bytes = encodeNumber(value.toString());
        } else {
          bytes = encodeNumber(value.toString());
        }
        buf.writeBytesWithLength(bytes);
      case ORA_TYPE_NUM_DATE:
      case ORA_TYPE_NUM_TIMESTAMP:
      case ORA_TYPE_NUM_TIMESTAMP_TZ:
      case ORA_TYPE_NUM_TIMESTAMP_LTZ:
        var length = dbType.bufferSizeFactor;
        final dt = value as DateTime;
        if (length == 11 && dt.millisecond == 0 && dt.microsecond == 0) {
          // the protocol requires that if the fractional seconds are zero
          // that the value be transmitted as a date, not a timestamp!
          length = 7;
        }
        final bytes = encodeDate(dt, dbType.bufferSizeFactor);
        buf.writeBytesWithLength(bytes, 0, length);
      case ORA_TYPE_NUM_BINARY_DOUBLE:
        buf.writeBytesWithLength(encodeBinaryDouble((value as num).toDouble()));
      case ORA_TYPE_NUM_BINARY_FLOAT:
        buf.writeBytesWithLength(encodeBinaryFloat((value as num).toDouble()));
      case ORA_TYPE_NUM_BOOLEAN:
        final b = value as bool;
        buf.writeBytesWithLength(b ? const [2, 1, 1] : const [1, 0]);
      case ORA_TYPE_NUM_INTERVAL_DS:
        buf.writeBytesWithLength(encodeIntervalDS(value as Duration));
      case ORA_TYPE_NUM_INTERVAL_YM:
        buf.writeBytesWithLength(encodeIntervalYM(value as IntervalYM));
      case ORA_TYPE_NUM_ROWID:
      case ORA_TYPE_NUM_UROWID:
        buf.writeBytesWithLength(utf8.encode(value as String));
      case ORA_TYPE_NUM_CLOB:
      case ORA_TYPE_NUM_BLOB:
      case ORA_TYPE_NUM_BFILE:
        final locator = (value as OracleLob).locator.locator;
        buf.writeUB4(locator.length);
        buf.writeBytesWithLength(locator);
      case ORA_TYPE_NUM_JSON:
        final data = encodeOson(value, maxFieldNameSize: conn.osonMaxFnameSize);
        buf.writeQLocator(data.length);
        buf.writeBytesWithLength(data);
      case ORA_TYPE_NUM_VECTOR:
        final data = encodeVector(value);
        buf.writeQLocator(data.length);
        buf.writeBytesWithLength(data);
      case ORA_TYPE_NUM_OBJECT:
        writeDbObject(buf, value as OracleDbObject);
      case ORA_TYPE_NUM_CURSOR:
        final child = value as ThinCursorImpl;
        child.statement ??= conn.statementCache.getStatement(null, false);
        if (child.statement!.cursorId == 0) {
          buf.writeUint8(1);
          buf.writeUint8(0);
        } else {
          buf.writeUB4(1);
          buf.writeUB4(child.statement!.cursorId);
        }
      default:
        throw dpyError(ERR_DB_TYPE_NOT_SUPPORTED, args: {'name': dbType.name});
    }
  }

  /// Writes a row of bind values; non-LONG values are written first,
  /// followed by any LONG values.
  void _writeBindParamsRow(WriteBuffer buf, List<BindInfo> params, int pos) {
    var foundLong = false;
    final maxStringSize = buf.caps.maxStringSize;
    for (final info in params) {
      if (info.isReturnBind) continue;
      final variable = info.variable!;
      if (variable.isArray) {
        buf.writeUB4(variable.numElementsInArray);
        for (var i = 0; i < variable.numElementsInArray; i++) {
          _writeBindValue(buf, variable, variable.values[i]);
        }
      } else {
        if (!statement.isPlsql &&
            variable.metadata.bufferSize > maxStringSize) {
          foundLong = true;
          continue;
        }
        _writeBindValue(buf, variable, variable.values[pos + offset]);
      }
    }
    if (foundLong) {
      for (final info in params) {
        if (info.isReturnBind) continue;
        final variable = info.variable!;
        if (variable.metadata.bufferSize <= maxStringSize) continue;
        _writeBindValue(buf, variable, variable.values[pos + offset]);
      }
    }
  }

  @override
  void preprocess() {
    final stmt = statement;
    if (stmt.isReturning && !parseOnly) {
      outVars = [
        for (final info in stmt.bindInfoList)
          if (info.isReturnBind) info.variable
      ];
    } else if (stmt.isQuery) {
      preprocessQuery();
    }
  }
}

/// Executes a statement (parsing, binding, defining and fetching as needed).
class ExecuteMessage extends MessageWithData {
  ExecuteMessage(super.cursor);

  int fetchOrientation = 0;
  int fetchPos = 0;
  bool scrollOperation = false;

  void _writeExecuteMessage(WriteBuffer buf) {
    final stmt = statement;
    final params = stmt.bindInfoList;
    var options = 0, execFlags = 0, numParams = 0, numIters = 1;
    if (!stmt.requiresDefine && !parseOnly) numParams = params.length;
    if (stmt.requiresDefine) {
      options |= TNS_EXEC_OPTION_DEFINE;
    } else if (!parseOnly && stmt.sql != null) {
      execFlags |= TNS_EXEC_FLAGS_IMPLICIT_RESULTSET;
      if (!scrollOperation) options |= TNS_EXEC_OPTION_EXECUTE;
    }
    if (cursor.scrollable && !parseOnly) {
      execFlags |= TNS_EXEC_FLAGS_SCROLLABLE | TNS_EXEC_FLAGS_NO_CANCEL_ON_EOF;
    }
    if (stmt.cursorId == 0 || stmt.isDdl) options |= TNS_EXEC_OPTION_PARSE;
    if (stmt.isQuery) {
      if (parseOnly) {
        options |= TNS_EXEC_OPTION_DESCRIBE;
      } else {
        numIters = stmt.cursorId == 0 || stmt.requiresDefine
            ? cursor.prefetchRows
            : cursor.arraySize;
        cursor.fetchArraySize = numIters;
        if (numIters > 0 && !stmt.noPrefetch) options |= TNS_EXEC_OPTION_FETCH;
      }
    }
    if (!stmt.isPlsql && !parseOnly) {
      options |= TNS_EXEC_OPTION_NOT_PLSQL;
    } else if (stmt.isPlsql && numParams > 0) {
      options |= TNS_EXEC_OPTION_PLSQL_BIND;
    }
    if (numParams > 0 && !scrollOperation) options |= TNS_EXEC_OPTION_BIND;
    if (batchErrors) options |= TNS_EXEC_OPTION_BATCH_ERRORS;
    if (arrayDmlRowCounts) execFlags |= TNS_EXEC_FLAGS_DML_ROWCOUNTS;
    if (conn.autocommit && !parseOnly) options |= TNS_EXEC_OPTION_COMMIT;

    writeFunctionCode(buf);
    buf.writeUB4(options); // execute options
    buf.writeUB4(stmt.cursorId); // cursor id
    if (stmt.cursorId == 0 || stmt.isDdl) {
      buf.writeUint8(1); // pointer (cursor id)
      buf.writeUB4(stmt.sqlLength);
    } else {
      buf.writeUint8(0); // pointer (cursor id)
      buf.writeUB4(0);
    }
    buf.writeUint8(1); // pointer (vector)
    buf.writeUB4(13); // al8i4 array length
    buf.writeUint8(0); // pointer (al8o4)
    buf.writeUint8(0); // pointer (al8o4l)
    buf.writeUB4(0); // prefetch buffer size
    buf.writeUB4(numIters); // prefetch number of rows
    buf.writeUB4(TNS_MAX_LONG_LENGTH); // maximum long size
    if (numParams == 0) {
      buf.writeUint8(0); // pointer (binds)
      buf.writeUB4(0); // number of binds
    } else {
      buf.writeUint8(1); // pointer (binds)
      buf.writeUB4(numParams); // number of binds
    }
    buf.writeUint8(0); // pointer (al8app)
    buf.writeUint8(0); // pointer (al8txn)
    buf.writeUint8(0); // pointer (al8txl)
    buf.writeUint8(0); // pointer (al8kv)
    buf.writeUint8(0); // pointer (al8kvl)
    if (stmt.requiresDefine) {
      buf.writeUint8(1); // pointer (al8doac)
      buf.writeUB4(cursor.fetchVars!.length); // number of defines
    } else {
      buf.writeUint8(0);
      buf.writeUB4(0);
    }
    buf.writeUB4(0); // registration id
    buf.writeUint8(0); // pointer (al8objlist)
    buf.writeUint8(1); // pointer (al8objlen)
    buf.writeUint8(0); // pointer (al8blv)
    buf.writeUB4(0); // al8blvl
    buf.writeUint8(0); // pointer (al8dnam)
    buf.writeUB4(0); // al8dnaml
    buf.writeUB4(0); // al8regid_msb
    if (arrayDmlRowCounts) {
      buf.writeUint8(1); // pointer (al8pidmlrc)
      buf.writeUB4(numExecs); // al8pidmlrcbl
      buf.writeUint8(1); // pointer (al8pidmlrcl)
    } else {
      buf.writeUint8(0); // pointer (al8pidmlrc)
      buf.writeUB4(0); // al8pidmlrcbl
      buf.writeUint8(0); // pointer (al8pidmlrcl)
    }
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_12_2) {
      buf.writeUint8(0); // pointer (al8sqlsig)
      buf.writeUB4(0); // SQL signature length
      buf.writeUint8(0); // pointer (SQL ID)
      buf.writeUB4(0); // allocated size of SQL ID
      buf.writeUint8(0); // pointer (length of SQL ID)
      if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_12_2_EXT1) {
        buf.writeUint8(0); // pointer (chunk ids)
        buf.writeUB4(0); // number of chunk ids
      }
    }
    if (stmt.cursorId == 0 || stmt.isDdl) {
      final sqlBytes = stmt.sqlBytes;
      if (sqlBytes == null) throw dpyError(ERR_INVALID_REF_CURSOR);
      buf.writeBytesWithLength(sqlBytes);
      buf.writeUB4(1); // al8i4[0] parse
    } else {
      buf.writeUB4(0); // al8i4[0] parse
    }
    if (stmt.isQuery) {
      buf.writeUB4(stmt.cursorId == 0 ? 0 : numIters); // al8i4[1]
    } else {
      buf.writeUB4(numExecs); // al8i4[1] execution count
    }
    buf.writeUB4(0); // al8i4[2]
    buf.writeUB4(0); // al8i4[3]
    buf.writeUB4(0); // al8i4[4]
    buf.writeUB4(0); // al8i4[5] SCN (part 1)
    buf.writeUB4(0); // al8i4[6] SCN (part 2)
    buf.writeUB4(stmt.isQuery ? 1 : 0); // al8i4[7] is query
    buf.writeUB4(0); // al8i4[8]
    buf.writeUB4(execFlags); // al8i4[9] execute flags
    buf.writeUB4(fetchOrientation); // al8i4[10] fetch orientation
    buf.writeUB4(fetchPos); // al8i4[11] fetch pos
    buf.writeUB4(0); // al8i4[12]
    if (stmt.requiresDefine) {
      writeColumnMetadata(buf, cursor.fetchVars!);
    } else if (numParams > 0) {
      _writeBindParams(buf, params);
    }
  }

  void _writeReexecuteMessage(WriteBuffer buf) {
    final stmt = statement;
    var params = stmt.bindInfoList;
    var options1 = 0, options2 = 0;
    int numIters;
    if (params.isNotEmpty) {
      if (!stmt.isQuery && !stmt.isReturning) {
        outVars = [
          for (final info in params)
            if (info.bindDir != TNS_BIND_DIR_INPUT) info.variable
        ];
      }
      params = [
        for (final info in params)
          if (info.bindDir != TNS_BIND_DIR_OUTPUT && !info.isReturnBind) info
      ];
    }
    if (functionCode == TNS_FUNC_REEXECUTE_AND_FETCH) {
      options1 |= TNS_EXEC_OPTION_EXECUTE;
      numIters = cursor.prefetchRows;
      cursor.fetchArraySize = numIters;
    } else {
      if (conn.autocommit) options2 |= TNS_EXEC_OPTION_COMMIT_REEXECUTE;
      numIters = numExecs;
    }
    writeFunctionCode(buf);
    buf.writeUB4(stmt.cursorId);
    buf.writeUB4(numIters);
    buf.writeUB4(options1);
    buf.writeUB4(options2);
    if (params.isNotEmpty) {
      for (var i = 0; i < numExecs; i++) {
        buf.writeUint8(TNS_MSG_TYPE_ROW_DATA);
        _writeBindParamsRow(buf, params, i);
      }
    }
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final stmt = statement;
    if (stmt.cursorId == 0 ||
        !stmt.executed ||
        stmt.sql == null ||
        stmt.noPrefetch ||
        stmt.bindsChanged ||
        parseOnly ||
        stmt.requiresDefine ||
        stmt.isDdl ||
        batchErrors ||
        cursor.scrollable) {
      functionCode = TNS_FUNC_EXECUTE;
      _writeExecuteMessage(buf);
    } else if (stmt.isQuery && cursor.prefetchRows > 0) {
      functionCode = TNS_FUNC_REEXECUTE_AND_FETCH;
      _writeReexecuteMessage(buf);
    } else {
      functionCode = TNS_FUNC_REEXECUTE;
      _writeReexecuteMessage(buf);
    }
    stmt.bindsChanged = false;
  }

  @override
  void process(ReadBuffer buf) {
    final stmt = statement;
    super.process(buf);
    if (errorOccurred && errorInfo.pos == 0 && stmt.isPlsql) {
      errorInfo.pos = errorInfo.rowcount + offset;
    }
    if (!parseOnly) stmt.executed = true;
    if (stmt.requiresDefine && stmt.sql != null) {
      if (resend) {
        stmt.requiresDefine = false;
      } else {
        resend = true;
      }
    }
  }
}

/// Fetches more rows from an open cursor.
class FetchMessage extends MessageWithData {
  FetchMessage(super.cursor) {
    functionCode = TNS_FUNC_FETCH;
  }

  @override
  void writeMessage(WriteBuffer buf) {
    cursor.fetchArraySize = cursor.arraySize;
    writeFunctionCode(buf);
    if (statement.cursorId == 0) throw dpyError(ERR_CURSOR_HAS_BEEN_CLOSED);
    buf.writeUB4(statement.cursorId);
    buf.writeUB4(cursor.fetchArraySize);
  }
}
