import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../exceptions.dart';
import 'buffer.dart';
import 'constants.dart';
import 'tls.dart';

final bool _debugPackets =
    Platform.environment.containsKey('DART_ORACLEDB_DEBUG_PACKETS');

/// Thrown when the call timeout expires while waiting for the server.
class CallTimeout implements Exception {
  const CallTimeout();
}

/// A packet received from the server (including its 8 byte header).
class Packet {
  Packet(this.type, this.flags, this.buf);

  final int type;
  final int flags;
  final Uint8List buf;

  int get size => buf.length;

  /// Returns the data flags of a data packet.
  int get dataFlags => (buf[8] << 8) | buf[9];

  /// Returns true if this data packet marks the end of a response.
  bool get hasEndOfResponse {
    final flags = dataFlags;
    if (flags & TNS_DATA_FLAGS_END_OF_RESPONSE != 0 ||
        flags & TNS_DATA_FLAGS_EOF != 0) {
      return true;
    }
    return buf.length == packetHeaderSize + 3 &&
        buf[packetHeaderSize + 2] == TNS_MSG_TYPE_END_OF_RESPONSE;
  }
}

/// TCP transport which splits the incoming byte stream into packets. A
/// [RawSocket] is used directly to avoid the overhead of the stream layers.
class Transport {
  RawSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final Queue<Uint8List> _pendingWrites = Queue<Uint8List>();
  int _pendingWriteOffset = 0;
  Completer<void>? _flushWaiter;
  final Queue<Packet> _packets = Queue<Packet>();
  Completer<void>? _waiter;
  Object? _error;
  bool _closed = false;

  /// Before the connection is accepted the packet size is a 16-bit value;
  /// afterwards it is a 32-bit value.
  bool fullPacketSize = false;

  Uint8List _partial = Uint8List(0);
  int _partialLen = 0;

  bool get isConnected => _socket != null && !_closed;

  /// The address and port of the database server.
  String get peerHost => (_raw ?? _socket)?.remoteAddress.address ?? '';
  int get peerPort => (_raw ?? _socket)?.remotePort ?? 0;

  /// Settings used to secure the connection with TLS (null for plain TCP).
  TlsConfig? tls;

  /// The underlying TCP socket and its subscription, retained when TLS is
  /// used so that a new TLS session can be negotiated on the same socket.
  RawSocket? _raw;
  StreamSubscription<RawSocketEvent>? _rawSubscription;

  Future<void> connect(String host, int port, Duration timeout) async {
    final raw = await RawSocket.connect(host, port, timeout: timeout);
    raw.setOption(SocketOption.tcpNoDelay, true);
    _closed = false;
    _error = null;
    if (tls == null) {
      _socket = raw;
      _subscription = raw.listen(_onEvent,
          onError: _onError, onDone: _onDone, cancelOnError: true);
      return;
    }
    _raw = raw;
    _rawSubscription = raw.listen(null);
    await _negotiateTls(timeout);
  }

  Future<void> _negotiateTls(Duration timeout) async {
    final tls = this.tls!;
    final secure = await RawSecureSocket.secure(_raw!,
            subscription: _rawSubscription,
            host: tls.host,
            context: tls.context,
            onBadCertificate: tls.onBadCertificate)
        .timeout(timeout);
    tls.checkPeer(secure.peerCertificate);
    _socket = secure;
    _subscription = secure.listen(_onEvent,
        onError: _onError, onDone: _onDone, cancelOnError: true);
  }

  /// Performs a new TLS handshake on the same TCP connection, as requested
  /// by the listener when it hands the connection over to the database
  /// server process. The previous TLS session is abandoned (not closed,
  /// which would close the underlying socket).
  Future<void> renegotiateTls(Duration timeout) async {
    final old = _subscription;
    old
      ?..onData(null)
      ..onError(null)
      ..onDone(null);
    _packets.clear();
    _partialLen = 0;
    await _negotiateTls(timeout);
  }

  void _onEvent(RawSocketEvent event) {
    final socket = _socket;
    if (socket == null) return;
    switch (event) {
      case RawSocketEvent.read:
        // read() must only be called when data is available
        while (socket.available() > 0) {
          final data = socket.read();
          if (data == null) break;
          _onData(data);
        }
      case RawSocketEvent.write:
        _writePending();
      case RawSocketEvent.readClosed:
      case RawSocketEvent.closed:
        _onDone();
    }
  }

  void _writePending() {
    final socket = _socket;
    if (socket == null) return;
    while (_pendingWrites.isNotEmpty) {
      final data = _pendingWrites.first;
      final n = socket.write(
          data, _pendingWriteOffset, data.length - _pendingWriteOffset);
      _pendingWriteOffset += n;
      if (_pendingWriteOffset < data.length) {
        socket.writeEventsEnabled = true;
        return;
      }
      _pendingWrites.removeFirst();
      _pendingWriteOffset = 0;
    }
    final waiter = _flushWaiter;
    if (waiter != null) {
      _flushWaiter = null;
      waiter.complete();
    }
  }

  /// Disconnects and starts using a new socket (used for listener redirects).
  Future<void> reconnect(String host, int port, Duration timeout) async {
    await disconnect();
    final tls = this.tls;
    if (tls != null) {
      this.tls = TlsConfig(tls.context, host, tls.dnMatch, tls.certDn);
    }
    _raw = null;
    _rawSubscription = null;
    _packets.clear();
    _partialLen = 0;
    fullPacketSize = false;
    await connect(host, port, timeout);
  }

  void send(Uint8List data) {
    final socket = _socket;
    if (socket == null || _closed) throw dpyError(ERR_NOT_CONNECTED);
    if (_debugPackets) _printPacket('Sending packet', data);
    if (_pendingWrites.isEmpty) {
      final n = socket.write(data);
      if (n == data.length) return;
      _pendingWrites.add(data);
      _pendingWriteOffset = n;
      socket.writeEventsEnabled = true;
    } else {
      _pendingWrites.add(data);
    }
  }

  /// Waits until all pending data has been written to the socket.
  Future<void> flush() async {
    if (_pendingWrites.isEmpty) return;
    final waiter = _flushWaiter ??= Completer<void>();
    await waiter.future;
  }

  Future<void> disconnect() async {
    final socket = _socket;
    if (socket == null) return;
    _socket = null;
    _closed = true;
    _pendingWrites.clear();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await socket.close();
    } catch (_) {}
    _notify();
  }

  /// Returns the next packet if one has already been received.
  Packet? tryReadPacket() => _packets.isEmpty ? null : _packets.removeFirst();

  bool get hasPacket => _packets.isNotEmpty;

  /// Returns a packet to the front of the queue.
  void unread(Packet packet) => _packets.addFirst(packet);

  /// Returns true if a complete response has already been received.
  bool get hasFullResponse {
    for (final packet in _packets) {
      if (packet.type != TNS_PACKET_TYPE_DATA || packet.hasEndOfResponse) {
        return true;
      }
    }
    return false;
  }

  /// The time by which the current call must complete (call timeout); when
  /// it is exceeded while waiting for packets, [CallTimeout] is thrown.
  DateTime? deadline;

  Future<void> _waitForData() {
    final future = (_waiter = Completer<void>()).future;
    final deadline = this.deadline;
    if (deadline == null) return future;
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) throw const CallTimeout();
    return future.timeout(remaining,
        onTimeout: () => throw const CallTimeout());
  }

  /// Waits for the next packet to arrive.
  Future<Packet> readPacket() async {
    while (_packets.isEmpty) {
      _checkError();
      await _waitForData();
    }
    return _packets.removeFirst();
  }

  /// Waits until a complete response (a packet with the end of response
  /// flag, or any packet that is not a data packet) has been received.
  Future<void> waitForFullResponse() async {
    while (!hasFullResponse) {
      _checkError();
      await _waitForData();
    }
  }

  void _checkError() {
    if (_error != null) {
      throw dpyError(ERR_CONNECTION_CLOSED, message: '$_error', cause: _error);
    }
    if (_closed || _socket == null) throw dpyError(ERR_CONNECTION_CLOSED);
  }

  void _notify() {
    final waiter = _waiter;
    if (waiter != null) {
      _waiter = null;
      waiter.complete();
    }
  }

  void _onError(Object error) {
    _error = error;
    _closed = true;
    _notify();
  }

  void _onDone() {
    _closed = true;
    _notify();
  }

  int _packetSizeAt(Uint8List buf, int offset) => fullPacketSize
      ? (buf[offset] << 24) |
          (buf[offset + 1] << 16) |
          (buf[offset + 2] << 8) |
          buf[offset + 3]
      : (buf[offset] << 8) | buf[offset + 1];

  void _onData(Uint8List chunk) {
    var offset = 0;
    final added = _packets.length;

    // complete any partial packet first
    if (_partialLen > 0) {
      var needed = packetHeaderSize;
      if (_partialLen >= packetHeaderSize) {
        needed = _packetSizeAt(_partial, 0);
      } else {
        final n = packetHeaderSize - _partialLen;
        final take = n < chunk.length ? n : chunk.length;
        _appendPartial(chunk, 0, take);
        offset = take;
        if (_partialLen < packetHeaderSize) return;
        needed = _packetSizeAt(_partial, 0);
      }
      final take = needed - _partialLen < chunk.length - offset
          ? needed - _partialLen
          : chunk.length - offset;
      _appendPartial(chunk, offset, offset + take);
      offset += take;
      if (_partialLen < needed) return;
      _addPacket(
          Uint8List.fromList(Uint8List.sublistView(_partial, 0, needed)));
      _partialLen = 0;
    }

    // extract complete packets directly from the chunk (no copies)
    while (chunk.length - offset >= packetHeaderSize) {
      final size = _packetSizeAt(chunk, offset);
      if (size < packetHeaderSize) {
        _onError(dpyError(ERR_UNEXPECTED_DATA, args: {'data': 'packet size'}));
        return;
      }
      if (chunk.length - offset < size) break;
      _addPacket(Uint8List.sublistView(chunk, offset, offset + size));
      offset += size;
    }
    if (offset < chunk.length) _appendPartial(chunk, offset, chunk.length);
    if (_packets.length != added) _notify();
  }

  void _appendPartial(Uint8List src, int start, int end) {
    final n = end - start;
    if (_partialLen + n > _partial.length) {
      var newLen = _partial.isEmpty ? 16384 : _partial.length * 2;
      while (newLen < _partialLen + n) {
        newLen *= 2;
      }
      _partial = Uint8List(newLen)..setRange(0, _partialLen, _partial);
    }
    _partial.setRange(_partialLen, _partialLen + n, src, start);
    _partialLen += n;
  }

  void _addPacket(Uint8List buf) {
    if (_debugPackets) _printPacket('Receiving packet', buf);
    _packets.add(Packet(buf[4], buf[5], buf));
  }

  void _printPacket(String operation, Uint8List data) {
    final out = StringBuffer('${DateTime.now().toIso8601String()} $operation'
        ' (${data.length} bytes)\n');
    for (var i = 0; i < data.length; i += 16) {
      final end = i + 16 < data.length ? i + 16 : data.length;
      out.write(i.toRadixString(16).padLeft(4, '0'));
      out.write(' : ');
      final ascii = StringBuffer();
      for (var j = i; j < i + 16; j++) {
        if (j < end) {
          out.write(data[j].toRadixString(16).padLeft(2, '0').toUpperCase());
          out.write(' ');
          final b = data[j];
          ascii.writeCharCode(b > 32 && b < 127 ? b : 46);
        } else {
          out.write('   ');
        }
      }
      out.write('|$ascii|\n');
    }
    print(out);
  }
}
