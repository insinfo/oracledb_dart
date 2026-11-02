import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import 'capabilities.dart';
import 'constants.dart';

const int packetHeaderSize = 8;

const Utf8Decoder _utf8Decoder = Utf8Decoder(allowMalformed: true);

/// Thrown when the response being parsed requires more data than has been
/// received so far. The protocol waits for more packets, restores the read
/// position to the last save point and processes the message again.
class OutOfPackets implements Exception {
  const OutOfPackets();
}

const OutOfPackets _outOfPackets = OutOfPackets();

/// Buffer holding the payload of all of the data packets received for a
/// response, stored contiguously so that values never straddle packets.
class ReadBuffer {
  ReadBuffer(this.caps);

  final Capabilities caps;
  Uint8List data = Uint8List(32 * 1024);
  int _size = 0;
  int pos = 0;
  int _savedPos = 0;

  /// Scratch buffer used to assemble values sent in chunks (long values).
  Uint8List _chunkBuf = Uint8List(32 * 1024);

  /// The buffer and offset of the bytes returned by [readBytesRef].
  Uint8List refData = Uint8List(0);
  int refOffset = 0;

  int get size => _size;
  int get bytesLeft => _size - pos;

  void reset() {
    _size = 0;
    pos = 0;
    _savedPos = 0;
  }

  /// Discards the data before the save point (already processed messages)
  /// so that the buffer does not grow while waiting for more packets.
  void compactToSavePoint() {
    if (_savedPos == 0) return;
    final remaining = _size - _savedPos;
    if (remaining > 0) data.setRange(0, remaining, data, _savedPos);
    _size = remaining;
    pos -= _savedPos;
    _savedPos = 0;
  }

  void append(Uint8List src, int start, int end) {
    final n = end - start;
    if (_size + n > data.length) {
      var newLen = data.length * 2;
      while (newLen < _size + n) {
        newLen *= 2;
      }
      final newData = Uint8List(newLen)..setRange(0, _size, data);
      data = newData;
    }
    data.setRange(_size, _size + n, src, start);
    _size += n;
  }

  void savePoint() => _savedPos = pos;
  void restorePoint() => pos = _savedPos;

  @pragma('vm:prefer-inline')
  void _ensure(int n) {
    if (pos + n > _size) throw _outOfPackets;
  }

  @pragma('vm:prefer-inline')
  int readUint8() {
    if (pos >= _size) throw _outOfPackets;
    return data[pos++];
  }

  @pragma('vm:prefer-inline')
  int readUB1() => readUint8();

  int readSB1() {
    final v = readUint8();
    return v >= 128 ? v - 256 : v;
  }

  int readUint16BE() {
    _ensure(2);
    final d = data, p = pos;
    pos = p + 2;
    return (d[p] << 8) | d[p + 1];
  }

  int readUint16LE() {
    _ensure(2);
    final d = data, p = pos;
    pos = p + 2;
    return d[p] | (d[p + 1] << 8);
  }

  int readUint32BE() {
    _ensure(4);
    final d = data, p = pos;
    pos = p + 4;
    return (d[p] << 24) | (d[p + 1] << 16) | (d[p + 2] << 8) | d[p + 3];
  }

  /// Reads an integer in the variable length "universal" format: a length
  /// byte (with the high bit indicating a negative value) followed by that
  /// many bytes in big endian order.
  @pragma('vm:prefer-inline')
  int _readUniversal(int maxLength, bool signed) {
    if (pos >= _size) throw _outOfPackets;
    final d = data;
    var length = d[pos];
    var negative = false;
    if (length & 0x80 != 0) {
      if (!signed) throw dpyError(ERR_UNEXPECTED_NEGATIVE_INTEGER);
      negative = true;
      length &= 0x7f;
    }
    if (length > maxLength) {
      throw dpyError(ERR_INTEGER_TOO_LARGE,
          args: {'length': length, 'max_length': maxLength});
    }
    if (pos + 1 + length > _size) throw _outOfPackets;
    var p = pos + 1;
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | d[p++];
    }
    pos = p;
    return negative ? -value : value;
  }

  int readUB2() => _readUniversal(2, false);
  int readUB4() => _readUniversal(4, false);
  int readUB8() => _readUniversal(8, false);
  int readSB2() => _readUniversal(2, true);
  int readSB4() => _readUniversal(4, true);
  int readSB8() => _readUniversal(8, true);

  @pragma('vm:prefer-inline')
  void _skipUniversal(int maxLength) {
    if (pos >= _size) throw _outOfPackets;
    final length = data[pos] & 0x7f;
    if (length > maxLength) {
      throw dpyError(ERR_INTEGER_TOO_LARGE,
          args: {'length': length, 'max_length': maxLength});
    }
    if (pos + 1 + length > _size) throw _outOfPackets;
    pos += 1 + length;
  }

  void skipUB1() => readUint8();
  void skipUB2() => _skipUniversal(2);
  void skipUB4() => _skipUniversal(4);
  void skipUB8() => _skipUniversal(8);
  void skipSB4() => _skipUniversal(4);

  void skipRawBytes(int n) {
    _ensure(n);
    pos += n;
  }

  /// Returns a view of the next [n] bytes (no copy is made).
  Uint8List readRawBytes(int n) {
    _ensure(n);
    final view = Uint8List.sublistView(data, pos, pos + n);
    pos += n;
    return view;
  }

  /// Reads bytes preceded by a length byte. Returns -1 if the value is null;
  /// otherwise the number of bytes, which can be found in [refData] starting
  /// at [refOffset]. Values longer than 252 bytes are sent in chunks and are
  /// assembled in a scratch buffer.
  int readBytesRef() {
    if (pos >= _size) throw _outOfPackets;
    final length = data[pos++];
    if (length == 0 || length == TNS_NULL_LENGTH_INDICATOR) return -1;
    if (length != TNS_LONG_LENGTH_INDICATOR) {
      if (pos + length > _size) throw _outOfPackets;
      refData = data;
      refOffset = pos;
      pos += length;
      return length;
    }
    var total = 0;
    while (true) {
      final chunkLen = readUB4();
      if (chunkLen == 0) break;
      _ensure(chunkLen);
      if (total + chunkLen > _chunkBuf.length) {
        var newLen = _chunkBuf.length * 2;
        while (newLen < total + chunkLen) {
          newLen *= 2;
        }
        _chunkBuf = Uint8List(newLen)..setRange(0, total, _chunkBuf);
      }
      _chunkBuf.setRange(total, total + chunkLen, data, pos);
      pos += chunkLen;
      total += chunkLen;
    }
    refData = _chunkBuf;
    refOffset = 0;
    return total;
  }

  /// Reads bytes preceded by a length byte and returns a copy of them.
  Uint8List? readBytes() {
    final n = readBytesRef();
    if (n < 0) return null;
    return Uint8List.fromList(
        Uint8List.sublistView(refData, refOffset, refOffset + n));
  }

  /// Reads a UB4 length and, if non-zero, bytes preceded by a length byte.
  Uint8List? readBytesWithLength() {
    final n = readUB4();
    if (n == 0) return null;
    return readBytes();
  }

  /// Reads a string encoded in UTF-8 (or UTF-16BE for the national
  /// character set) preceded by a length byte.
  String? readStr([int csfrm = CS_FORM_IMPLICIT]) {
    final n = readBytesRef();
    if (n < 0) return null;
    if (csfrm == CS_FORM_NCHAR) return decodeUtf16(refData, refOffset, n);
    return _utf8Decoder.convert(refData, refOffset, refOffset + n);
  }

  /// Reads a UB4 length and, if non-zero, a string.
  String? readStrWithLength() {
    final n = readUB4();
    if (n == 0) return null;
    return readStr();
  }

  Uint8List readNullTerminatedBytes() {
    final start = pos;
    var end = pos;
    while (end < _size && data[end] != 0) {
      end++;
    }
    if (end >= _size) throw _outOfPackets;
    pos = end + 1;
    return Uint8List.fromList(Uint8List.sublistView(data, start, pos));
  }

  /// Skips bytes preceded by a length byte, which may be sent in chunks.
  void skipRawBytesChunked() {
    final length = readUint8();
    if (length != TNS_LONG_LENGTH_INDICATOR) {
      skipRawBytes(length);
      return;
    }
    while (true) {
      final chunkLen = readUB4();
      if (chunkLen == 0) break;
      skipRawBytes(chunkLen);
    }
  }
}

String decodeUtf16(Uint8List data, int offset, int length) {
  final codes = List<int>.filled(length >> 1, 0);
  for (var i = 0; i < codes.length; i++) {
    codes[i] = (data[offset + 2 * i] << 8) | data[offset + 2 * i + 1];
  }
  return String.fromCharCodes(codes);
}

Uint8List encodeUtf16(String value) {
  final units = value.codeUnits;
  final out = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    out[2 * i] = units[i] >> 8;
    out[2 * i + 1] = units[i] & 0xff;
  }
  return out;
}

/// Callback used to send a complete packet to the server.
typedef PacketSender = void Function(Uint8List packet);

/// Buffer used to write requests; when a packet fills up (based on the SDU)
/// it is sent to the server and writing continues in a new packet.
class WriteBuffer {
  WriteBuffer(this.caps, this._sender) {
    resizeForSdu();
  }

  final Capabilities caps;
  final PacketSender _sender;
  Uint8List _data = Uint8List(0);
  int _pos = 0;
  int _maxSize = 0;
  int _packetType = 0;
  int _packetFlags = 0;
  int dataFlags = 0;
  int _seqNum = 0;
  bool packetSent = false;

  void resizeForSdu() {
    _maxSize = caps.sdu;
    _data = Uint8List(_maxSize);
  }

  void startRequest(int packetType, {int packetFlags = 0, int dataFlags = 0}) {
    packetSent = false;
    _packetType = packetType;
    _packetFlags = packetFlags;
    _pos = packetHeaderSize;
    if (packetType == TNS_PACKET_TYPE_DATA) {
      this.dataFlags = dataFlags;
      _pos += 2;
    }
  }

  void endRequest() {
    if (_pos > packetHeaderSize) _sendPacket(true);
  }

  void _sendPacket(bool finalPacket) {
    final size = _pos;
    final d = _data;
    if (caps.protocolVersion >= TNS_VERSION_MIN_LARGE_SDU) {
      d[0] = size >>> 24;
      d[1] = (size >>> 16) & 0xff;
      d[2] = (size >>> 8) & 0xff;
      d[3] = size & 0xff;
    } else {
      d[0] = size >>> 8;
      d[1] = size & 0xff;
      d[2] = 0;
      d[3] = 0;
    }
    d[4] = _packetType;
    d[5] = _packetFlags;
    d[6] = 0;
    d[7] = 0;
    if (_packetType == TNS_PACKET_TYPE_DATA) {
      d[8] = dataFlags >>> 8;
      d[9] = dataFlags & 0xff;
    }
    _sender(Uint8List.fromList(Uint8List.sublistView(d, 0, size)));
    packetSent = true;
    _pos = packetHeaderSize;
    if (!finalPacket && _packetType == TNS_PACKET_TYPE_DATA) {
      _pos += 2; // allow space for data flags
    }
  }

  @pragma('vm:prefer-inline')
  void _reserve(int n) {
    if (_pos + n > _maxSize) _sendPacket(false);
  }

  void writeUint8(int value) {
    if (_pos + 1 > _maxSize) _sendPacket(false);
    _data[_pos++] = value;
  }

  void writeUint16BE(int value) {
    _reserve(2);
    _data[_pos++] = (value >> 8) & 0xff;
    _data[_pos++] = value & 0xff;
  }

  void writeUint16LE(int value) {
    _reserve(2);
    _data[_pos++] = value & 0xff;
    _data[_pos++] = (value >> 8) & 0xff;
  }

  void writeUint32BE(int value) {
    _reserve(4);
    final d = _data;
    d[_pos++] = (value >>> 24) & 0xff;
    d[_pos++] = (value >>> 16) & 0xff;
    d[_pos++] = (value >>> 8) & 0xff;
    d[_pos++] = value & 0xff;
  }

  void writeUint64BE(int value) {
    writeUint32BE(value >>> 32);
    writeUint32BE(value & 0xffffffff);
  }

  void writeRaw(List<int> src, [int start = 0, int? end]) {
    end ??= src.length;
    while (start < end) {
      var n = _maxSize - _pos;
      if (n == 0) {
        _sendPacket(false);
        continue;
      }
      if (n > end - start) n = end - start;
      _data.setRange(_pos, _pos + n, src, start);
      _pos += n;
      start += n;
    }
  }

  /// Writes the bytes preceded by their length; values longer than 252 bytes
  /// are written in chunks.
  void writeBytesWithLength(List<int> src, [int start = 0, int? end]) {
    end ??= src.length;
    var n = end - start;
    if (n <= TNS_MAX_SHORT_LENGTH) {
      writeUint8(n);
      if (n > 0) writeRaw(src, start, end);
      return;
    }
    writeUint8(TNS_LONG_LENGTH_INDICATOR);
    while (n > 0) {
      final chunk = n < TNS_CHUNK_SIZE ? n : TNS_CHUNK_SIZE;
      writeUB4(chunk);
      writeRaw(src, start, start + chunk);
      start += chunk;
      n -= chunk;
    }
    writeUB4(0);
  }

  void writeUB2(int value) {
    if (value == 0) {
      writeUint8(0);
    } else if (value <= 0xff) {
      writeUint8(1);
      writeUint8(value);
    } else {
      writeUint8(2);
      writeUint16BE(value);
    }
  }

  void writeUB4(int value) {
    if (value == 0) {
      writeUint8(0);
    } else if (value <= 0xff) {
      writeUint8(1);
      writeUint8(value);
    } else if (value <= 0xffff) {
      writeUint8(2);
      writeUint16BE(value);
    } else {
      writeUint8(4);
      writeUint32BE(value);
    }
  }

  /// Writes a 32-bit signed integer in universal format.
  void writeSB4(int value) {
    value = value.toSigned(32);
    var sign = 0;
    if (value < 0) {
      value = -value;
      sign = 0x80;
    }
    if (value == 0) {
      writeUint8(0);
    } else if (value <= 0xff) {
      writeUint8(1 | sign);
      writeUint8(value);
    } else if (value <= 0xffff) {
      writeUint8(2 | sign);
      writeUint16BE(value);
    } else {
      writeUint8(4 | sign);
      writeUint32BE(value);
    }
  }

  void writeUB8(int value) {
    if (value == 0) {
      writeUint8(0);
    } else if (value > 0 && value <= 0xff) {
      writeUint8(1);
      writeUint8(value);
    } else if (value > 0 && value <= 0xffff) {
      writeUint8(2);
      writeUint16BE(value);
    } else if (value > 0 && value <= 0xffffffff) {
      writeUint8(4);
      writeUint32BE(value);
    } else {
      writeUint8(8);
      writeUint64BE(value);
    }
  }

  void writeStr(String value) => writeRaw(utf8.encode(value));

  /// Writes a QLocator (always 40 bytes) for a value of [dataLength] bytes
  /// sent inline (JSON and VECTOR binds).
  void writeQLocator(int dataLength, {bool writeLength = true}) {
    writeUB4(40); // QLocator length
    if (writeLength) writeUint8(40); // chunk length
    writeUint16BE(38); // QLocator length less 2 bytes
    writeUint16BE(TNS_LOB_QLOCATOR_VERSION);
    writeUint8(TNS_LOB_LOC_FLAGS_VALUE_BASED |
        TNS_LOB_LOC_FLAGS_BLOB |
        TNS_LOB_LOC_FLAGS_ABSTRACT);
    writeUint8(TNS_LOB_LOC_FLAGS_INIT);
    writeUint16BE(0); // additional flags
    writeUint16BE(1); // byt1
    writeUint64BE(dataLength);
    writeUint16BE(0); // unused
    writeUint16BE(0); // csid
    writeUint16BE(0); // unused
    writeUint64BE(0); // unused
    writeUint64BE(0); // unused
  }

  void writeSeqNum() {
    _seqNum = (_seqNum + 1) & 0xff;
    if (_seqNum == 0) _seqNum = 1;
    writeUint8(_seqNum);
  }
}
