import 'dart:io';
import 'dart:typed_data';

import '../exceptions.dart';
import 'connect_params.dart';
import 'protocol/capabilities.dart';
import 'protocol/constants.dart';
import 'protocol/messages/base.dart';
import 'protocol/messages/connect.dart';
import 'protocol/messages/protocol.dart';
import 'protocol/messages/data_types.dart';
import 'protocol/messages/auth.dart';
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

    // Disable end-of-response for Protocol and DataTypes messages
    // as the server doesn't send it for these messages
    final savedSupportsEOR = capabilities.supportsEndOfResponse;
    capabilities.supportsEndOfResponse = false;

    // Send Protocol message
    print('DEBUG: Sending Protocol message...');
    final protocolMsg = ProtocolMessage()..initialize(this);
    final protocolPkt = protocolMsg.buildRequest();
    print('DEBUG: Protocol packet (${protocolPkt.length} bytes): ${protocolPkt.take(50).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    await _transport.sendRaw(protocolPkt);
    print('DEBUG: Receiving Protocol response...');
    await _receiveMessage(protocolMsg);
    print('DEBUG: Protocol message complete');

    // Send DataTypes message
    print('DEBUG: Sending DataTypes message...');
    final dataTypesMsg = DataTypesMessage()..initialize(this);
    final dataTypesPkt = dataTypesMsg.buildRequest();
    await _transport.sendRaw(dataTypesPkt);
    print('DEBUG: Receiving DataTypes response...');
    await _receiveMessage(dataTypesMsg);
    print('DEBUG: DataTypes message complete');

    // Restore end-of-response support
    capabilities.supportsEndOfResponse = savedSupportsEOR;

    // AUTH phase 1: request session data (no password)
    final authPhase1 = AuthMessage(
      user: params.user,
      password: params.password,
      serviceName: params.serviceName,
      charsetId: capabilities.charsetId,
      ncharsetId: capabilities.ncharsetId,
      capabilities: capabilities,
      includePassword: false,
    )..initialize(this);
    final pkt1 = authPhase1.buildRequest();
    await _transport.sendRaw(pkt1);
    await _receiveMessage(authPhase1);
    sessionData = {...sessionData, ...authPhase1.sessionData};

    // AUTH phase 2: send verifier using session data
    final authPhase2 = AuthMessage(
      user: params.user,
      password: params.password,
      serviceName: params.serviceName,
      charsetId: capabilities.charsetId,
      ncharsetId: capabilities.ncharsetId,
      capabilities: capabilities,
      includePassword: true,
      initialSessionData: sessionData,
    )..initialize(this);
    final pkt2 = authPhase2.buildRequest();
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
      final packet = await _transport.readPacket();
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
}
