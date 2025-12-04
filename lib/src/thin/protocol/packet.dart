// Arquivo: \src\thin\protocol\packet.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../exceptions.dart';
import 'constants.dart';

/// Basic write buffer that grows as bytes are appended.
class WriteBuffer {
  final BytesBuilder _builder = BytesBuilder();

  void writeUint8(int value) {
    _builder.addByte(value & 0xFF);
  }

  void writeUint16LE(int value) {
    final data = ByteData(2)..setUint16(0, value & 0xFFFF, Endian.little);
    writeBytes(data.buffer.asUint8List());
  }

  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value & 0xFFFF, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeUint64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  /// Writes a 32-bit integer in Oracle's universal format (variable length).
  void writeUB4(int value) {
    if (value == 0) {
      writeUint8(0);
    } else if (value <= 0xFF) {
      writeUint8(1);
      writeUint8(value);
    } else if (value <= 0xFFFF) {
      writeUint8(2);
      writeUint16(value);
    } else {
      writeUint8(4);
      writeUint32(value);
    }
  }

  /// Writes a 16-bit integer in Oracle's universal format (variable length).
  void writeUB2(int value) {
    if (value == 0) {
      writeUint8(0);
    } else if (value <= 0xFF) {
      writeUint8(1);
      writeUint8(value);
    } else {
      writeUint8(2);
      writeUint16(value);
    }
  }

  /// Writes a 64-bit integer in Oracle's universal format (variable length).
  void writeUB8(int value) {
    if (value == 0) {
      writeUint8(0);
    } else if (value <= 0xFF) {
      writeUint8(1);
      writeUint8(value);
    } else if (value <= 0xFFFF) {
      writeUint8(2);
      writeUint16(value);
    } else if (value <= 0xFFFFFFFF) {
      writeUint8(4);
      writeUint32(value);
    } else {
      writeUint8(8);
      writeUint64(value);
    }
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  /// Writes bytes prefixed by their length in Oracle raw format (UB1 or chunked).
  void writeBytesWithLength(List<int> bytes) {
    if (bytes.isEmpty) {
      writeUint8(0);
      return;
    }
    if (bytes.length < TNS_LONG_LENGTH_INDICATOR) {
      writeUint8(bytes.length);
      writeBytes(bytes);
      return;
    }
    writeUint8(TNS_LONG_LENGTH_INDICATOR);
    var offset = 0;
    while (offset < bytes.length) {
      final chunkLen = min(0xFFFF, bytes.length - offset);
      writeUB4(chunkLen);
      writeBytes(bytes.sublist(offset, offset + chunkLen));
      offset += chunkLen;
    }
    writeUB4(0);
  }

  Uint8List toBytes() => _builder.toBytes();
}

/// Basic read buffer with big-endian helpers mirroring python-oracledb.
class ReadBuffer {
  ReadBuffer(Uint8List data) : _data = data;

  final Uint8List _data;
  int _pos = 0;

  bool get isEOF => _pos >= _data.length;
  int get remaining => _data.length - _pos;

  int readUint8() => _read(1, (bd) => bd.getUint8(0));
  
  /// Peeks the next byte without advancing the position.
  int peekUint8() {
    if (isEOF) {
      throw createOracleException(
        dpyCode: ERR_UNEXPECTED_END_OF_DATA,
        message: 'unexpected end of data while peeking',
      );
    }
    return _data[_pos];
  }

  /// Visualiza bytes sem avançar o cursor (útil para logs de debug).
  Uint8List peekBytes(int length) {
    final safeLen = min(length, remaining);
    return Uint8List.sublistView(_data, _pos, _pos + safeLen);
  }

  int readUint16() => _read(2, (bd) => bd.getUint16(0, Endian.big));
  int readUint16LE() => _read(2, (bd) => bd.getUint16(0, Endian.little));
  int readUint32() => _read(4, (bd) => bd.getUint32(0, Endian.big));
  int readUint64() => _read(8, (bd) => bd.getUint64(0, Endian.big));
  int readInt16() => _read(2, (bd) => bd.getInt16(0, Endian.big));
  int readInt32() => _read(4, (bd) => bd.getInt32(0, Endian.big));

  /// Internal helper to read variable length integer bytes.
  int _readVarInt(int length) {
    if (length == 0) return 0;
    int value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | readUint8();
    }
    return value;
  }

  /// Internal helper to read the length byte for UB types.
  int _readLengthByte() {
    final byte = readUint8();
    if ((byte & 0x80) != 0) {
      return byte & 0x7F; // Negative handling if needed, for now just mask
    }
    return byte;
  }

  /// Reads an unsigned 16-bit integer in Oracle's universal format (variable length).
  int readUB2() {
    final length = _readLengthByte();
    return _readVarInt(length);
  }

  /// Reads an unsigned 32-bit integer in Oracle's universal format (variable length).
  int readUB4() {
    final length = _readLengthByte();
    return _readVarInt(length);
  }

  /// Reads an unsigned 64-bit integer in Oracle's universal format (variable length).
  int readUB8() {
    final length = _readLengthByte();
    return _readVarInt(length);
  }

  /// Skips an unsigned 32-bit integer in Oracle's universal format.
  void skipUB4() {
    final length = _readLengthByte();
    if (length > 0) {
      skipBytes(length);
    }
  }

  String readNullTerminatedString({Encoding encoding = utf8}) {
    final startPos = _pos;
    while (_pos < _data.length && _data[_pos] != 0) {
      _pos++;
    }
    final strBytes = _data.sublist(startPos, _pos);
    if (_pos < _data.length) {
      _pos++; // Skip the null terminator
    }
    return encoding.decode(strBytes);
  }

  Uint8List readBytes(int length) => _slice(length);
  void skipBytes(int length) => _skip(length);

  void savePoint() {}

  /// Reads a string where the outer size is encoded as UB4.
  /// If size > 0, it delegates to _readOracleString to handle internal format.
  String readStringWithLength({Encoding encoding = utf8}) {
    // Python usa UB4 (comprimento variável) para o tamanho externo
    final outerLength = readUB4();
    if (outerLength == 0) {
      return '';
    }
    final bytes = _readRawBytesChunked();
    if (bytes == null) {
      return '';
    }
    if (bytes.length != outerLength) {
      throw createOracleException(
        dpyCode: ERR_UNEXPECTED_END_OF_DATA,
        message:
            'length-prefixed string mismatch: declared $outerLength bytes, read ${bytes.length}',
      );
    }
    return encoding.decode(bytes);
  }

  /// Reads a server rowid tuple using Variable Integers (UB).
  Rowid readRowid() {
    final rba = readUB4();
    final partitionId = readUB2();
    skipUint8(); // Python driver skips a byte here (ub1)
    final blockNum = readUB4();
    final slotNum = readUB2();
    return Rowid(
      rba: rba,
      partitionId: partitionId,
      blockNum: blockNum,
      slotNum: slotNum,
    );
  }

  void skipRawBytesChunked() {
    final length = readUint8();
    if (length != TNS_LONG_LENGTH_INDICATOR) {
      skipBytes(length);
      return;
    }
    while (true) {
      final chunkLen = readUB4();
      if (chunkLen == 0) break;
      skipBytes(chunkLen);
    }
  }

  /// Reads bytes where the outer length is encoded as UB4.
  Uint8List readBytesWithLength() {
    // Python usa UB4 (comprimento variável) para o tamanho externo
    final outerLength = readUB4();
    if (outerLength == 0) {
      return Uint8List(0);
    }
    final bytes = _readRawBytesChunked();
    if (bytes == null) {
      return Uint8List(0);
    }
    if (bytes.length != outerLength) {
      throw createOracleException(
        dpyCode: ERR_UNEXPECTED_END_OF_DATA,
        message:
            'length-prefixed bytes mismatch: declared $outerLength bytes, read ${bytes.length}',
      );
    }
    return bytes;
  }

  Uint8List? readBytesRawOrNull() {
    return _readRawBytesChunked();
  }

  /// Internal helper: Reads raw bytes with a leading length byte (UB1) or chunked encoding.
  Uint8List? _readRawBytesChunked() {
    final length = readUint8();
    if (length == 0 || length == TNS_NULL_LENGTH_INDICATOR) {
      return null;
    }
    if (length != TNS_LONG_LENGTH_INDICATOR) {
      return readBytes(length);
    }
    final chunks = <int>[];
    while (true) {
      final chunkLen = readUB4();
      if (chunkLen == 0) break;
      chunks.addAll(readBytes(chunkLen));
    }
    return Uint8List.fromList(chunks);
  }

  void skipUint8() => _skip(1);
  void skipUint16() => _skip(2);
  void skipUint32() => _skip(4);

  T _read<T>(int length, T Function(ByteData) reader) {
    if (remaining < length) {
      throw createOracleException(
        dpyCode: ERR_UNEXPECTED_END_OF_DATA,
        message:
            'unexpected end of data: wanted $length bytes, only $remaining left',
      );
    }
    final view = ByteData.sublistView(_data, _pos, _pos + length);
    _pos += length;
    return reader(view);
  }

  Uint8List _slice(int length) {
    if (remaining < length) {
      throw createOracleException(
        dpyCode: ERR_UNEXPECTED_END_OF_DATA,
        message:
            'unexpected end of data: wanted $length bytes, only $remaining left',
      );
    }
    final result = Uint8List.sublistView(_data, _pos, _pos + length);
    _pos += length;
    return result;
  }

  void _skip(int length) {
    if (remaining < length) {
      throw createOracleException(
        dpyCode: ERR_UNEXPECTED_END_OF_DATA,
        message:
            'unexpected end of data: wanted $length bytes, only $remaining left',
      );
    }
    _pos += length;
  }
}

class Packet {
  Packet({
    required this.packetSize,
    required this.packetType,
    required this.packetFlags,
    required this.buf,
  });

  final int packetSize;
  final int packetType;
  final int packetFlags;
  final Uint8List buf;

  bool get hasEndOfResponse {
    if (buf.length < packetHeaderSize + 2) return false;

    final flags = _readUint16BE(buf, packetHeaderSize);
    if ((flags & TNS_DATA_FLAGS_END_OF_RESPONSE) != 0) {
      return true;
    }

    final eorMarkerOffset = packetHeaderSize + 2;
    return packetSize == packetHeaderSize + 3 &&
        buf.length > eorMarkerOffset &&
        buf[eorMarkerOffset] == TNS_MSG_TYPE_END_OF_RESPONSE;
  }
}

class Rowid {
  const Rowid({
    required this.rba,
    required this.partitionId,
    required this.blockNum,
    required this.slotNum,
  });
  final int rba;
  final int partitionId;
  final int blockNum;
  final int slotNum;
}

const int packetHeaderSize = 8;

Uint8List buildTnsPacket({
  required Uint8List bodyBytes,
  required int packetType,
  int packetFlags = 0,
  bool includeDataFlags = false,
  bool useLargeSdu = false,
}) {
  final dataFlagsLen = includeDataFlags ? 2 : 0;
  final totalLen = packetHeaderSize + dataFlagsLen + bodyBytes.length;
  final packet = Uint8List(totalLen);
  final header = ByteData.sublistView(packet, 0, packetHeaderSize);
  if (useLargeSdu) {
    header.setUint32(0, totalLen, Endian.big);
  } else {
    header.setUint16(0, totalLen, Endian.big);
    header.setUint16(2, 0, Endian.big);
  }
  header.setUint8(4, packetType);
  header.setUint8(5, packetFlags);
  header.setUint16(6, 0, Endian.big);
  var offset = packetHeaderSize;
  if (includeDataFlags) {
    packet[offset] = 0;
    packet[offset + 1] = 0;
    offset += 2;
  }
  packet.setRange(offset, totalLen, bodyBytes);
  return packet;
}

int _readUint16BE(Uint8List data, int offset) {
  final view = ByteData.sublistView(data, offset, offset + 2);
  return view.getUint16(0, Endian.big);
}
