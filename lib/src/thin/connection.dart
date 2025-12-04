import 'dart:io';
import 'dart:typed_data';

import '../exceptions.dart';
import 'connect_params.dart';
import 'debug/auth_logger.dart';
import 'protocol/capabilities.dart';
import 'protocol/constants.dart';
import 'protocol/messages/base.dart';
import 'protocol/messages/connect.dart';
import 'protocol/messages/protocol.dart';
import 'protocol/messages/data_types.dart';
import 'protocol/messages/auth.dart';
import 'protocol/messages/fast_auth.dart';
import 'protocol/packet.dart';
import 'protocol/transport.dart';

/// Thin connection stub. Opens a socket and prepares transport; handshake/login
/// is still to be implemented.
class ThinConnection {
  ThinConnection(this.params)
      : _transport = Transport(),
        capabilities = Capabilities();

  final ConnectParams params;
  final Transport _transport;
  final Capabilities capabilities;
  bool _connected = false;
  Packet? _pendingPacket;
  Uint8List? comboKey; // combo key derived during auth
  Uint8List? sessionKey; // session key from verifier negotiation
  String? sessionSignature;
  Uint8List? ltxid;
  Map<String, String> sessionData = {};
  int? sessionId;
  int? serialNum;
  String? dbDomain;
  String? dbName;
  int? maxOpenCursors;
  String? serviceFromServer;
  String? instanceName;
  int? maxIdentifierLength;
  List<int>? serverVersion;
  bool supportsBool = false;
  String? edition;

  bool get isConnected => _connected && _transport.isConnected;

  /// Establish a TCP connection to the Oracle listener. Handshake/login TODO.
  Future<void> connect() async {
    final socket = await Socket.connect(
      params.host,
      params.port,
      timeout: const Duration(seconds: 5),
    );
    _transport.setFromSocket(socket);
    // Build connect descriptor string
    final connectString =
        "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${params.host})(PORT=${params.port}))"
        "(CONNECT_DATA=(SERVICE_NAME=${params.serviceName})))";
    final connectMsg = ConnectMessage(
      connectStringBytes: connectString.codeUnits,
      host: params.host,
      port: params.port,
      sdu: capabilities.sdu,
    )..initialize(this);
    print('DEBUG: needsConnectData=${connectMsg.needsConnectData}');

    final packetBytes = connectMsg.buildPacket();
    await _transport.sendRaw(packetBytes);
    final connectDataPacket = connectMsg.buildConnectDataPacket();
    if (connectDataPacket != null) {
      await _transport.sendRaw(connectDataPacket);
    }

    // Wait for ACCEPT/REFUSE/REDIRECT
    var packet = await _transport.readPacket();
    print('DEBUG: Initial response packet type ${packet.packetType}');
    if (packet.packetType == TNS_PACKET_TYPE_RESEND) {
      print('DEBUG: Server requested CONNECT resend');
      await _transport.sendRaw(packetBytes);
      if (connectDataPacket != null) {
        await _transport.sendRaw(connectDataPacket);
      }
      packet = await _transport.readPacket();
      print('DEBUG: Response after resend packet type ${packet.packetType}');
    }
    final body =
        Uint8List.sublistView(packet.buf, packetHeaderSize, packet.packetSize);
    final buf = ReadBuffer(body);
    connectMsg.process(buf, packet.packetType);

    final protocolMsg = ProtocolMessage()..initialize(this);
    final dataTypesMsg = DataTypesMessage()..initialize(this);

    if (capabilities.supportsFastAuth) {
      print('DEBUG: Sending FastAuth message (protocol + data types + auth phase 1)...');
      final authPhase1 = _createAuthMessage(includePassword: false);
      final fastAuthMsg = FastAuthMessage(
        protocolMessage: protocolMsg,
        dataTypesMessage: dataTypesMsg,
        authMessage: authPhase1,
      )..initialize(this);
      final fastPkt = fastAuthMsg.buildRequest();
      AuthPacketLogger.logSend(authPhase1.traceLabel, fastPkt);
      await _transport.sendRaw(fastPkt);
      print('DEBUG: Receiving FastAuth response...');
      await _receiveMessage(fastAuthMsg);
      sessionData = {...sessionData, ...authPhase1.sessionData};
    } else {
      // Disable end-of-response for Protocol and DataTypes messages
      final savedSupportsEOR = capabilities.supportsEndOfResponse;
      capabilities.supportsEndOfResponse = false;

      // Send Protocol message
      print('DEBUG: Sending Protocol message...');
      final protocolPkt = protocolMsg.buildRequest();
      print('DEBUG: Protocol packet (${protocolPkt.length} bytes): ${protocolPkt.take(50).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await _transport.sendRaw(protocolPkt);
      print('DEBUG: Receiving Protocol response...');
      await _receiveMessage(protocolMsg);
      print('DEBUG: Protocol message complete');

      // Send DataTypes message
      print('DEBUG: Sending DataTypes message...');
      final dataTypesPkt = dataTypesMsg.buildRequest();
      print('DEBUG: DataTypes packet (${dataTypesPkt.length} bytes):');
      _printHexDump(dataTypesPkt);
      await _transport.sendRaw(dataTypesPkt);
      print('DEBUG: Receiving DataTypes response...');
      await _receiveMessage(dataTypesMsg);
      print('DEBUG: DataTypes message complete');
      print('DEBUG: ttcFieldVersion after negotiation: ${capabilities.ttcFieldVersion}');

      // Restore end-of-response support
      capabilities.supportsEndOfResponse = savedSupportsEOR;

      // AUTH phase 1: request session data (no password)
      print('DEBUG: Sending AUTH phase 1...');
      final authPhase1 = _createAuthMessage(includePassword: false);
      final pkt1 = authPhase1.buildRequest();
      AuthPacketLogger.logSend(authPhase1.traceLabel, pkt1);
      print('DEBUG: AUTH phase 1 packet (${pkt1.length} bytes):');
      _printHexDump(pkt1);
      await _transport.sendRaw(pkt1);
      print('DEBUG: Receiving AUTH phase 1 response...');
      await _receiveMessage(authPhase1);
      sessionData = {...sessionData, ...authPhase1.sessionData};
    }

    // AUTH phase 2: send verifier using session data
    final authPhase2 = _createAuthMessage(
      includePassword: true,
      initialSessionData: sessionData,
    );
    final pkt2 = authPhase2.buildRequest();
    AuthPacketLogger.logSend(authPhase2.traceLabel, pkt2);
    await _transport.sendRaw(pkt2);
    await _receiveMessage(authPhase2);
    sessionData = {...sessionData, ...authPhase2.sessionData};

    // Ensure session keys are available; otherwise fail fast.
    if (comboKey == null || sessionKey == null) {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_FAILED,
        message:
            'AUTH did not yield session keys; TTC login is not complete yet.',
      );
    }

    _connected = true;
  }

  Future<void> close() async {
    await _transport.disconnect();
    _connected = false;
  }

  Transport get transport => _transport;

  Future<void> _receiveMessage(Message message) async {
    message.endOfResponse = false;
    message.errorOccurred = false;
    print('DEBUG: _receiveMessage starting, supportsEOR=${capabilities.supportsEndOfResponse}');
    while (!message.endOfResponse) {
      print('DEBUG: Reading packet...');
      final packet = await _nextPacket();
      
      // IGNORA marker packets por enquanto - responder incorretamente causa TNS-12592
      // TODO: implementar BREAK/RESET corretamente quando necessário
      if (packet.packetType == TNS_PACKET_TYPE_MARKER) {
        print('DEBUG: Received marker packet, initiating RESET handshake');
        await _handleMarkerPacket(packet);
        continue;
      }
      
      if (AuthPacketLogger.enabled) {
        String? traceLabel;
        if (message is AuthMessage) {
          traceLabel = message.traceLabel;
        } else if (message is FastAuthMessage) {
          traceLabel = message.authMessage.traceLabel;
        }
        if (traceLabel != null) {
          final packetBytes =
              Uint8List.fromList(packet.buf.sublist(0, packet.packetSize));
          AuthPacketLogger.logReceive(traceLabel, packetBytes);
        }
      }
      print('DEBUG: Got packet type=${packet.packetType}, size=${packet.packetSize}, hasEOR=${packet.hasEndOfResponse}');
      final bodyOffset = packet.packetType == TNS_PACKET_TYPE_DATA
          ? packetHeaderSize + 2
          : packetHeaderSize;
      if (packet.packetSize > bodyOffset) {
        final body =
            Uint8List.sublistView(packet.buf, bodyOffset, packet.packetSize);
        final buf = ReadBuffer(body);
        message.processBuffer(buf);
        print('DEBUG: After processBuffer, endOfResponse=${message.endOfResponse}');
      }
      if (packet.hasEndOfResponse ||
          packet.packetType != TNS_PACKET_TYPE_DATA) {
        message.endOfResponse = true;
        print('DEBUG: Set endOfResponse=true due to packet');
      }
    }
    print('DEBUG: _receiveMessage complete');
    message.checkAndRaiseException();
  }

  Future<Packet> _nextPacket() async {
    if (_pendingPacket != null) {
      final packet = _pendingPacket!;
      _pendingPacket = null;
      return packet;
    }
    return _transport.readPacket();
  }

  Future<void> _handleMarkerPacket(Packet packet) async {
    final markerType = _markerTypeFromPacket(packet);
    print('DEBUG: Marker type=$markerType, sending RESET');
    await _sendMarker(TNS_MARKER_TYPE_RESET);

    var resetAckReceived = false;
    while (!resetAckReceived) {
      final nextPacket = await _transport.readPacket();
      if (nextPacket.packetType != TNS_PACKET_TYPE_MARKER) {
        _pendingPacket = nextPacket;
        return;
      }
      final nextMarkerType = _markerTypeFromPacket(nextPacket);
      if (nextMarkerType == TNS_MARKER_TYPE_RESET) {
        print('DEBUG: Received RESET marker ack');
        resetAckReceived = true;
      }
    }

    while (true) {
      final nextPacket = await _transport.readPacket();
      if (nextPacket.packetType == TNS_PACKET_TYPE_MARKER) {
        continue;
      }
      _pendingPacket = nextPacket;
      return;
    }
  }

  int _markerTypeFromPacket(Packet packet) {
    if (packet.packetSize < packetHeaderSize + 3) {
      return -1;
    }
    return packet.buf[packetHeaderSize + 2];
  }

  Future<void> _sendMarker(int markerType) async {
    final body = Uint8List.fromList([1, 0, markerType & 0xFF]);
    final packet = buildTnsPacket(
      bodyBytes: body,
      packetType: TNS_PACKET_TYPE_MARKER,
      useLargeSdu:
          capabilities.protocolVersion >= TNS_VERSION_MIN_LARGE_SDU,
    );
    await _transport.sendRaw(packet);
  }

  AuthMessage _createAuthMessage({
    required bool includePassword,
    Map<String, String>? initialSessionData,
  }) {
    final msg = AuthMessage(
      user: params.user,
      password: params.password,
      serviceName: params.serviceName,
      charsetId: capabilities.charsetId,
      ncharsetId: capabilities.ncharsetId,
      capabilities: capabilities,
      includePassword: includePassword,
      initialSessionData: initialSessionData,
    )..initialize(this);
    return msg;
  }

  void _printHexDump(Uint8List data) {
    final sb = StringBuffer();
    for (var i = 0; i < data.length; i += 16) {
      final end = (i + 16).clamp(0, data.length);
      final bytes = data.sublist(i, end);
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final ascii = bytes.map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.').join();
      sb.writeln('  ${i.toRadixString(16).padLeft(4, '0')}: ${hex.padRight(48)} $ascii');
    }
    print(sb.toString());
  }
}
