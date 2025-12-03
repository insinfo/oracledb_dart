// Thin protocol transport: send/receive packets over a Socket.
// This is a Dart-friendly port of python-oracledb's transport.pyx.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../exceptions.dart';
import 'constants.dart';
import 'packet.dart';

class Transport {
  Transport({
    int maxPacketSize = TNS_CHUNK_SIZE,
    bool fullPacketSize = false,
    bool? debugPackets,
  })  : _maxPacketSize = maxPacketSize,
        _fullPacketSize = fullPacketSize,
        _debugPackets =
            debugPackets ?? Platform.environment.containsKey('PYO_DEBUG_PACKETS');

  final int _maxPacketSize;
  bool _fullPacketSize;
  final bool _debugPackets;

  Socket? _socket;
  StreamIterator<Uint8List>? _iterator;
  Uint8List? _partialBuf;
  int _opNum = 0;
  int _sdu = TNS_CHUNK_SIZE;

  bool get isConnected => _socket != null;
  String get hostInfo => _socket == null
      ? 'disconnected'
      : '${_socket!.remoteAddress.address}:${_socket!.remotePort}';

  /// Negotiated SDU size (if known).
  int get sdu => _sdu;

  void setFromSocket(Socket socket) {
    _socket = socket;
    _iterator = StreamIterator(socket);
  }

  void setSdu(int value) {
    _sdu = value;
  }

  void setFullPacketSize(bool value) {
    _fullPacketSize = value;
  }

  /// Adjust the socket timeout; in Dart we emulate this via `setOption` when available.
  void setTimeout(Duration? timeout) {
    if (_socket == null) return;
    // Dart sockets do not expose a direct timeout; keep hook for parity.
    // Callers can wrap reads with `timeout` on the Future instead.
  }

  /// Reads and parses a packet from the transport.
  Future<Packet> readPacket() async {
    Packet? packet = extractPacket();
    while (packet == null) {
      if (_iterator == null) {
        throw createOracleException(
          dpyCode: ERR_CONNECTION_CLOSED,
          message: 'transport is not connected',
        );
      }
      final hasData = await _iterator!.moveNext();
      if (!hasData) {
        _disconnect();
        throw createOracleException(
          dpyCode: ERR_CONNECTION_CLOSED,
          message: 'socket closed while reading packet',
        );
      }
      final chunk = _iterator!.current;
      if (chunk.isEmpty) continue;
      packet = extractPacket(Uint8List.fromList(chunk));
    }
    return packet;
  }

  Future<void> disconnect() async {
    if (_socket == null) return;
    if (_debugPackets) {
      stdout.writeln(_getDebugHeader('Disconnecting transport'));
    }
    await _iterator?.cancel();
    _iterator = null;
    await _socket?.close();
    _socket = null;
  }

  /// Writes a packet to the transport.
  Future<void> writePacket(WriteBuffer buf) async {
    if (_socket == null) {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_CLOSED,
        message: 'transport is not connected',
      );
    }
    final data = buf.toBytes();
    if (_debugPackets) {
      _printPacket('Sending packet', data);
    }
    try {
      _socket!.add(data);
      await _socket!.flush();
    } catch (e) {
      _disconnect();
      throw createOracleException(
        dpyCode: ERR_CONNECTION_CLOSED,
        message: 'failed to write packet: $e',
        cause: e,
      );
    }
  }

  /// Send raw packet bytes (when the caller already built the header).
  Future<void> sendRaw(Uint8List data) async {
    if (_socket == null) {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_CLOSED,
        message: 'transport is not connected',
      );
    }
    if (_debugPackets) {
      _printPacket('Sending packet', data);
    }
    try {
      _socket!.add(data);
      await _socket!.flush();
    } catch (e) {
      _disconnect();
      throw createOracleException(
        dpyCode: ERR_CONNECTION_CLOSED,
        message: 'failed to write packet: $e',
        cause: e,
      );
    }
  }

  /// Try to extract a complete packet from the buffered data.
  Packet? extractPacket([Uint8List? data]) {
    if (data != null) {
      _appendPartial(data);
    }
    final size = _partialBuf?.length ?? 0;
    if (size < packetHeaderSize) return null;

    final buf = _partialBuf!;
    final packetSize =
        _fullPacketSize ? _readUint32BE(buf, 0) : _readUint16BE(buf, 0);
    if (size < packetSize) return null;

    final packetBuf =
        size == packetSize ? buf : Uint8List.sublistView(buf, 0, packetSize);
    final packet = Packet(
      packetSize: packetSize,
      packetType: packetBuf[4],
      packetFlags: packetBuf[5],
      buf: packetBuf,
    );

    // Retain remaining bytes, if any.
    _partialBuf = size == packetSize
        ? null
        : Uint8List.sublistView(buf, packetSize, size);

    if (_debugPackets) {
      _printPacket('Receiving packet', packet.buf);
    }
    return packet;
  }

  void _appendPartial(Uint8List data) {
    if (_partialBuf == null || _partialBuf!.isEmpty) {
      _partialBuf = data;
      return;
    }
    final combined = Uint8List(_partialBuf!.length + data.length);
    combined.setRange(0, _partialBuf!.length, _partialBuf!);
    combined.setRange(_partialBuf!.length, combined.length, data);
    _partialBuf = combined;
  }

  void _disconnect() {
    _iterator?.cancel();
    _iterator = null;
    _socket?.destroy();
    _socket = null;
  }

  void _printPacket(String operation, Uint8List data) {
    final header = _getDebugHeader(operation);
    final buf = StringBuffer(header);
    int offset = 0;
    while (offset < data.length) {
      final end = (offset + 8).clamp(0, data.length);
      final slice = data.sublist(offset, end);
      final hexBytes = slice.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).toList();
      while (hexBytes.length < 8) {
        hexBytes.add('  ');
      }
      final printable = slice
          .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.')
          .join()
          .padRight(8, ' ');
      buf.writeln();
      buf.write('${offset.toString().padLeft(4, '0')} : ${hexBytes.join(' ')} |$printable|');
      offset += 8;
    }
    stdout.writeln(buf.toString());
  }

  String _getDebugHeader(String operation) {
    _opNum += 1;
    final now = DateTime.now().toIso8601String();
    final sockInfo = _socket == null
        ? 'closed'
        : '${_socket!.remoteAddress.address}:${_socket!.remotePort}';
    return '$now $operation [op $_opNum] on socket $sockInfo';
  }
}
