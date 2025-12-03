// Core packet helpers for the thin protocol.

import 'dart:typed_data';

import '../../exceptions.dart';
import 'constants.dart';

/// Basic write buffer that grows as bytes are appended.
class WriteBuffer {
  final BytesBuilder _builder = BytesBuilder(copyOnWrite: false);

  void writeUint8(int value) {
    _builder.addByte(value & 0xFF);
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

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
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
  int readUint16() => _read(2, (bd) => bd.getUint16(0, Endian.big));
  int readUint32() => _read(4, (bd) => bd.getUint32(0, Endian.big));
  int readUint64() => _read(8, (bd) => bd.getUint64(0, Endian.big));
  int readInt16() => _read(2, (bd) => bd.getInt16(0, Endian.big));
  int readInt32() => _read(4, (bd) => bd.getInt32(0, Endian.big));

  Uint8List readBytes(int length) => _slice(length);
  void skipBytes(int length) => _skip(length);

  /// Reads a server rowid tuple.
  Rowid readRowid() {
    final rba = readUint32();
    final partitionId = readUint16();
    final blockNum = readUint32();
    final slotNum = readUint16();
    return Rowid(
      rba: rba,
      partitionId: partitionId,
      blockNum: blockNum,
      slotNum: slotNum,
    );
  }

  /// Skip a byte-length-prefixed raw payload; if the length is the long
  /// length indicator, consume chunked segments until a zero-length terminator.
  void skipRawBytesChunked() {
    final length = readUint8();
    if (length != TNS_LONG_LENGTH_INDICATOR) {
      skipBytes(length);
      return;
    }
    while (true) {
      final chunkLen = readUint32();
      if (chunkLen == 0) break;
      skipBytes(chunkLen);
    }
  }

  /// Read a raw payload with a leading length byte or chunked encoding.
  Uint8List readBytesWithLength() {
    final length = readUint8();
    if (length != TNS_LONG_LENGTH_INDICATOR) {
      return readBytes(length);
    }
    final chunks = <int>[];
    while (true) {
      final chunkLen = readUint32();
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
    final view =
        ByteData.sublistView(_data, _pos, _pos + length); // cheap slice view
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

/// Representation of a network packet header and payload.
class Packet {
  Packet({
    required this.packetSize,
    required this.packetType,
    required this.packetFlags,
    required this.buf,
  });

  /// Total size of the packet reported by the network layer.
  final int packetSize;

  /// TNS packet type (CONNECT, ACCEPT, DATA, ...).
  final int packetType;

  /// Flags reported on the packet header.
  final int packetFlags;

  /// Raw bytes for the entire packet, header first.
  final Uint8List buf;

  /// Returns `true` if the packet marks the end of a response.
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

/// Oracle rowid components used by the protocol layer.
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

// Packet header starts with 8 bytes in the Python implementation.
const int packetHeaderSize = 8;

int _readUint16BE(Uint8List data, int offset) {
  final view = ByteData.sublistView(data, offset, offset + 2);
  return view.getUint16(0, Endian.big);
}

int _readUint32BE(Uint8List data, int offset) {
  final view = ByteData.sublistView(data, offset, offset + 4);
  return view.getUint32(0, Endian.big);
}
