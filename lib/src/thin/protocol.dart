import 'dart:async';
import 'dart:collection';

import '../exceptions.dart';
import 'buffer.dart';
import 'capabilities.dart';
import 'connection_impl.dart';
import 'constants.dart';
import 'messages/base.dart';
import 'transport.dart';

/// Serializes requests on a connection (only one request may be in progress
/// on the wire at any time).
class RequestLock {
  bool _locked = false;

  bool get isLocked => _locked;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() fn) async {
    if (_locked) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _locked = true;
    try {
      return await fn();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _locked = false;
      }
    }
  }
}

class Protocol {
  Protocol(this.conn) {
    readBuf = ReadBuffer(caps);
    writeBuf = WriteBuffer(caps, transport.send);
  }

  final ThinConnImpl conn;
  final Capabilities caps = Capabilities();
  final Transport transport = Transport();
  late final ReadBuffer readBuf;
  late final WriteBuffer writeBuf;
  final RequestLock lock = RequestLock();

  bool inConnect = true;
  bool txnInProgress = false;
  bool breakInProgress = false;
  int pendingErrorNum = 0;

  /// Type and flags of the last non-data packet received (used during
  /// connection establishment).
  int lastPacketType = 0;
  int lastPacketFlags = 0;

  bool _markerPending = false;
  int _pendingMarkerType = 0;

  bool get isHealthy => transport.isConnected && pendingErrorNum == 0;

  void forceDisconnect() {
    transport.disconnect();
  }

  void checkConnected() {
    if (pendingErrorNum != 0 &&
        pendingErrorNum != TNS_ERR_SESSION_SHUTDOWN &&
        pendingErrorNum != TNS_ERR_INBAND_MESSAGE) {
      transport.disconnect();
      if (pendingErrorNum == TNS_ERR_EXCEEDED_IDLE_TIME) {
        throw dpyError(ERR_EXCEEDED_IDLE_TIME);
      }
      throw dpyError(ERR_UNSUPPORTED_INBAND_NOTIFICATION,
          args: {'err_num': pendingErrorNum});
    }
    if (!transport.isConnected) {
      if (pendingErrorNum == TNS_ERR_SESSION_SHUTDOWN) {
        throw dpyError(ERR_CONNECTION_CLOSED);
      }
      throw dpyError(ERR_NOT_CONNECTED);
    }
  }

  void _processControlPacket(Packet packet) {
    final b = packet.buf;
    final controlType = (b[8] << 8) | b[9];
    if (controlType == TNS_CONTROL_TYPE_RESET_OOB) {
      caps.supportsOob = false;
    } else if (controlType == TNS_CONTROL_TYPE_INBAND_NOTIFICATION) {
      pendingErrorNum = (b[14] << 24) | (b[15] << 16) | (b[16] << 8) | b[17];
    }
  }

  /// Appends the payload of the packets received to the read buffer. At
  /// least one packet is waited for; if [waitForFull] is set, all packets up
  /// to the end of the response are waited for instead.
  Future<void> _fill({required bool waitForFull}) async {
    if (waitForFull) await transport.waitForFullResponse();
    var gotData = false;
    while (true) {
      var packet = transport.tryReadPacket();
      if (packet == null) {
        if (gotData) return;
        packet = await transport.readPacket();
      }
      switch (packet.type) {
        case TNS_PACKET_TYPE_DATA:
          if (packet.dataFlags == TNS_DATA_FLAGS_EOF) {
            pendingErrorNum = TNS_ERR_SESSION_SHUTDOWN;
          }
          readBuf.append(packet.buf, packetHeaderSize + 2, packet.size);
          gotData = true;
          if (waitForFull && packet.hasEndOfResponse) return;
        case TNS_PACKET_TYPE_MARKER:
          _markerPending = true;
          _pendingMarkerType = packet.size > 10 ? packet.buf[10] : 0;
          return;
        case TNS_PACKET_TYPE_CONTROL:
          _processControlPacket(packet);
          checkConnected();
        default:
          lastPacketType = packet.type;
          lastPacketFlags = packet.flags;
          readBuf.append(packet.buf, packetHeaderSize, packet.size);
          return;
      }
    }
  }

  void _sendMarker(int markerType, [WriteBuffer? buf]) {
    buf ??= writeBuf;
    buf.startRequest(TNS_PACKET_TYPE_MARKER);
    buf.writeUint8(1);
    buf.writeUint8(0);
    buf.writeUint8(markerType);
    buf.endRequest();
  }

  /// Interrupts the call in progress, if any: the call fails with ORA-01013.
  /// A separate buffer is used to avoid interfering with the request.
  void breakExternal() {
    if (breakInProgress || !lock.isLocked || !transport.isConnected) return;
    breakInProgress = true;
    _sendMarker(TNS_MARKER_TYPE_INTERRUPT, WriteBuffer(caps, transport.send));
  }

  /// Performs the break/reset handshake with the server after it has sent a
  /// marker (or after the client has sent a break).
  Future<void> _reset() async {
    _sendMarker(TNS_MARKER_TYPE_RESET);
    var markerType = _markerPending ? _pendingMarkerType : -1;
    _markerPending = false;
    while (markerType != TNS_MARKER_TYPE_RESET) {
      final packet = await transport.readPacket();
      if (packet.type == TNS_PACKET_TYPE_MARKER) {
        markerType = packet.size > 10 ? packet.buf[10] : 0;
      }
    }
    while (true) {
      final packet = await transport.readPacket();
      if (packet.type != TNS_PACKET_TYPE_MARKER) {
        transport.unread(packet);
        break;
      }
    }
    breakInProgress = false;
  }

  Future<void> _processResponse(Message message) async {
    while (true) {
      try {
        message.process(readBuf);
        return;
      } on OutOfPackets {
        if (_markerPending) {
          await _reset();
          readBuf.reset();
          await _fill(waitForFull: caps.supportsEndOfResponse);
        } else {
          readBuf.compactToSavePoint();
          await _fill(waitForFull: false);
          readBuf.restorePoint();
        }
      }
    }
  }

  /// Sends the message to the server and processes the response, applying
  /// the call timeout of the connection.
  Future<void> processMessage(Message message) async {
    final timeout = conn.callTimeout;
    if (timeout == null || inConnect) return _processMessage(message);
    transport.deadline = DateTime.now().add(timeout);
    try {
      await _processMessage(message);
    } on CallTimeout {
      await _recoverFromTimeout(message, timeout);
    } finally {
      transport.deadline = null;
    }
  }

  /// Interrupts the call that exceeded the call timeout and discards the
  /// response of the server to the interruption (so that the connection
  /// remains usable), then raises DPY-4024.
  Future<void> _recoverFromTimeout(Message message, Duration timeout) async {
    transport.deadline = DateTime.now().add(timeout);
    try {
      breakInProgress = true;
      _sendMarker(TNS_MARKER_TYPE_INTERRUPT);
      if (!_markerPending) {
        readBuf.reset();
        await _fill(waitForFull: false);
      }
      if (_markerPending) {
        await _reset();
        readBuf.reset();
        await _fill(waitForFull: caps.supportsEndOfResponse);
      }
      try {
        await _processResponse(message);
      } on CallTimeout {
        rethrow;
      } catch (_) {
        // the interrupted call ends with ORA-01013, which is expected
      }
      breakInProgress = false;
    } on CallTimeout {
      transport.disconnect();
      throw dpyError(ERR_CONNECTION_CLOSED,
          message: 'socket timed out while recovering from previous socket '
              'timeout');
    }
    throw dpyError(ERR_CALL_TIMEOUT_EXCEEDED,
        args: {'timeout': timeout.inMilliseconds});
  }

  Future<void> _processMessage(Message message) async {
    try {
      readBuf.reset();
      _markerPending = false;
      message.send(writeBuf);
      await _fill(waitForFull: caps.supportsEndOfResponse);
      if (_markerPending && readBuf.size == 0) {
        await _reset();
        await _fill(waitForFull: caps.supportsEndOfResponse);
      }
      await _processResponse(message);
    } on CallTimeout {
      rethrow;
    } catch (_) {
      if (!inConnect && writeBuf.packetSent && transport.isConnected) {
        try {
          _sendMarker(TNS_MARKER_TYPE_BREAK);
          await _reset();
        } catch (_) {
          transport.disconnect();
        }
      }
      rethrow;
    }
    if (message.flushOutBinds) {
      writeBuf.startRequest(TNS_PACKET_TYPE_DATA);
      writeBuf.writeUint8(TNS_MSG_TYPE_FLUSH_OUT_BINDS);
      writeBuf.endRequest();
      readBuf.reset();
      await _fill(waitForFull: caps.supportsEndOfResponse);
      await _processResponse(message);
    }
    if (breakInProgress) {
      // the call completed before the server processed the interruption;
      // consume the response to the interruption
      readBuf.reset();
      _markerPending = false;
      await _fill(waitForFull: false);
      if (_markerPending) {
        await _reset();
        readBuf.reset();
        await _fill(waitForFull: caps.supportsEndOfResponse);
      }
      try {
        await _processResponse(SimpleMessage(conn, 0));
      } catch (_) {}
      breakInProgress = false;
    }
    _processCallStatus(message.callStatus);
    if (message.errorOccurred) {
      if (message.retry) {
        message.errorOccurred = false;
        return _processMessage(message);
      }
      message.checkAndThrow();
    }
  }

  void _processCallStatus(int callStatus) {
    txnInProgress = callStatus & TNS_EOCS_FLAGS_TXN_IN_PROGRESS != 0;
    if (callStatus & TNS_EOCS_FLAGS_SESS_RELEASE != 0) {
      conn.statementCache.clearOpenCursors();
    }
  }

  /// Processes a single message as a complete request.
  Future<void> processSingleMessage(Message message) async {
    message.preprocess();
    await lock.run(() async {
      checkConnected();
      await processMessage(message);
      if (message.resend) await processMessage(message);
    });
    message.postprocess();
  }

  /// Sends the final close packet and disconnects.
  Future<void> finalClose() async {
    if (transport.isConnected) {
      try {
        writeBuf.startRequest(TNS_PACKET_TYPE_DATA,
            dataFlags: TNS_DATA_FLAGS_EOF);
        writeBuf.endRequest();
        await transport.flush();
      } catch (_) {}
    }
    await transport.disconnect();
  }
}
