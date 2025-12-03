// Base thin message scaffolding. This is an incremental port of
// python-oracledb's base.pyx; many parts are still TODO.

import '../../../exceptions.dart';
import '../constants.dart';
import '../packet.dart';

/// Internal representation of error information received from the database.
class OracleErrorInfo {
  int num = 0; // ORA- or internal error number
  int cursorId = 0;
  int pos = 0; // Position offset in SQL for error
  int rowcount = 0; // Row count or row number for PL/SQL errors
  String? message;
  Rowid? rowid; // Rowid components
  List<OracleException>? batchErrors; // Batch errors, if any
}

/// Base class for all messages sent to and received from the Oracle database
/// in thin mode. Concrete message classes should override the parsing logic.
abstract class Message {
  /// Connection implementation (kept dynamic until the connection layer is ported).
  late final dynamic connImpl;

  /// Object type cache; dynamic placeholder for now.
  dynamic typeCache;

  /// Pipeline operation result; dynamic placeholder for now.
  dynamic pipelineResultImpl;

  late OracleErrorInfo errorInfo;

  int messageType = TNS_MSG_TYPE_FUNCTION;
  int functionCode = 0; // Set by subclasses
  int callStatus = 0; // Received from server
  int endToEndSeqNum = 0; // Received from server
  int tokenNum = 0; // Used for pipeline operations

  bool endOfResponse = false; // Flag indicating end of server response
  bool errorOccurred = false; // Flag indicating if an error was received
  bool flushOutBinds = false; // Flag indicating out binds need flushing
  bool resend = false; // Flag indicating message needs to be resent (e.g., define phase)
  bool retry = false; // Flag indicating execution should be retried (e.g., datatype change)
  OracleWarning? warning; // Any warning received

  bool get useLargeSdu {
    final version = connImpl?.capabilities.protocolVersion ?? 0;
    return version >= TNS_VERSION_MIN_LARGE_SDU;
  }

  /// Initializes the base message fields.
  /// Must be called by concrete message constructors or initialization methods.
  void initialize(dynamic connImpl) {
    this.connImpl = connImpl;
    errorInfo = OracleErrorInfo();
    initializeHook(); // Call subclass specific initialization
  }

  /// Hook for subclasses to perform specific initialization.
  void initializeHook() {}

  /// Checks if an error occurred during processing and throws the appropriate
  /// Dart exception. Forces connection closure for session dead errors.
  void checkAndRaiseException() {
    if (!errorOccurred) return;

    final isRecoverable = _recoverableOraCodes.contains(errorInfo.num);

    final OracleException error = createOracleException(
      message: errorInfo.message ?? "Unknown database error",
      oraCode: errorInfo.num,
      offset: errorInfo.pos,
      isRecoverable: isRecoverable,
    );

    if (error.isSessionDead) {
      try {
        // Best-effort: some connection implementations expose protocol control.
        connImpl?.protocol?._forceClose();
      } catch (_) {
        // ignore: best effort close
      }
    }
    throw error;
  }

  /// Processes the error information part of a response packet.
  /// This is a partial port; detailed batch/warning parsing still TODO.
  void processErrorInfo(ReadBuffer buf) {
    final info = errorInfo;
    info.batchErrors = null; // Reset batch errors

    callStatus = buf.readUint32(); // end of call status
    endToEndSeqNum = buf.readUint16(); // end to end seq# (ignored here)
    buf.skipUint32(); // current row number
    buf.skipUint16(); // error number (older format)
    buf.skipUint16(); // array elem error (older format)
    buf.skipUint16(); // array elem error (older format)
    info.cursorId = buf.readUint16(); // cursor id
    info.pos = buf.readInt16(); // error position
    buf.skipUint8(); // sql type (19c and earlier)
    buf.skipUint8(); // fatal?
    final flags = buf.readUint8(); // flags
    buf.skipUint8(); // user cursor options
    buf.skipUint8(); // UPI parameter

    if ((flags & 0x20) != 0) {
      warning = createOracleException(
        message: 'Compilation warning',
        dpyCode: WRN_COMPILATION_ERROR,
      ) as OracleWarning;
    }

    // Rowid
    info.rowid = buf.readRowid();
    buf.skipUint32(); // OS error
    buf.skipUint8(); // statement number
    buf.skipUint8(); // call number
    buf.skipUint16(); // padding
    buf.skipUint32(); // success iters

    final numBytes = buf.readUint32(); // oerrdd (logical rowid) length
    if (numBytes > 0) {
      buf.skipRawBytesChunked();
    }

    // Batch errors: codes
    final numErrors = buf.readUint16();
    if (numErrors > 0) {
      info.batchErrors = <OracleException>[];
      final firstByte = buf.readUint8();
      for (var i = 0; i < numErrors; i++) {
        if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
          buf.skipUint32(); // chunk length ignored
        }
        final code = buf.readUint16();
        info.batchErrors!.add(
          createOracleException(message: 'Batch error $code', oraCode: code),
        );
      }
      if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
        buf.skipBytes(1); // end marker
      }
    }

    // Batch errors: offsets
    final numOffsets = buf.readUint32();
    if (numOffsets > 0) {
      if (numOffsets > 65535) {
        throw createOracleException(
          dpyCode: ERR_TOO_MANY_BATCH_ERRORS,
          message: 'Too many batch errors returned ($numOffsets)',
        );
      }
      final firstByte = buf.readUint8();
      for (var i = 0; i < numOffsets; i++) {
        if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
          buf.skipUint32();
        }
        final offset = buf.readUint32();
        if (i < (info.batchErrors?.length ?? 0)) {
          info.batchErrors![i] = createOracleException(
            message: info.batchErrors![i].message,
            oraCode: info.batchErrors![i].code,
            offset: offset,
          );
        }
      }
      if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
        buf.skipBytes(1); // end marker
      }
    }
  }

  /// Process a single message segment from the server.
  /// This covers common message types and marks end-of-response when needed.
  void processMessage(ReadBuffer buf, int messageType) {
    if (messageType == TNS_MSG_TYPE_ERROR) {
      processErrorInfo(buf);
    } else if (messageType == TNS_MSG_TYPE_WARNING) {
      _processWarningInfo(buf);
    } else if (messageType == TNS_MSG_TYPE_SERVER_SIDE_PIGGYBACK) {
      _processServerSidePiggyback(buf);
    } else if (messageType == TNS_MSG_TYPE_PARAMETER) {
      processReturnParameters(buf);
    } else if (messageType == TNS_MSG_TYPE_TOKEN) {
      final token = buf.readUint64();
      if (token != tokenNum) {
        throw createOracleException(
          dpyCode: ERR_MISMATCHED_TOKEN,
          message: 'Token mismatch: got $token expected $tokenNum',
        );
      }
    } else if (messageType == TNS_MSG_TYPE_STATUS) {
      callStatus = buf.readUint32();
      endToEndSeqNum = buf.readUint16();
      endOfResponse = true; // conservative; refined once caps are threaded
    } else if (messageType == TNS_MSG_TYPE_END_OF_RESPONSE) {
      endOfResponse = true;
    } else {
      throw createOracleException(
        dpyCode: ERR_MESSAGE_TYPE_UNKNOWN,
        message: 'Unknown message type $messageType at position ${buf.remaining}',
      );
    }
  }

  /// Process all message chunks contained in the supplied buffer until the
  /// server signals the end of response or the buffer is exhausted.
  void processBuffer(ReadBuffer buf) {
    while (!buf.isEOF && !endOfResponse) {
      final messageType = buf.readUint8();
      processMessage(buf, messageType);
    }
  }

  /// Hook for subclasses that expect parameter payloads (for example AUTH).
  void processReturnParameters(ReadBuffer buf) {
    if (buf.remaining > 0) {
      buf.skipBytes(buf.remaining);
    }
  }

  void _processWarningInfo(ReadBuffer buf) {
    // Minimal warning handling: consume status and create a warning object.
    callStatus = buf.readUint32();
    warning = createOracleException(
      dpyCode: WRN_COMPILATION_ERROR,
      message: 'Server returned warning (status=$callStatus)',
    ) as OracleWarning;
  }

  void _processServerSidePiggyback(ReadBuffer buf) {
    if (buf.remaining == 0) return;
    final opcode = buf.readUint8();
    if (opcode == TNS_SERVER_PIGGYBACK_LTXID) {
      final ltxid = buf.readBytesWithLength();
      try {
        connImpl?._ltxid = ltxid;
      } catch (_) {
        // ignore if connection impl not wired yet
      }
      return;
    }
    // For other opcodes, consume the remaining payload to keep stream aligned.
    if (buf.remaining > 0) {
      buf.skipBytes(buf.remaining);
    }
  }
}

const Set<int> _recoverableOraCodes = {
  28,
  31,
  376,
  603,
  1012,
  1033,
  1034,
  1089,
  1090,
  1092,
  1115,
  2396,
  3113,
  3114,
  3135,
  12153,
  12514,
  12537,
  12547,
  12570,
  12571,
  12583,
  12757,
  16456,
};
//      buf.skipUint8(); // user cursor options
//      buf.skipUint8(); // UPI parameter
//      int flags = buf.readUint8();
//      if ((flags & 0x20) != 0) {
//         warning = _createOracleException( // Use helper to create warnings too
//           dpyCode: WRN_COMPILATION_ERROR, // Need this const defined
//           message: 'Creation succeeded with compilation errors',
//         ) as OracleWarning?;
//      }
//      info.rowid = buf.readRowid(); // rowid
//      buf.skipUint32(); // OS error
//      buf.skipUint8(); // statement number
//      buf.skipUint8(); // call number
//      buf.skipUint16(); // padding
//      buf.skipUint32(); // success iters
//      int numBytes = buf.readUint32(); // oerrdd (logical rowid) length
//      if (numBytes > 0) {
//        buf.skipRawBytesChunked();
//      }

//      // batch error codes
//      int numErrors = buf.readUint16(); // batch error codes array
//      if (numErrors > 0) {
//        info.batchErrors = List<OracleException>.filled(numErrors, OracleDatabaseError("")); // Pre-fill list
//        int firstByte = buf.readUint8();
//        for (int i = 0; i < numErrors; i++) {
//          if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
//            buf.skipUint32(); // chunk length ignored
//          }
//          int errorCode = buf.readUint16();
//          // Create a basic error, message will be filled later if available
//          info.batchErrors![i] = _createOracleException(oraCode: errorCode, message: 'Batch error code $errorCode');
//        }
//        if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
//          buf.skipBytes(1); // ignore end marker
//        }
//      }

//      // batch error offsets
//      int numOffsets = buf.readUint32(); // batch error row offset array
//      if (numOffsets > 0) {
//        if (numOffsets > 65535) {
//           throw _createOracleException(dpyCode: ERR_TOO_MANY_BATCH_ERRORS, message: 'Too many batch errors');
//        }
//        int firstByte = buf.readUint8();
//        for (int i = 0; i < numOffsets; i++) {
//          if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
//            buf.skipUint32(); // chunk length ignored
//          }
//          int offset = buf.readUint32();
//          if (info.batchErrors != null && i < info.batchErrors!.length) {
//             // Directly modifying the object might be complex in Dart if immutable.
//             // Consider creating new instances or using mutable error objects.
//             // This is a direct translation approach:
//             var originalError = info.batchErrors![i];
//             info.batchErrors![i] = _createOracleException(
//               message: originalError.message, // Keep original message for now
//               oraCode: originalError.code,
//               dpyCode: int.tryParse(originalError.fullCode?.substring(4) ?? ''),
//               offset: offset, // Set the offset
//               context: originalError.context,
//               cause: originalError.cause,
//             );
//          }
//        }
//        if (firstByte == TNS_LONG_LENGTH_INDICATOR) {
//          buf.skipBytes(1); // ignore end marker
//        }
//      }

//      // batch error messages
//      int numMessages = buf.readUint16(); // batch error messages array
//      if (numMessages > 0) {
//        buf.skipBytes(1); // ignore packed size
//        for (int i = 0; i < numMessages; i++) {
//          buf.skipUint16(); // skip chunk length
//          String errorMessage = buf.readString(CS_FORM_IMPLICIT)?.trim() ?? '';
//          if (info.batchErrors != null && i < info.batchErrors!.length) {
//            // Update the message of the existing error object
//            var originalError = info.batchErrors![i];
//            info.batchErrors![i] = _createOracleException(
//              message: errorMessage, // Set the actual message
//              oraCode: originalError.code,
//              dpyCode: int.tryParse(originalError.fullCode?.substring(4) ?? ''),
//              offset: originalError.offset,
//              context: originalError.context,
//              cause: originalError.cause,
//            );
//            // Potentially call a method similar to _make_adjustments here
//          }
//          buf.skipBytes(2); // ignore end marker
//        }
//      }

//      info.num = buf.readUint32(); // error number (extended)
//      info.rowcount = buf.readUint64(); // row number (extended)

//      // fields added in Oracle Database 20c
//      if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_20_1) {
//        buf.skipUint32(); // sql type
//        buf.skipUint32(); // server checksum
//      }

//      // error message
//      if (info.num != 0) {
//        errorOccurred = true;
//        if (info.pos < 0) info.pos = 0; // Error pos is sb2, adjust if needed
//        info.message = buf.readString(CS_FORM_IMPLICIT)?.trim();
//      }

//      // an error message marks the end of a response if no explicit end of
//      // response is available
//      if (!buf.caps.supportsEndOfResponse) {
//        endOfResponse = true;
//      }
//   }


//   /// Processes a single message type received from the buffer.
//   void _processMessage(ReadBuffer buf, int messageType) {
//     if (messageType == TNS_MSG_TYPE_ERROR) {
//       _processErrorInfo(buf);
//     } else if (messageType == TNS_MSG_TYPE_WARNING) {
//       _processWarningInfo(buf);
//     } else if (messageType == TNS_MSG_TYPE_TOKEN) {
//       int receivedTokenNum = buf.readUint64();
//       if (receivedTokenNum != tokenNum) {
//          throw _createOracleException(
//             dpyCode: ERR_MISMATCHED_TOKEN,
//             message: 'Token mismatch', // Arguments need formatting
//             // token_num: receivedTokenNum,
//             // expected_token_num: tokenNum,
//          );
//       }
//     } else if (messageType == TNS_MSG_TYPE_STATUS) {
//       callStatus = buf.readUint32();
//       endToEndSeqNum = buf.readUint16();
//       if (!buf.caps.supportsEndOfResponse) {
//         endOfResponse = true;
//       }
//     } else if (messageType == TNS_MSG_TYPE_PARAMETER) {
//       _processReturnParameters(buf);
//     } else if (messageType == TNS_MSG_TYPE_SERVER_SIDE_PIGGYBACK) {
//       _processServerSidePiggyback(buf);
//     } else if (messageType == TNS_MSG_TYPE_END_OF_RESPONSE) {
//       endOfResponse = true;
//     } else {
//        throw _createOracleException(
//           dpyCode: ERR_MESSAGE_TYPE_UNKNOWN,
//           message: 'Unknown message type', // Arguments need formatting
//           // message_type: messageType,
//           // position: buf.pos - 1,
//        );
//     }
//   }


//   /// Processes the return parameters section of a response.
//   /// Must be implemented by subclasses that expect return parameters.
//   void _processReturnParameters(ReadBuffer buf) {
//     throw OracleInternalError("Subclass must implement _processReturnParameters");
//   }

//   /// Processes a server-side piggyback message.
//   void _processServerSidePiggyback(ReadBuffer buf) {
//     int opcode = buf.readUint8();
//     switch (opcode) {
//       case TNS_SERVER_PIGGYBACK_LTXID:
//         connImpl.ltxid = buf.readBytesWithLength();
//         break;
//       case TNS_SERVER_PIGGYBACK_QUERY_CACHE_INVALIDATION:
//       case TNS_SERVER_PIGGYBACK_TRACE_EVENT:
//         // Currently ignored
//         break;
//       case TNS_SERVER_PIGGYBACK_OS_PID_MTS:
//         buf.skipUint16();
//         buf.skipRawBytesChunked();
//         break;
//       case TNS_SERVER_PIGGYBACK_SYNC:
//         buf.skipUint16(); // num DTYs
//         buf.skipUint8(); // length DTYs
//         int numElements = buf.readUint16();
//         buf.skipUint8(); // length
//         for (int i = 0; i < numElements; i++) {
//           int temp16 = buf.readUint16();
//           if (temp16 > 0) buf.skipRawBytesChunked(); // key
//           temp16 = buf.readUint16();
//           if (temp16 > 0) buf.skipRawBytesChunked(); // value
//           buf.skipUint16(); // flags
//         }
//         buf.skipUint32(); // overall flags
//         break;
//       case TNS_SERVER_PIGGYBACK_EXT_SYNC:
//         buf.skipUint16(); // num DTYs
//         buf.skipUint8(); // length DTYs
//         break;
//       case TNS_SERVER_PIGGYBACK_AC_REPLAY_CONTEXT:
//         buf.skipUint16(); // num DTYs
//         buf.skipUint8(); // length DTYs
//         buf.skipUint32(); // flags
//         buf.skipUint32(); // error code
//         buf.skipUint8(); // queue
//         int numBytes = buf.readUint32(); // replay context len
//         if (numBytes > 0) buf.skipRawBytesChunked();
//         break;
//       case TNS_SERVER_PIGGYBACK_SESS_RET:
//          buf.skipUint16();
//          buf.skipUint8();
//          int numElements = buf.readUint16();
//          if (numElements > 0) {
//            buf.skipUint8();
//            for (int i = 0; i < numElements; i++) {
//              int temp16 = buf.readUint16();
//              if (temp16 > 0) buf.skipRawBytesChunked(); // key
//              temp16 = buf.readUint16();
//              if (temp16 > 0) buf.skipRawBytesChunked(); // value
//              buf.skipUint16(); // flags
//            }
//          }
//          int flags = buf.readUint32(); // session flags
//          if ((flags & TNS_SESSGET_SESSION_CHANGED) != 0) {
//            if (connImpl.drcpEstablishSession) {
//               connImpl.statementCache?.clearOpenCursors(); // Need null check
//            }
//          }
//          connImpl.drcpEstablishSession = false;
//          connImpl.sessionId = buf.readUint32();
//          connImpl.serialNum = buf.readUint16();
//          break;
//       case TNS_SERVER_PIGGYBACK_SESS_SIGNATURE:
//         buf.skipUint16(); // num dtys
//         buf.skipUint8(); // length dty
//         buf.skipUint64(); // signature flags
//         buf.skipUint64(); // client signature
//         buf.skipUint64(); // server signature
//         break;
//       default:
//          throw _createOracleException(
//             dpyCode: ERR_UNKNOWN_SERVER_PIGGYBACK,
//             message: 'Unknown piggyback opcode', // Args need formatting
//             // opcode: opcode,
//          );
//     }
//   }


//   /// Processes the warning information part of a response packet.
//   void _processWarningInfo(ReadBuffer buf) {
//      int errorNum = buf.readUint16();
//      int numBytes = buf.readUint16();
//      buf.skipUint16(); // flags
//      if (errorNum != 0 && numBytes > 0) {
//        String message = buf.readString(CS_FORM_IMPLICIT)?.trim() ?? '';
//        warning = _createOracleException(
//           oraCode: errorNum,
//           message: message,
//        ) as OracleWarning?;
//      }
//   }

//   // --- Piggyback Writing Methods (Internal Helpers) ---

//   /// Writes the piggyback header for starting a pipeline.
//   void _writeBeginPipelinePiggyback(WriteBuffer buf) {
//     buf.dataFlags |= TNS_DATA_FLAGS_BEGIN_PIPELINE;
//     _writePiggybackCode(buf, TNS_FUNC_PIPELINE_BEGIN);
//     buf.writeUint16(0); // error set ID
//     buf.writeUint8(0); // error set mode
//     buf.writeUint8(connImpl.pipelineMode);
//   }

//   /// Writes the piggyback header to close cursors.
//   void _writeCloseCursorsPiggyback(WriteBuffer buf) {
//     _writePiggybackCode(buf, TNS_FUNC_CLOSE_CURSORS);
//     buf.writeUint8(1); // pointer
//     connImpl.statementCache?.writeCursorsToClose(buf); // Need null check
//   }

//   /// Writes the piggyback header to set the current schema.
//   void _writeCurrentSchemaPiggyback(WriteBuffer buf) {
//     _writePiggybackCode(buf, TNS_FUNC_SET_SCHEMA);
//     buf.writeUint8(1); // pointer
//     final schemaBytes = connImpl.currentSchema?.codeUnits ?? Uint8List(0);
//     buf.writeUint32(schemaBytes.length);
//     buf.writeBytesWithLength(schemaBytes);
//   }

//    /// Writes the piggyback to close temporary LOBs.
//   void _writeCloseTempLobsPiggyback(WriteBuffer buf) {
//      final lobsToClose = connImpl.tempLobsToClose;
//      if (lobsToClose == null || lobsToClose.isEmpty) return;

//      _writePiggybackCode(buf, TNS_FUNC_LOB_OP);
//      const int opCode = TNS_LOB_OP_FREE_TEMP | TNS_LOB_OP_ARRAY;

//      // Temp lob data header
//      buf.writeUint8(1); // pointer
//      buf.writeUint32(connImpl.tempLobsTotalSize);
//      buf.writeUint8(0); // dest lob locator pointer
//      buf.writeUint32(0); // dest lob locator length
//      buf.writeUint32(0); // source lob locator pointer (unused for free)
//      buf.writeUint32(0); // source lob locator length (unused for free)
//      buf.writeUint8(0); // source lob offset
//      buf.writeUint8(0); // dest lob offset
//      buf.writeUint8(0); // charset
//      buf.writeUint32(opCode);
//      buf.writeUint8(0); // scn
//      buf.writeUint32(0); // losbscn
//      buf.writeUint64(0); // lobscnl
//      buf.writeUint64(0);
//      buf.writeUint8(0);

//      // Array lob fields (unused for free)
//      buf.writeUint8(0);
//      buf.writeUint32(0);
//      buf.writeUint8(0);
//      buf.writeUint32(0);
//      buf.writeUint8(0);
//      buf.writeUint32(0);

//      // Write the actual LOB locators
//      for (final locator in lobsToClose) {
//        buf.writeBytes(locator);
//      }

//      // Reset connection state
//      connImpl.tempLobsToClose = null;
//      connImpl.tempLobsTotalSize = 0;
//    }


//    /// Writes the piggyback for end-to-end attributes.
//   void _writeEndToEndPiggyback(WriteBuffer buf) {
//     int flags = 0;
//     Uint8List? actionBytes;
//     Uint8List? clientIdBytes;
//     Uint8List? clientInfoBytes;
//     Uint8List? moduleBytes;
//     Uint8List? dbopBytes;

//     // Determine flags and encode strings
//     if (connImpl.actionModified) {
//       flags |= TNS_END_TO_END_ACTION;
//       actionBytes = connImpl.action?.codeUnits;
//     }
//     if (connImpl.clientIdentifierModified) {
//       flags |= TNS_END_TO_END_CLIENT_IDENTIFIER;
//       clientIdBytes = connImpl.clientIdentifier?.codeUnits;
//     }
//     if (connImpl.clientInfoModified) {
//       flags |= TNS_END_TO_END_CLIENT_INFO;
//       clientInfoBytes = connImpl.clientInfo?.codeUnits;
//     }
//     if (connImpl.moduleModified) {
//       flags |= TNS_END_TO_END_MODULE;
//       moduleBytes = connImpl.module?.codeUnits;
//     }
//     if (connImpl.dbopModified) {
//       flags |= TNS_END_TO_END_DBOP;
//       dbopBytes = connImpl.dbop?.codeUnits;
//     }

//     // Write initial packet data
//     _writePiggybackCode(buf, TNS_FUNC_SET_END_TO_END_ATTR);
//     buf.writeUint8(0); // pointer (cidnam)
//     buf.writeUint8(0); // pointer (cidser)
//     buf.writeUint32(flags);

//     // Write headers (pointers and lengths)
//     buf.writeUint8(connImpl.clientIdentifierModified ? 1 : 0);
//     buf.writeUint32(clientIdBytes?.length ?? 0);
//     buf.writeUint8(connImpl.moduleModified ? 1 : 0);
//     buf.writeUint32(moduleBytes?.length ?? 0);
//     buf.writeUint8(connImpl.actionModified ? 1 : 0);
//     buf.writeUint32(actionBytes?.length ?? 0);
//     buf.writeUint8(0); buf.writeUint32(0); // cideci
//     buf.writeUint8(0); buf.writeUint32(0); // cidcct, cidecs
//     buf.writeUint8(connImpl.clientInfoModified ? 1 : 0);
//     buf.writeUint32(clientInfoBytes?.length ?? 0);
//     buf.writeUint8(0); buf.writeUint32(0); // cidkstk
//     buf.writeUint8(0); buf.writeUint32(0); // cidktgt
//     buf.writeUint8(connImpl.dbopModified ? 1 : 0);
//     buf.writeUint32(dbopBytes?.length ?? 0);

//     // Write actual string values if they exist
//     if (connImpl.clientIdentifierModified && clientIdBytes != null) {
//         buf.writeBytesWithLength(clientIdBytes);
//     }
//     if (connImpl.moduleModified && moduleBytes != null) {
//         buf.writeBytesWithLength(moduleBytes);
//     }
//     if (connImpl.actionModified && actionBytes != null) {
//         buf.writeBytesWithLength(actionBytes);
//     }
//     if (connImpl.clientInfoModified && clientInfoBytes != null) {
//         buf.writeBytesWithLength(clientInfoBytes);
//     }
//     if (connImpl.dbopModified && dbopBytes != null) {
//         buf.writeBytesWithLength(dbopBytes);
//     }

//     // Reset flags and values on connection
//     connImpl.actionModified = false;
//     connImpl.action = null;
//     connImpl.clientIdentifierModified = false;
//     connImpl.clientIdentifier = null;
//     connImpl.clientInfoModified = false;
//     connImpl.clientInfo = null;
//     connImpl.dbopModified = false;
//     connImpl.dbop = null;
//     connImpl.moduleModified = false;
//     connImpl.module = null;
//   }

//   /// Writes the function code header, including any necessary piggybacks.
//   void _writeFunctionCode(WriteBuffer buf) {
//     _writePiggybacks(buf); // Write piggybacks first
//     buf.writeUint8(messageType);
//     buf.writeUint8(functionCode);
//     buf.writeSeqNum(); // Assuming WriteBuffer has this method
//     if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_1) {
//       buf.writeUint64(tokenNum);
//     }
//   }

//   /// Abstract method for subclasses to implement writing their specific message payload.
//   void _writeMessage(WriteBuffer buf);


//   /// Writes the header for a piggyback message.
//   void _writePiggybackCode(WriteBuffer buf, int code) {
//     buf.writeUint8(TNS_MSG_TYPE_PIGGYBACK);
//     buf.writeUint8(code);
//     buf.writeSeqNum(); // Assuming WriteBuffer has this method
//     if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_1) {
//       buf.writeUint64(tokenNum);
//     }
//   }

//   /// Writes all pending piggyback messages before the main message.
//   void _writePiggybacks(WriteBuffer buf) {
//     if (connImpl.pipelineMode != 0) {
//       _writeBeginPipelinePiggyback(buf);
//       connImpl.pipelineMode = 0;
//     }
//     if (connImpl.currentSchemaModified) {
//       _writeCurrentSchemaPiggyback(buf);
//       // Reset flag after writing
//       connImpl.currentSchemaModified = false;
//     }
//     if (connImpl.statementCache != null &&
//         connImpl.statementCache!.numCursorsToClose > 0 &&
//         !connImpl.drcpEstablishSession) {
//       _writeCloseCursorsPiggyback(buf);
//     }
//     if (connImpl.actionModified ||
//         connImpl.clientIdentifierModified ||
//         connImpl.clientInfoModified ||
//         connImpl.dbopModified ||
//         connImpl.moduleModified) {
//       _writeEndToEndPiggyback(buf);
//     }
//      if (connImpl.tempLobsTotalSize > 0) {
//        _writeCloseTempLobsPiggyback(buf);
//      }
//     if (connImpl.sessionStateDesired != 0) {
//       _writeSessionStatePiggyback(buf);
//     }
//   }

//   /// Writes the session state piggyback message.
//   void _writeSessionStatePiggyback(WriteBuffer buf) {
//      int state = connImpl.sessionStateDesired;
//      _writePiggybackCode(buf, TNS_FUNC_SESSION_STATE);
//      buf.writeUint64(state | TNS_SESSION_STATE_EXPLICIT_BOUNDARY);
//      connImpl.sessionStateDesired = 0; // Reset after writing
//   }


//   /// Hook for subclasses to perform actions after processing the response.
//   void postprocess() {
//     // Default: no-op
//   }

//   /// Async version of postprocess.
//   Future<void> postprocessAsync() async {
//     // Default: no-op
//   }

//   /// Hook for subclasses to perform actions before sending the message.
//   void preprocess() {
//     // Default: no-op
//   }

//   /// Processes the entire response from the ReadBuffer for this message.
//   void process(ReadBuffer buf) {
//     endOfResponse = false;
//     flushOutBinds = false;
//     while (!endOfResponse) {
//       buf.savePoint(); // Save position in case of needing more data (async)
//       int messageType = buf.readUint8();
//       _processMessage(buf, messageType);
//     }
//   }

//   /// Sends the message using the WriteBuffer.
//   void send(WriteBuffer buf) {
//     buf.startRequest(TNS_PACKET_TYPE_DATA);
//     _writeMessage(buf);
//     if (pipelineResultImpl != null) {
//       buf.dataFlags |= TNS_DATA_FLAGS_END_OF_REQUEST;
//     }
//     buf.endRequest();
//   }
// }


// /// Base class for messages that handle column data (like execute and fetch).
// abstract class MessageWithData extends Message {
//    BaseThinCursorImpl? cursorImpl; // Associated cursor implementation
//    Uint8List? bitVectorBuf; // Buffer for the bit vector (null indicators)
//    // Pointer equivalent - in Dart, maybe just use bitVectorBuf directly with offsets
//    // const char_type *bit_vector;
//    bool arraydmlrowcounts = false;
//    int row_index = 0; // Current row index being processed in the buffer
//    int num_execs = 1; // Number of executions (for executeMany)
//    int num_columns_sent = 0; // Columns sent in bit vector case
//    List<int>? dmlrowcounts; // DML row counts for array DML
//    bool batcherrors = false;
//    List<ThinVarImpl>? out_var_impls; // Variables for OUT binds (PL/SQL)
//    bool in_fetch = false; // Flag indicating if currently processing fetch data
//    bool parse_only = false;
//    dynamic cursor; // Reference to the public Cursor object
//    int offset = 0; // Offset for executeMany

//    /// Adjusts metadata if server returns a different type than expected
//    /// (e.g., CLOB data when expecting VARCHAR).
//    void _adjustMetadata(ThinVarImpl prevVarImpl, OracleMetadata metadata) {
//      int typeNum = metadata.dbType.oraTypeNum;
//      int prevTypeNum = prevVarImpl.fetchMetadata!.dbType.oraTypeNum; // Add null check

//      if (typeNum == ORA_TYPE_NUM_CLOB &&
//          const {
//            ORA_TYPE_NUM_CHAR,
//            ORA_TYPE_NUM_LONG,
//            ORA_TYPE_NUM_VARCHAR
//          }.contains(prevTypeNum)) {
//        int csfrm = prevVarImpl.fetchMetadata!.dbType.csfrm; // Add null check
//        metadata.dbType = DbType.fromOraTypeAndCsfrm(ORA_TYPE_NUM_LONG, csfrm);
//      } else if (typeNum == ORA_TYPE_NUM_BLOB &&
//          const {ORA_TYPE_NUM_RAW, ORA_TYPE_NUM_LONG_RAW}.contains(prevTypeNum)) {
//        metadata.dbType = DbType.fromOraTypeAndCsfrm(ORA_TYPE_NUM_LONG_RAW, 0);
//      }
//    }

//    /// Creates a cursor instance based on describe information received.
//    dynamic /* BaseThinCursor */ _createCursorFromDescribe(ReadBuffer buf, [dynamic cursor]) {
//      // Needs implementation detail for cursor creation in Dart
//      throw UnimplementedError();
//    }


//    /// Reads and stores the bit vector for null/duplicate handling.
//    void _getBitVector(ReadBuffer buf, int numBytes) {
//       Uint8List ptr = buf.readBytes(numBytes); // Assumes readBytes returns Uint8List
//       if (bitVectorBuf == null || bitVectorBuf!.length < numBytes) {
//         bitVectorBuf = Uint8List(numBytes);
//       }
//       bitVectorBuf!.setRange(0, numBytes, ptr);
//       // Note: Dart doesn't have a direct pointer equivalent for `bit_vector`.
//       // Logic using it will need to access `bitVectorBuf` directly.
//    }


//    /// Checks the bit vector to see if data for a column is duplicated.
//    bool _isDuplicateData(int columnNum) {
//      if (bitVectorBuf == null) {
//        return false;
//      }
//      int byteNum = columnNum ~/ 8;
//      int bitNum = columnNum % 8;
//      if (byteNum >= bitVectorBuf!.length) {
//          // Avoid out-of-bounds access if bit vector is shorter than expected
//          return false;
//      }
//      return (bitVectorBuf![byteNum] & (1 << bitNum)) == 0;
//    }

//   /// Writes column metadata for bind variables.
//   void _writeColumnMetadata(WriteBuffer buf, List<ThinVarImpl> bindVarImpls) {
//     for (final varImpl in bindVarImpls) {
//       final metadata = varImpl.metadata!; // Add null check
//       int oraTypeNum = metadata.dbType.oraTypeNum;
//       int bufferSize = metadata.bufferSize;
//       if (const {ORA_TYPE_NUM_ROWID, ORA_TYPE_NUM_UROWID}.contains(oraTypeNum)) {
//         oraTypeNum = ORA_TYPE_NUM_VARCHAR;
//         bufferSize = TNS_MAX_UROWID_LENGTH;
//       }
//       int flag = TNS_BIND_USE_INDICATORS;
//       if (varImpl.isArray) {
//         flag |= TNS_BIND_ARRAY;
//       }
//       int contFlag = 0;
//       int lobPrefetchLength = 0;
//       if (const {ORA_TYPE_NUM_BLOB, ORA_TYPE_NUM_CLOB}.contains(oraTypeNum)) {
//         contFlag = TNS_LOB_PREFETCH_FLAG;
//       } else if (oraTypeNum == ORA_TYPE_NUM_JSON) {
//         contFlag = TNS_LOB_PREFETCH_FLAG;
//         bufferSize = lobPrefetchLength = TNS_JSON_MAX_LENGTH;
//       } else if (oraTypeNum == ORA_TYPE_NUM_VECTOR) {
//         contFlag = TNS_LOB_PREFETCH_FLAG;
//         bufferSize = lobPrefetchLength = TNS_VECTOR_MAX_LENGTH;
//       }
//       buf.writeUint8(oraTypeNum);
//       buf.writeUint8(flag);
//       buf.writeUint8(0); // Precision
//       buf.writeUint8(0); // Scale
//       buf.writeUint32(bufferSize);
//       buf.writeUint32(varImpl.isArray ? varImpl.numElements : 0); // Max array elements
//       buf.writeUint64(contFlag);
//       if (metadata.objType != null) {
//         final typImpl = metadata.objType as ThinDbObjectTypeImpl; // Needs cast
//         buf.writeUint32(typImpl.oid.length);
//         buf.writeBytesWithLength(typImpl.oid);
//         buf.writeUint32(typImpl.version);
//       } else {
//         buf.writeUint32(0); // OID length
//         buf.writeUint16(0); // version
//       }
//       buf.writeUint16(metadata.dbType.csfrm != 0 ? TNS_CHARSET_UTF8 : 0);
//       buf.writeUint8(metadata.dbType.csfrm);
//       buf.writeUint32(lobPrefetchLength); // max chars (LOB prefetch)
//       if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_12_2) {
//         buf.writeUint32(0); // oaccolid
//       }
//     }
//   }

//   /// Writes a single column's value for a bind parameter row.
//   void _writeBindParamsColumn(WriteBuffer buf, OracleMetadata metadata, dynamic value) {
//       final oraTypeNum = metadata.dbType.oraTypeNum;
//       // ... (Implementation needs to translate the Cython _write_bind_params_column logic) ...
//       // This involves checking the type of 'value' and writing the corresponding
//       // TNS representation using buf.write* methods.
//       // Example for string:
//       if (value == null) {
//         buf.writeUint8(0); // Null indicator
//       } else if (const {
//             ORA_TYPE_NUM_VARCHAR, ORA_TYPE_NUM_CHAR, ORA_TYPE_NUM_LONG
//           }.contains(oraTypeNum)) {
//           Uint8List tempBytes;
//           if (metadata.dbType.csfrm == CS_FORM_IMPLICIT) {
//               tempBytes = (value as String).codeUnits as Uint8List; // Or utf8.encode
//           } else {
//               buf.caps.checkNCharsetId();
//               tempBytes = /* encode value as UTF16 */ throw UnimplementedError();
//           }
//           buf.writeBytesWithLength(tempBytes);
//       } else if (oraTypeNum == ORA_TYPE_NUM_NUMBER || oraTypeNum == ORA_TYPE_NUM_BINARY_INTEGER) {
//           Uint8List tempBytes;
//           if (value is bool) {
//               tempBytes = value ? Uint8List.fromList([49]) /* '1' */ : Uint8List.fromList([48]) /* '0' */;
//           } else {
//               tempBytes = value.toString().codeUnits as Uint8List; // Or utf8.encode
//           }
//           buf.writeOracleNumber(tempBytes); // Assuming WriteBuffer has this method
//       }
//       // ... handle other types (NUMBER, DATE, LOB, OBJECT, JSON, VECTOR etc.) ...
//        else {
//           throw _createOracleException(
//               dpyCode: ERR_DB_TYPE_NOT_SUPPORTED,
//               message: 'DB Type ${metadata.dbType.name} not supported for writing',
//               // name: metadata.dbType.name,
//           );
//        }
//     }

//   /// Writes a full row of bind parameters.
//   void _writeBindParamsRow(WriteBuffer buf, List<BindInfo> params, int pos) {
//     bool foundLong = false;
//     // Write non-LONG values first
//     for (final bindInfo in params) {
//       if (bindInfo.isReturnBind) continue;
//       final varImpl = bindInfo.bindVarImpl as ThinVarImpl; // Needs cast
//       final metadata = varImpl.metadata!; // Add null check
//       if (varImpl.isArray) {
//         final numElements = varImpl.numElementsInArray;
//         buf.writeUint32(numElements);
//         for (int k=0; k < numElements; ++k) {
//             final value = varImpl.values[k]; // Access internal values list
//              _writeBindParamsColumn(buf, metadata, value);
//         }
//       } else {
//         if (!cursorImpl!.statement!.isPlsql && // Add null checks
//             metadata.bufferSize > buf.caps.maxStringSize) {
//           foundLong = true;
//           continue;
//         }
//         _writeBindParamsColumn(buf, metadata, varImpl.values[pos + offset]); // Access internal values list
//       }
//     }
//     // Write LONG values if any were found
//     if (foundLong) {
//       for (final bindInfo in params) {
//          if (bindInfo.isReturnBind) continue;
//          final varImpl = bindInfo.bindVarImpl as ThinVarImpl; // Needs cast
//          final metadata = varImpl.metadata!; // Add null check
//          if (metadata.bufferSize <= buf.caps.maxStringSize) {
//            continue;
//          }
//          _writeBindParamsColumn(buf, metadata, varImpl.values[pos + offset]); // Access internal values list
//       }
//     }
//   }


//   /// Actions before processing query data (fetch).
//   void _preprocessQuery() {
//     final cursorImpl = this.cursorImpl!; // Assert non-null
//     final statement = cursorImpl.statement!; // Assert non-null

//     inFetch = true;
//     cursorImpl.moreRowsToFetch = true;
//     cursorImpl.bufferRowcount = cursorImpl.bufferIndex = 0;
//     row_index = 0;

//     if (statement.fetchVarImpls == null) {
//       return; // No fetch vars yet, describe info will create them
//     }

//     // Check if output type handler changed
//     bool usesMetadata = false; // Placeholder
//     final typeHandler = cursorImpl.getOutputTypeHandler(usesMetadata);
//     if (typeHandler != statement.lastOutputTypeHandler) {
//       final conn = cursor!.connection; // Assert non-null
//       for (int i = 0; i < cursorImpl.fetchVarImpls!.length; i++) { // Add null check
//          final varImpl = cursorImpl.fetchVarImpls![i] as ThinVarImpl; // Add null check & cast
//          cursorImpl.createFetchVar(
//               conn, cursor, typeHandler, usesMetadata, i, varImpl.fetchMetadata! // Add null check
//          );
//       }
//       statement.lastOutputTypeHandler = typeHandler;
//     }

//     // Create Arrow arrays if needed
//     if (cursorImpl.fetchingArrow) {
//         cursorImpl.createArrowArrays();
//     }

//     out_var_impls = cursorImpl.fetchVarImpls?.cast<ThinVarImpl>(); // Add null check & cast
//   }

//   /// Processes the bit vector indicating null/duplicate columns.
//   void _processBitVector(ReadBuffer buf) {
//     num_columns_sent = buf.readUint16();
//     int numBytes = cursorImpl!.numColumns ~/ 8; // Add null check
//     if (cursorImpl!.numColumns % 8 > 0) { // Add null check
//       numBytes += 1;
//     }
//     _getBitVector(buf, numBytes);
//   }

//   /// Processes column data from the buffer based on metadata.
//   dynamic _processColumnData(ReadBuffer buf, ThinVarImpl varImpl, int pos) {
//      final OracleMetadata metadata = (inFetch ? varImpl.fetchMetadata : varImpl.metadata)!; // Add null check
//      final int oraTypeNum = metadata.dbType.oraTypeNum;
//      final int csfrm = metadata.dbType.csfrm;
//      dynamic columnValue;

//      if (varImpl.bypassDecode) {
//        // Treat as RAW if bypassing decode
//        OracleData data = OracleData();
//        buf.readOracleData(metadata, data, fromDbObject: false);
//         if (!data.isNull) {
//            columnValue = convertRawToPython(data.buffer); // Needs specific RAW conversion
//         } else {
//            columnValue = null;
//         }
//      } else if (metadata.bufferSize == 0 && inFetch &&
//          !const {
//            ORA_TYPE_NUM_LONG, ORA_TYPE_NUM_LONG_RAW, ORA_TYPE_NUM_UROWID
//          }.contains(oraTypeNum)) {
//        columnValue = null; // Null by describe
//      } else if (oraTypeNum == ORA_TYPE_NUM_ROWID) {
//         if (!inFetch) {
//             columnValue = buf.readString(CS_FORM_IMPLICIT);
//         } else {
//             int numBytes = buf.readUint8();
//             if (numBytes == 0 || numBytes == TNS_NULL_LENGTH_INDICATOR) {
//                 columnValue = null;
//             } else {
//                 Rowid rowid = Rowid(0,0,0,0); // Assuming Rowid constructor
//                 buf.readRowid(rowid);
//                 columnValue = _encodeRowid(rowid); // Assuming helper exists
//             }
//         }
//      } else if (oraTypeNum == ORA_TYPE_NUM_UROWID) {
//         if (!inFetch) {
//             columnValue = buf.readString(CS_FORM_IMPLICIT);
//         } else {
//             columnValue = buf.readUrowid(); // Assuming ReadBuffer method
//         }
//      } else if (oraTypeNum == ORA_TYPE_NUM_CURSOR) {
//          buf.skipUint8(); // length (fixed)
//          dynamic currentCursor = (!inFetch) ? varImpl.values[pos] : null;
//          columnValue = _createCursorFromDescribe(buf, currentCursor);
//          final childCursorImpl = (columnValue as dynamic/*Cursor*/).impl as BaseThinCursorImpl; // Needs cast
//          childCursorImpl.statement!.cursorId = buf.readUint16(); // Add null check
//          if (inFetch) {
//              childCursorImpl.statement!.isNested = true; // Add null check
//          }
//      } else if (const {
//          ORA_TYPE_NUM_CLOB, ORA_TYPE_NUM_BLOB, ORA_TYPE_NUM_BFILE
//        }.contains(oraTypeNum)) {
//        dynamic currentLob = (cursorImpl!.statement!.isPlsql) ? varImpl.values[pos] : null; // Add null check
//        columnValue = buf.readLobWithLength(connImpl, metadata.dbType, currentLob); // Assuming ReadBuffer method
//      } else if (oraTypeNum == ORA_TYPE_NUM_JSON) {
//         columnValue = buf.readOson(); // Assuming ReadBuffer method
//      } else if (oraTypeNum == ORA_TYPE_NUM_VECTOR) {
//         columnValue = buf.readVector(); // Assuming ReadBuffer method
//      } else if (oraTypeNum == ORA_TYPE_NUM_OBJECT) {
//          final typImpl = metadata.objType as ThinDbObjectTypeImpl?; // Needs cast and null check
//          if (typImpl == null) {
//              columnValue = buf.readXmltype(connImpl); // Assuming ReadBuffer method
//          } else {
//              final objImpl = buf.readDbObject(typImpl); // Assuming ReadBuffer method
//              if (objImpl != null) {
//                  dynamic currentObject = (cursorImpl!.statement!.isPlsql) ? varImpl.values[pos] : null; // Add null check
//                  if (currentObject != null) {
//                      (currentObject as dynamic /*DbObject*/).impl = objImpl; // Needs cast
//                      columnValue = currentObject;
//                  } else {
//                      columnValue = DbObject.fromImpl(objImpl); // Assuming static constructor
//                  }
//              } else {
//                 columnValue = null;
//              }
//          }
//      } else {
//        OracleData data = OracleData();
//        buf.readOracleData(metadata, data, fromDbObject: false);
//        if (metadata.dbType.csfrm == CS_FORM_NCHAR) {
//          buf.caps.checkNCharsetId();
//        }
//        if (cursorImpl!.fetchingArrow) { // Add null check
//          // convert_oracle_data_to_arrow(metadata, varImpl.metadata!, data, varImpl.arrowArray!); // Add null checks
//          throw UnimplementedError("Arrow conversion not fully translated");
//        } else {
//           columnValue = convertOracleDataToPython(
//               metadata, varImpl.metadata!, data, varImpl.encodingErrors, false); // Add null check
//        }
//      }

//      if (!inFetch) {
//        int actualNumBytes = buf.readInt32();
//        if (actualNumBytes < 0 && oraTypeNum == ORA_TYPE_NUM_BOOLEAN) {
//          columnValue = null;
//        } else if (actualNumBytes != 0 && columnValue != null) {
//          String unitType = (columnValue is Uint8List) ? "bytes" : "characters";
//          int colValueLen = (columnValue is Uint8List) ? columnValue.length : (columnValue as String).length;
//           throw _createOracleException(
//               dpyCode: ERR_COLUMN_TRUNCATED,
//               message: 'Column truncated', // Args need formatting
//               // col_value_len: colValueLen,
//               // unit: unitType,
//               // actual_len: actualNumBytes,
//           );
//        }
//      } else if (oraTypeNum == ORA_TYPE_NUM_LONG || oraTypeNum == ORA_TYPE_NUM_LONG_RAW) {
//        buf.skipInt32(); // null indicator
//        buf.skipUint32(); // return code
//      }
//      return columnValue;
//    }


//   /// Processes describe information received from the server.
//   void _processDescribeInfo(ReadBuffer buf, dynamic cursor, BaseThinCursorImpl cursorImpl) {
//      final stmt = cursorImpl.statement!; // Assert non-null
//      List<ThinVarImpl>? prevFetchVarImpls = stmt.fetchVarImpls?.cast<ThinVarImpl>(); // Add null check and cast

//      buf.skipUint32(); // max row size
//      cursorImpl.numColumns = buf.readUint32();
//      cursorImpl.initFetchVars(cursorImpl.numColumns); // Assuming method exists
//      if (cursorImpl.numColumns > 0) {
//        buf.skipUint8(); // Skip array header byte if columns exist
//      }

//      bool usesMetadata = false; // Placeholder, determined by handler signature
//      final typeHandler = cursorImpl.getOutputTypeHandler(usesMetadata);
//      final conn = cursor.connection;

//      for (int i = 0; i < cursorImpl.numColumns; i++) {
//        final metadata = _processMetadata(buf); // Assuming _processMetadata is implemented
//        if (prevFetchVarImpls != null && i < prevFetchVarImpls.length) {
//           _adjustMetadata(prevFetchVarImpls[i], metadata);
//        }
//        if (const {
//              ORA_TYPE_NUM_BLOB, ORA_TYPE_NUM_CLOB, ORA_TYPE_NUM_JSON, ORA_TYPE_NUM_VECTOR
//            }.contains(metadata.dbType.oraTypeNum)) {
//          stmt.requiresDefine = true;
//          stmt.noPrefetch = true;
//        }
//        cursorImpl.createFetchVar(conn, cursor, typeHandler, usesMetadata, i, metadata); // Assuming method exists
//      }

//      int numBytes = buf.readUint32(); // current date length
//      if (numBytes > 0) buf.skipRawBytesChunked();
//      buf.skipUint32(); // dcbflag
//      buf.skipUint32(); // dcbmdbz
//      buf.skipUint32(); // dcbmnpr
//      buf.skipUint32(); // dcbmxpr
//      numBytes = buf.readUint32(); // dcbqcky length
//      if (numBytes > 0) buf.skipRawBytesChunked();

//      // Update statement with processed info
//      stmt.fetchMetadata = cursorImpl.fetchMetadata;
//      stmt.fetchVars = cursorImpl.fetchVars;
//      stmt.fetchVarImpls = cursorImpl.fetchVarImpls;
//      stmt.numColumns = cursorImpl.numColumns;
//      stmt.lastOutputTypeHandler = typeHandler;
//    }


//   /// Processes the IO vector received during PL/SQL execution.
//   void _processIoVector(ReadBuffer buf) {
//      buf.skipUint8(); // flag
//      buf.skipUint16(); // num requests
//      buf.skipUint32(); // iteration number
//      /*int numIters =*/ buf.readUint32(); // num iters this time
//      buf.skipUint16(); // uac buffer length
//      int numBytes = buf.readUint16(); // bit vector length
//      if (numBytes > 0) buf.skipBytes(numBytes);
//      numBytes = buf.readUint16(); // rowid length
//      if (numBytes > 0) buf.skipBytes(numBytes);

//      out_var_impls = [];
//      if (cursorImpl?.statement?.bindInfoList != null) { // Add null checks
//         for (final bindInfo in cursorImpl!.statement!.bindInfoList!) { // Add null checks
//             bindInfo.bindDir = buf.readUint8();
//             if (bindInfo.bindDir != TNS_BIND_DIR_INPUT) {
//                 if (bindInfo.bindVarImpl != null) {
//                     out_var_impls!.add(bindInfo.bindVarImpl as ThinVarImpl); // Needs cast
//                 }
//             }
//         }
//      }
//   }

//   /// Processes an implicit result set message.
//   void _processImplicitResult(ReadBuffer buf) {
//     cursorImpl!.implicitResultsets = []; // Add null check
//     int numResults = buf.readUint32();
//     for (int i = 0; i < numResults; i++) {
//       int numBytes = buf.readUint8();
//       buf.skipBytes(numBytes); // Skip unknown bytes
//       final childCursor = _createCursorFromDescribe(buf);
//       final childCursorImpl = (childCursor as dynamic/*Cursor*/).impl as BaseThinCursorImpl; // Needs cast
//       childCursorImpl.statement!.cursorId = buf.readUint16(); // Add null check
//       cursorImpl!.implicitResultsets!.add(childCursor); // Add null check
//     }
//   }

//   /// Processes a row data message.
//   void _processRowData(ReadBuffer buf) {
//     if (out_var_impls == null) return; // Should not happen if IO vector was processed

//     for (int i = 0; i < out_var_impls!.length; i++) {
//       final varImpl = out_var_impls![i];
//       if (varImpl.isArray) {
//         varImpl.numElementsInArray = buf.readUint32();
//         for (int pos = 0; pos < varImpl.numElementsInArray; pos++) {
//           final value = _processColumnData(buf, varImpl, pos);
//           varImpl.values[pos] = value; // Assuming values is List<dynamic>
//         }
//       } else if (cursorImpl?.statement?.isReturning ?? false) { // Add null checks
//         int numRows = buf.readUint32();
//         List<dynamic> values = List<dynamic>.filled(numRows, null);
//         for (int j = 0; j < numRows; j++) {
//            values[j] = _processColumnData(buf, varImpl, j);
//         }
//         varImpl.values[row_index] = values; // Store the list of returned values
//         varImpl.hasReturnedData = true;
//       } else if (cursorImpl?.fetchingArrow ?? false) { // Add null check
//          if (_isDuplicateData(i)) {
//             // varImpl.arrowArray!.appendLastValue(varImpl.lastArrowArray); // Add null checks
//             throw UnimplementedError("Arrow duplicate handling not translated");
//          } else {
//            _processColumnData(buf, varImpl, row_index);
//          }
//          varImpl.lastArrowArray = null;
//       } else if (_isDuplicateData(i)) {
//          dynamic value;
//          if (row_index == 0 && varImpl.outconverter != null) {
//             value = varImpl.lastRawValue;
//          } else {
//             value = varImpl.values[cursorImpl!.lastRowIndex]; // Add null check
//          }
//          varImpl.values[row_index] = value;
//       } else {
//         final value = _processColumnData(buf, varImpl, row_index);
//         varImpl.values[row_index] = value;
//       }
//     }
//     row_index++;
//     if (inFetch) {
//       cursorImpl!.lastRowIndex = row_index - 1; // Add null check
//       cursorImpl!.bufferRowcount = row_index; // Add null check
//       // Reset bit vector pointer equivalent
//       // bit_vector = NULL; // Not directly applicable in Dart
//       bitVectorBuf = null; // Clear the buffer instead
//     }
//   }

//   /// Processes a row header message.
//   void _processRowHeader(ReadBuffer buf) {
//     buf.skipUint8(); // flags
//     buf.skipUint16(); // num requests
//     buf.skipUint32(); // iteration number
//     buf.skipUint32(); // num iters
//     buf.skipUint16(); // buffer length
//     int numBytes = buf.readUint32();
//     if (numBytes > 0) {
//       buf.skipUint8(); // skip repeated length
//       _getBitVector(buf, numBytes);
//     }
//     numBytes = buf.readUint32();
//     if (numBytes > 0) {
//       buf.skipRawBytesChunked(); // rxhrid
//     }
//   }
// }

// // Helper to encode Rowid (needs implementation based on Rowid structure)
// String _encodeRowid(Rowid rowid) {
//   // ... implementation based on _convert_base64 logic ...
//   throw UnimplementedError("Rowid encoding not implemented");
// }
