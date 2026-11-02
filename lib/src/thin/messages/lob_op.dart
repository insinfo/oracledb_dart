import 'dart:typed_data';

import '../buffer.dart';
import '../connection_impl.dart';
import '../constants.dart';
import 'base.dart';

/// Locator and metadata of a LOB, shared by the LOB operation messages.
class LobLocator {
  LobLocator(this.oraTypeNum, this.csfrm, this.locator,
      {this.size = 0, this.chunkSize = 0, this.hasMetadata = false});

  final int oraTypeNum;
  final int csfrm;
  Uint8List locator;
  int size;
  int chunkSize;
  bool hasMetadata;

  bool get isBinary =>
      oraTypeNum == ORA_TYPE_NUM_BLOB || oraTypeNum == ORA_TYPE_NUM_BFILE;

  /// CLOBs are stored in UTF-16 when the database character set has a
  /// variable length (such as AL32UTF8), as do all NCLOBs.
  bool get usesUtf16 =>
      csfrm == CS_FORM_NCHAR ||
      (locator.length > TNS_LOB_LOC_OFFSET_FLAG_3 &&
          locator[TNS_LOB_LOC_OFFSET_FLAG_3] &
                  TNS_LOB_LOC_FLAGS_VAR_LENGTH_CHARSET !=
              0);

  bool get isTemporary =>
      locator.length > TNS_LOB_LOC_OFFSET_FLAG_4 &&
      (locator[TNS_LOB_LOC_OFFSET_FLAG_1] & TNS_LOB_LOC_FLAGS_ABSTRACT != 0 ||
          locator[TNS_LOB_LOC_OFFSET_FLAG_4] & TNS_LOB_LOC_FLAGS_TEMP != 0);
}

/// Performs an operation on a LOB (read, write, trim, get length, ...).
class LobOpMessage extends Message {
  LobOpMessage(super.conn, this.operation, this.lob) {
    functionCode = TNS_FUNC_LOB_OP;
  }

  final int operation;
  final LobLocator? lob;
  int sourceOffset = 0;
  int destOffset = 0;
  int destLength = 0;
  int amount = 0;
  bool sendAmount = false;
  bool boolFlag = false;

  /// Data to write, or the data read (raw bytes as stored by the server).
  Uint8List? data;

  @override
  void processMessage(ReadBuffer buf, int messageType) {
    if (messageType == TNS_MSG_TYPE_LOB_DATA) {
      data = buf.readBytes() ?? Uint8List(0);
    } else {
      super.processMessage(buf, messageType);
    }
  }

  @override
  void processReturnParameters(ReadBuffer buf) {
    final lob = this.lob;
    if (lob != null) {
      lob.locator = Uint8List.fromList(buf.readRawBytes(lob.locator.length));
    }
    if (operation == TNS_LOB_OP_CREATE_TEMP) {
      buf.skipUB2(); // character set
      buf.skipUB1(); // trailing flags
    } else if (sendAmount) {
      amount = buf.readSB8();
    }
    if (operation == TNS_LOB_OP_IS_OPEN ||
        operation == TNS_LOB_OP_FILE_EXISTS ||
        operation == TNS_LOB_OP_FILE_ISOPEN) {
      boolFlag = buf.readUB1() > 0;
    }
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final lob = this.lob;
    writeFunctionCode(buf);
    if (lob == null) {
      buf.writeUint8(0); // source pointer
      buf.writeUB4(0); // source length
    } else {
      buf.writeUint8(1); // source pointer
      buf.writeUB4(lob.locator.length);
    }
    buf.writeUint8(0); // dest pointer
    buf.writeUB4(destLength);
    buf.writeUB4(0); // short source offset
    buf.writeUB4(0); // short dest offset
    buf.writeUint8(operation == TNS_LOB_OP_CREATE_TEMP ? 1 : 0); // charset
    buf.writeUint8(0); // pointer (short amount)
    final nullLob = operation == TNS_LOB_OP_CREATE_TEMP ||
        operation == TNS_LOB_OP_IS_OPEN ||
        operation == TNS_LOB_OP_FILE_EXISTS ||
        operation == TNS_LOB_OP_FILE_ISOPEN;
    buf.writeUint8(nullLob ? 1 : 0); // pointer (NULL LOB)
    buf.writeUB4(operation);
    buf.writeUint8(0); // pointer (SCN array)
    buf.writeUint8(0); // SCN array length
    buf.writeUB8(sourceOffset);
    buf.writeUB8(destOffset);
    buf.writeUint8(sendAmount ? 1 : 0); // pointer (amount)
    for (var i = 0; i < 3; i++) {
      buf.writeUint16BE(0); // array LOB (not used)
    }
    if (lob != null) buf.writeRaw(lob.locator);
    if (operation == TNS_LOB_OP_CREATE_TEMP) {
      buf.writeUB4(
          lob!.csfrm == CS_FORM_NCHAR ? TNS_CHARSET_UTF16 : TNS_CHARSET_UTF8);
    }
    final data = this.data;
    if (data != null) {
      buf.writeUint8(TNS_MSG_TYPE_LOB_DATA);
      buf.writeBytesWithLength(data);
    }
    if (sendAmount) buf.writeUB8(amount);
  }
}

/// Writes the piggyback that frees the temporary LOBs released by the
/// application.
void writeFreeTempLobsPiggyback(Message message, WriteBuffer buf) {
  final ThinConnImpl conn = message.conn;
  message.writePiggybackCode(buf, TNS_FUNC_LOB_OP);
  buf.writeUint8(1); // pointer
  buf.writeUB4(conn.tempLobsTotalSize);
  buf.writeUint8(0); // dest lob locator
  buf.writeUB4(0);
  buf.writeUB4(0); // source lob locator
  buf.writeUB4(0);
  buf.writeUint8(0); // source lob offset
  buf.writeUint8(0); // dest lob offset
  buf.writeUint8(0); // charset
  buf.writeUB4(TNS_LOB_OP_FREE_TEMP | TNS_LOB_OP_ARRAY);
  buf.writeUint8(0); // scn
  buf.writeUB4(0); // losbscn
  buf.writeUB8(0); // lobscnl
  buf.writeUB8(0);
  buf.writeUint8(0);
  // array lob fields
  buf.writeUint8(0);
  buf.writeUB4(0);
  buf.writeUint8(0);
  buf.writeUB4(0);
  buf.writeUint8(0);
  buf.writeUB4(0);
  for (final locator in conn.tempLobsToClose) {
    buf.writeRaw(locator);
  }
  conn.tempLobsToClose.clear();
  conn.tempLobsTotalSize = 0;
}
