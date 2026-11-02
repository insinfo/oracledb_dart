import 'dart:convert';
import 'dart:typed_data';

import '../../exceptions.dart';
import '../buffer.dart';
import '../codecs.dart';
import '../connection_impl.dart';
import '../constants.dart';
import '../types.dart';
import 'lob_op.dart';

/// An error returned as part of a batch (executeMany with batch errors).
class BatchError {
  BatchError(this.code);

  final int code;
  int offset = 0;
  String message = '';

  @override
  String toString() => 'BatchError(offset: $offset, $message)';
}

class OracleErrorInfo {
  int num = 0;
  int cursorId = 0;
  int pos = 0;
  int rowcount = 0;
  String? message;
  int rowidRba = 0;
  int rowidPartitionId = 0;
  int rowidBlockNum = 0;
  int rowidSlotNum = 0;
  List<BatchError>? batchErrors;

  String? get rowid =>
      encodeRowid(rowidRba, rowidPartitionId, rowidBlockNum, rowidSlotNum);
}

/// Base class for all messages sent to the server.
abstract class Message {
  Message(this.conn);

  final ThinConnImpl conn;
  int messageType = TNS_MSG_TYPE_FUNCTION;
  int functionCode = 0;
  int callStatus = 0;
  int endToEndSeqNum = 0;
  int tokenNum = 0;
  bool endOfResponse = false;
  bool errorOccurred = false;
  bool flushOutBinds = false;
  bool resend = false;
  bool retry = false;
  OracleErrorInfo errorInfo = OracleErrorInfo();
  OracleException? warning;

  /// Throws the error returned by the server, if one was returned.
  void checkAndThrow() {
    if (!errorOccurred) return;
    final error = createOracleException(
        message: errorInfo.message ?? '',
        oraCode: errorInfo.num,
        offset: errorInfo.pos);
    if (error.isSessionDead) conn.protocol.forceDisconnect();
    throw error;
  }

  void processErrorInfo(ReadBuffer buf) {
    final info = errorInfo;
    callStatus = buf.readUB4(); // end of call status
    buf.skipUB2(); // end to end seq#
    buf.skipUB4(); // current row number
    buf.skipUB2(); // error number
    buf.skipUB2(); // array elem error
    buf.skipUB2(); // array elem error
    info.cursorId = buf.readUB2(); // cursor id
    final errorPos = buf.readSB2(); // error position
    buf.skipUB1(); // sql type (19c and earlier)
    buf.skipUB1(); // fatal?
    buf.skipUB1(); // flags
    buf.skipUB1(); // user cursor options
    buf.skipUB1(); // UPI parameter
    final flags = buf.readUB1();
    if (flags & 0x20 != 0) {
      warning = dpyError(WRN_COMPILATION_ERROR);
    }
    info.rowidRba = buf.readUB4(); // rowid
    info.rowidPartitionId = buf.readUB2();
    buf.skipUB1();
    info.rowidBlockNum = buf.readUB4();
    info.rowidSlotNum = buf.readUB2();
    buf.skipUB4(); // OS error
    buf.skipUB1(); // statement number
    buf.skipUB1(); // call number
    buf.skipUB2(); // padding
    buf.skipUB4(); // success iters
    final numBytes = buf.readUB4(); // oerrdd (logical rowid)
    if (numBytes > 0) buf.skipRawBytesChunked();

    // batch error codes
    final numErrors = buf.readUB2();
    if (numErrors > 0) {
      final errors = info.batchErrors = <BatchError>[];
      final firstByte = buf.readUB1();
      for (var i = 0; i < numErrors; i++) {
        if (firstByte == TNS_LONG_LENGTH_INDICATOR) buf.skipUB4();
        errors.add(BatchError(buf.readUB2()));
      }
      if (firstByte == TNS_LONG_LENGTH_INDICATOR) buf.skipRawBytes(1);
    }

    // batch error offsets
    final numOffsets = buf.readUB4();
    if (numOffsets > 0) {
      if (numOffsets > 65535) throw dpyError(ERR_TOO_MANY_BATCH_ERRORS);
      final firstByte = buf.readUB1();
      for (var i = 0; i < numOffsets; i++) {
        if (firstByte == TNS_LONG_LENGTH_INDICATOR) buf.skipUB4();
        final offset = buf.readUB4();
        if (i < numErrors) info.batchErrors![i].offset = offset;
      }
      if (firstByte == TNS_LONG_LENGTH_INDICATOR) buf.skipRawBytes(1);
    }

    // batch error messages
    final numMessages = buf.readUB2();
    if (numMessages > 0) {
      buf.skipRawBytes(1); // ignore packed size
      for (var i = 0; i < numMessages; i++) {
        buf.skipUB2(); // skip chunk length
        final message = (buf.readStr() ?? '').trimRight();
        if (info.batchErrors != null && i < info.batchErrors!.length) {
          info.batchErrors![i].message = message;
        }
        buf.skipRawBytes(2); // ignore end marker
      }
    }

    info.num = buf.readUB4(); // error number (extended)
    info.rowcount = buf.readUB8(); // row number (extended)

    // fields added in Oracle Database 20c
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_20_1) {
      buf.skipUB4(); // sql type
      buf.skipUB4(); // server checksum
    }

    // error message
    if (info.num != 0) {
      errorOccurred = true;
      if (errorPos > 0) info.pos = errorPos;
      info.message = (buf.readStr() ?? '').trimRight();
    }

    // an error message marks the end of a response if no explicit end of
    // response is available
    if (!buf.caps.supportsEndOfResponse) endOfResponse = true;
  }

  void processKeywordValuePairs(ReadBuffer buf, int numPairs) {
    for (var i = 0; i < numPairs; i++) {
      Uint8List? textValue, binaryValue;
      if (buf.readUB2() > 0) textValue = buf.readBytes(); // text value
      if (buf.readUB2() > 0) binaryValue = buf.readBytes(); // binary value
      final keywordNum = buf.readUB2(); // keyword num
      if (keywordNum == TNS_KEYWORD_NUM_CURRENT_SCHEMA && textValue != null) {
        conn.currentSchema = utf8.decode(textValue);
      } else if (keywordNum == TNS_KEYWORD_NUM_EDITION && textValue != null) {
        conn.edition = utf8.decode(textValue);
      } else if (keywordNum == TNS_KEYWORD_NUM_TRANSACTION_ID &&
          binaryValue != null) {
        _updateSessionlessTxnState(binaryValue);
      }
    }
  }

  void _updateSessionlessTxnState(Uint8List data) {
    final state = data[data.length - 2];
    final syncVersion = data[data.length - 1];
    if (syncVersion != 1) {
      throw dpyError(ERR_UNKNOWN_TRANSACTION_SYNC_VERSION,
          args: {'version': syncVersion});
    }
    if (state & TNS_TPC_TXNID_SYNC_UNSET != 0) {
      conn.protocol.txnInProgress = false;
    } else if (state & TNS_TPC_TXNID_SYNC_SET != 0) {
      conn.protocol.txnInProgress = true;
    }
  }

  void processMessage(ReadBuffer buf, int messageType) {
    switch (messageType) {
      case TNS_MSG_TYPE_ERROR:
        processErrorInfo(buf);
      case TNS_MSG_TYPE_WARNING:
        processWarningInfo(buf);
      case TNS_MSG_TYPE_TOKEN:
        final tokenNum = buf.readUB8();
        if (tokenNum != this.tokenNum) {
          throw dpyError(ERR_MISMATCHED_TOKEN, args: {
            'token_num': tokenNum,
            'expected_token_num': this.tokenNum,
          });
        }
      case TNS_MSG_TYPE_STATUS:
        callStatus = buf.readUB4();
        endToEndSeqNum = buf.readUB2();
        if (!buf.caps.supportsEndOfResponse) endOfResponse = true;
      case TNS_MSG_TYPE_PARAMETER:
        processReturnParameters(buf);
      case TNS_MSG_TYPE_SERVER_SIDE_PIGGYBACK:
        processServerSidePiggyback(buf);
      case TNS_MSG_TYPE_END_OF_RESPONSE:
        endOfResponse = true;
      default:
        throw dpyError(ERR_MESSAGE_TYPE_UNKNOWN,
            args: {'message_type': messageType, 'position': buf.pos - 1});
    }
  }

  ColumnMetadata processMetadata(ReadBuffer buf) {
    final caps = buf.caps;
    final oraTypeNum = buf.readUB1();
    buf.skipUB1(); // flags
    final precision = buf.readSB1();
    final scale = buf.readSB1();
    final bufferSize = buf.readUB4();
    buf.skipUB4(); // max number of array elements
    buf.skipUB8(); // cont flags
    buf.readBytesWithLength(); // OID
    buf.skipUB2(); // version
    buf.skipUB2(); // character set id
    final csfrm = buf.readUB1(); // character set form
    var dbType = DbType.fromMetadata(oraTypeNum, csfrm);
    var maxSize = buf.readUB4();
    if (oraTypeNum == ORA_TYPE_NUM_RAW) maxSize = bufferSize;
    if (caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_12_2) {
      buf.skipUB4(); // oaccolid
    }
    final nullsAllowed = buf.readUB1();
    buf.skipUB1(); // v7 length of name
    final name = buf.readStrWithLength() ?? '';
    final schema = buf.readStrWithLength();
    final typeName = buf.readStrWithLength();
    buf.skipUB2(); // column position
    final udsFlags = buf.readUB4();
    String? domainSchema, domainName;
    Map<String, String>? annotations;
    if (caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1) {
      domainSchema = buf.readStrWithLength();
      domainName = buf.readStrWithLength();
    }
    if (caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_3) {
      var numAnnotations = buf.readUB4();
      if (numAnnotations > 0) {
        buf.skipUB1();
        annotations = {};
        numAnnotations = buf.readUB4();
        buf.skipUB1();
        for (var i = 0; i < numAnnotations; i++) {
          final key = buf.readStrWithLength() ?? '';
          final value = buf.readStrWithLength() ?? '';
          annotations[key] = value;
          buf.skipUB4(); // flags
        }
        buf.skipUB4(); // flags
      }
    }
    var vectorDimensions = 0, vectorFormat = 0, vectorFlags = 0;
    if (caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_4) {
      vectorDimensions = buf.readUB4();
      vectorFormat = buf.readUB1();
      vectorFlags = buf.readUB1();
    }
    if (oraTypeNum == ORA_TYPE_NUM_OBJECT &&
        schema == 'SYS' &&
        typeName == 'XMLTYPE') {
      dbType = DbType.xmltype;
    }
    return ColumnMetadata(
      name: name,
      dbType: dbType,
      precision: precision,
      scale: scale,
      maxSize: maxSize,
      bufferSize: bufferSize,
      nullable: nullsAllowed != 0,
      isJson: udsFlags & TNS_UDS_FLAGS_IS_JSON != 0,
      isOson: udsFlags & TNS_UDS_FLAGS_IS_OSON != 0,
      domainSchema: domainSchema,
      domainName: domainName,
      annotations: annotations,
      vectorDimensions: vectorDimensions,
      vectorFormat: vectorFormat,
      vectorFlags: vectorFlags,
    );
  }

  void processReturnParameters(ReadBuffer buf) {
    throw UnimplementedError('return parameters for $runtimeType');
  }

  void processServerSidePiggyback(ReadBuffer buf) {
    final opcode = buf.readUB1();
    switch (opcode) {
      case TNS_SERVER_PIGGYBACK_LTXID:
        conn.ltxid = buf.readBytesWithLength();
      case TNS_SERVER_PIGGYBACK_QUERY_CACHE_INVALIDATION:
      case TNS_SERVER_PIGGYBACK_TRACE_EVENT:
        break;
      case TNS_SERVER_PIGGYBACK_OS_PID_MTS:
        buf.readUB2();
        buf.skipRawBytesChunked();
      case TNS_SERVER_PIGGYBACK_SYNC:
        buf.skipUB2(); // skip number of DTYs
        buf.skipUB1(); // skip length of DTYs
        final numElements = buf.readUB2();
        buf.skipUB1(); // skip length
        processKeywordValuePairs(buf, numElements);
        buf.skipUB4(); // skip overall flags
      case TNS_SERVER_PIGGYBACK_EXT_SYNC:
        buf.skipUB2(); // skip number of DTYs
        buf.skipUB1(); // skip length of DTYs
      case TNS_SERVER_PIGGYBACK_AC_REPLAY_CONTEXT:
        buf.skipUB2(); // skip number of DTYs
        buf.skipUB1(); // skip length of DTYs
        buf.skipUB4(); // skip flags
        buf.skipUB4(); // skip error code
        buf.skipUB1(); // skip queue
        if (buf.readUB4() > 0) buf.skipRawBytesChunked(); // replay context
      case TNS_SERVER_PIGGYBACK_SESS_RET:
        buf.skipUB2();
        buf.skipUB1();
        final numElements = buf.readUB2();
        if (numElements > 0) {
          buf.skipUB1();
          for (var i = 0; i < numElements; i++) {
            if (buf.readUB2() > 0) buf.skipRawBytesChunked(); // key
            if (buf.readUB2() > 0) buf.skipRawBytesChunked(); // value
            buf.skipUB2(); // flags
          }
        }
        final flags = buf.readUB4(); // session flags
        if (flags & TNS_SESSGET_SESSION_CHANGED != 0 &&
            conn.drcpEstablishSession) {
          conn.statementCache.clearOpenCursors();
        }
        conn.drcpEstablishSession = false;
        conn.sessionId = buf.readUB4();
        conn.serialNum = buf.readUB2();
      case TNS_SERVER_PIGGYBACK_SESS_SIGNATURE:
        buf.skipUB2(); // number of dtys
        buf.skipUB1(); // length of dty
        buf.skipUB8(); // signature flags
        buf.skipUB8(); // client signature
        buf.skipUB8(); // server signature
      default:
        throw dpyError(ERR_UNKNOWN_SERVER_PIGGYBACK, args: {'opcode': opcode});
    }
  }

  void processWarningInfo(ReadBuffer buf) {
    final errorNum = buf.readUB2(); // error number
    final numBytes = buf.readUB2(); // length of error message
    buf.skipUB2(); // flags
    if (errorNum != 0 && numBytes > 0) {
      final message = (buf.readStr() ?? '').trimRight();
      warning = OracleWarning(message, code: errorNum);
    }
  }

  void writeFunctionCode(WriteBuffer buf) {
    writePiggybacks(buf);
    buf.writeUint8(messageType);
    buf.writeUint8(functionCode);
    buf.writeSeqNum();
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_1) {
      buf.writeUB8(tokenNum);
    }
  }

  void writeMessage(WriteBuffer buf) => writeFunctionCode(buf);

  void writePiggybackCode(WriteBuffer buf, int code) {
    buf.writeUint8(TNS_MSG_TYPE_PIGGYBACK);
    buf.writeUint8(code);
    buf.writeSeqNum();
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_1) {
      buf.writeUB8(tokenNum);
    }
  }

  void writePiggybacks(WriteBuffer buf) {
    if (conn.currentSchemaModified) _writeCurrentSchemaPiggyback(buf);
    if (conn.statementCache.numCursorsToClose > 0 &&
        !conn.drcpEstablishSession) {
      writePiggybackCode(buf, TNS_FUNC_CLOSE_CURSORS);
      buf.writeUint8(1); // pointer
      conn.statementCache.writeCursorsToClose(buf);
    }
    if (conn.endToEndModified) _writeEndToEndPiggyback(buf);
    if (conn.tempLobsTotalSize > 0) writeFreeTempLobsPiggyback(this, buf);
    if (conn.sessionStateDesired != 0) {
      writePiggybackCode(buf, TNS_FUNC_SESSION_STATE);
      buf.writeUB8(
          conn.sessionStateDesired | TNS_SESSION_STATE_EXPLICIT_BOUNDARY);
      conn.sessionStateDesired = 0;
    }
  }

  void _writeCurrentSchemaPiggyback(WriteBuffer buf) {
    writePiggybackCode(buf, TNS_FUNC_SET_SCHEMA);
    buf.writeUint8(1); // pointer
    final bytes = utf8.encode(conn.currentSchema ?? '');
    buf.writeUB4(bytes.length);
    buf.writeBytesWithLength(bytes);
    conn.currentSchemaModified = false;
  }

  void _writeEndToEndPiggyback(WriteBuffer buf) {
    final c = conn;
    var flags = 0;
    if (c.actionModified) flags |= TNS_END_TO_END_ACTION;
    if (c.clientIdentifierModified) flags |= TNS_END_TO_END_CLIENT_IDENTIFIER;
    if (c.clientInfoModified) flags |= TNS_END_TO_END_CLIENT_INFO;
    if (c.moduleModified) flags |= TNS_END_TO_END_MODULE;
    if (c.dbopModified) flags |= TNS_END_TO_END_DBOP;

    Uint8List? enc(String? v) => v == null ? null : utf8.encode(v);
    final clientIdentifier = enc(c.clientIdentifier);
    final module = enc(c.module);
    final action = enc(c.action);
    final clientInfo = enc(c.clientInfo);
    final dbop = enc(c.dbop);

    void header(bool modified, Uint8List? value) {
      if (modified) {
        buf.writeUint8(1); // pointer
        buf.writeUB4(value?.length ?? 0);
      } else {
        buf.writeUint8(0); // pointer
        buf.writeUB4(0); // length
      }
    }

    writePiggybackCode(buf, TNS_FUNC_SET_END_TO_END_ATTR);
    buf.writeUint8(0); // pointer (cidnam)
    buf.writeUint8(0); // pointer (cidser)
    buf.writeUB4(flags);
    header(c.clientIdentifierModified, clientIdentifier);
    header(c.moduleModified, module);
    header(c.actionModified, action);
    buf.writeUint8(0); // pointer (cideci)
    buf.writeUB4(0); // length (cideci)
    buf.writeUint8(0); // cidcct
    buf.writeUB4(0); // cidecs
    header(c.clientInfoModified, clientInfo);
    buf.writeUint8(0); // pointer (cidkstk)
    buf.writeUB4(0); // length (cidkstk)
    buf.writeUint8(0); // pointer (cidktgt)
    buf.writeUB4(0); // length (cidktgt)
    header(c.dbopModified, dbop);
    if (c.clientIdentifierModified && clientIdentifier != null) {
      buf.writeBytesWithLength(clientIdentifier);
    }
    if (c.moduleModified && module != null) buf.writeBytesWithLength(module);
    if (c.actionModified && action != null) buf.writeBytesWithLength(action);
    if (c.clientInfoModified && clientInfo != null) {
      buf.writeBytesWithLength(clientInfo);
    }
    if (c.dbopModified && dbop != null) buf.writeBytesWithLength(dbop);
    c.resetEndToEnd();
  }

  void preprocess() {}

  void postprocess() {}

  void process(ReadBuffer buf) {
    endOfResponse = false;
    flushOutBinds = false;
    while (!endOfResponse) {
      buf.savePoint();
      final messageType = buf.readUB1();
      processMessage(buf, messageType);
    }
  }

  void send(WriteBuffer buf) {
    buf.startRequest(TNS_PACKET_TYPE_DATA);
    writeMessage(buf);
    buf.endRequest();
  }
}

/// Releases a DRCP session back to the pool of the database (one-way: the
/// server sends no response).
class SessionReleaseMessage extends Message {
  SessionReleaseMessage(super.conn, this.releaseMode) {
    messageType = TNS_MSG_TYPE_ONEWAY_FN;
    functionCode = TNS_FUNC_SESSION_RELEASE;
  }

  final int releaseMode;

  @override
  void writeMessage(WriteBuffer buf) {
    writeFunctionCode(buf);
    buf.writeUint8(0); // pointer (tag name)
    buf.writeUint8(0); // tag name length
    buf.writeUB4(releaseMode); // mode
  }
}

/// Simple messages consisting only of a function code.
class SimpleMessage extends Message {
  SimpleMessage(super.conn, int functionCode) {
    this.functionCode = functionCode;
  }
}
