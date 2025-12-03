import 'dart:typed_data';

import '../constants.dart';
import '../packet.dart';
import 'base.dart';

/// Data types message for establishing data type formats with the server.
/// This message is sent after the protocol message during connection setup.
class DataTypesMessage extends Message {
  
  /// Builds the data types request packet to send to the server.
  Uint8List buildRequest() {
    final body = WriteBuffer();
    
    // Write message type
    body.writeUint8(TNS_MSG_TYPE_DATA_TYPES);
    
    // Write character set and capabilities
    body.writeUint16LE(TNS_CHARSET_UTF8);
    body.writeUint16LE(TNS_CHARSET_UTF8);
    body.writeUint8(TNS_ENCODING_MULTI_BYTE | TNS_ENCODING_CONV_LENGTH);
    body.writeBytesWithLength(connImpl.capabilities.compileCaps);
    body.writeBytesWithLength(connImpl.capabilities.runtimeCaps);
    
    // Write data types array
    for (final entry in _dataTypes) {
      if (entry[0] == 0) break;
      body.writeUint16(entry[0]); // data_type
      body.writeUint16(entry[1]); // conv_data_type
      body.writeUint16(entry[2]); // representation
      body.writeUint16(0);        // padding
    }
    body.writeUint16(0); // terminator
    
    final bodyBytes = body.toBytes();
    return buildTnsPacket(
      bodyBytes: bodyBytes,
      packetType: TNS_PACKET_TYPE_DATA,
      includeDataFlags: true,
      useLargeSdu: useLargeSdu,
    );
  }

  @override
  void processMessage(ReadBuffer buf, int messageType) {
    if (messageType == TNS_MSG_TYPE_DATA_TYPES) {
      _processDataTypes(buf);
      endOfResponse = true;
    } else {
      super.processMessage(buf, messageType);
    }
  }

  void _processDataTypes(ReadBuffer buf) {
    // Read and skip data type definitions from server
    while (true) {
      final dataType = buf.readUint16();
      if (dataType == 0) break;
      final convDataType = buf.readUint16();
      if (convDataType != 0) {
        buf.skipBytes(4);
      }
    }
    if (!connImpl.capabilities.supportsEndOfResponse) {
      endOfResponse = true;
    }
  }
}

// Data type definitions for Oracle protocol negotiation
// Format: [data_type, conv_data_type, representation]
const List<List<int>> _dataTypes = [
  [ORA_TYPE_NUM_VARCHAR, ORA_TYPE_NUM_VARCHAR, TNS_TYPE_REP_UNIVERSAL],
  [ORA_TYPE_NUM_NUMBER, ORA_TYPE_NUM_NUMBER, TNS_TYPE_REP_ORACLE],
  [ORA_TYPE_NUM_LONG, ORA_TYPE_NUM_LONG, TNS_TYPE_REP_UNIVERSAL],
  [ORA_TYPE_NUM_DATE, ORA_TYPE_NUM_DATE, TNS_TYPE_REP_ORACLE],
  [ORA_TYPE_NUM_RAW, ORA_TYPE_NUM_RAW, TNS_TYPE_REP_UNIVERSAL],
  [ORA_TYPE_NUM_LONG_RAW, ORA_TYPE_NUM_LONG_RAW, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_UB2, TNS_DATA_TYPE_UB2, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_UB4, TNS_DATA_TYPE_UB4, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_SB1, TNS_DATA_TYPE_SB1, TNS_TYPE_REP_ORACLE],
  [TNS_DATA_TYPE_SB2, TNS_DATA_TYPE_SB2, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_SB4, TNS_DATA_TYPE_SB4, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_SWORD, TNS_DATA_TYPE_SWORD, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_UWORD, TNS_DATA_TYPE_UWORD, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_PTRB, TNS_DATA_TYPE_PTRB, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_PTRW, TNS_DATA_TYPE_PTRW, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_TIDDEF, TNS_DATA_TYPE_TIDDEF, TNS_TYPE_REP_UNIVERSAL],
  [ORA_TYPE_NUM_ROWID, ORA_TYPE_NUM_ROWID, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_AMS, TNS_DATA_TYPE_AMS, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_BRN, TNS_DATA_TYPE_BRN, TNS_TYPE_REP_UNIVERSAL],
  [TNS_DATA_TYPE_CWD, TNS_DATA_TYPE_CWD, TNS_TYPE_REP_UNIVERSAL],
  [0, 0, 0], // terminator
];

// TNS Data type constants (subset needed for data types message)
const int TNS_DATA_TYPE_UB2 = 25;
const int TNS_DATA_TYPE_UB4 = 26;
const int TNS_DATA_TYPE_SB1 = 27;
const int TNS_DATA_TYPE_SB2 = 28;
const int TNS_DATA_TYPE_SB4 = 29;
const int TNS_DATA_TYPE_SWORD = 30;
const int TNS_DATA_TYPE_UWORD = 31;
const int TNS_DATA_TYPE_PTRB = 32;
const int TNS_DATA_TYPE_PTRW = 33;
const int TNS_DATA_TYPE_TIDDEF = 10;
const int TNS_DATA_TYPE_AMS = 40;
const int TNS_DATA_TYPE_BRN = 41;
const int TNS_DATA_TYPE_CWD = 117;

// Type representations
const int TNS_TYPE_REP_UNIVERSAL = 1;
const int TNS_TYPE_REP_ORACLE = 10;

// Oracle type numbers (should eventually be in constants.dart)
const int ORA_TYPE_NUM_VARCHAR = 1;
const int ORA_TYPE_NUM_NUMBER = 2;
const int ORA_TYPE_NUM_LONG = 8;
const int ORA_TYPE_NUM_DATE = 12;
const int ORA_TYPE_NUM_RAW = 23;
const int ORA_TYPE_NUM_LONG_RAW = 24;
const int ORA_TYPE_NUM_ROWID = 11;

// WriteBuffer extension for little-endian writes
extension _WriteBufferLE on WriteBuffer {
  void writeUint16LE(int value) {
    final data = ByteData(2)..setUint16(0, value & 0xFFFF, Endian.little);
    writeBytes(data.buffer.asUint8List());
  }
}
