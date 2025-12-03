import 'dart:io';
import 'dart:typed_data';

import 'connect_params.dart';
import 'protocol/capabilities.dart';
import 'protocol/messages/connect.dart';
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

    final packetBytes = connectMsg.buildPacket();
    await _transport.sendRaw(packetBytes);

    // Wait for ACCEPT/REFUSE/REDIRECT
    final packet = await _transport.readPacket();
    final body =
        Uint8List.sublistView(packet.buf, packetHeaderSize, packet.packetSize);
    final buf = ReadBuffer(body);
    connectMsg.process(buf, packet.packetType);

    // TODO: perform full TTC auth handshake; placeholder attempts minimal auth.
    final authMsg = AuthMessage(
      user: params.user,
      password: params.password,
      serviceName: params.serviceName,
      charsetId: capabilities.charsetId,
      ncharsetId: capabilities.ncharsetId,
      capabilities: capabilities,
    )..initialize(this);
    final authReq = authMsg.buildRequest();
    await _transport.sendRaw(authReq);
    final authPacket = await _transport.readPacket();
    final authBody = Uint8List.sublistView(
        authPacket.buf, packetHeaderSize, authPacket.packetSize);
    final authBuf = ReadBuffer(authBody);
    authMsg.processResponse(authBuf);
    _connected = true;
  }

  Future<void> close() async {
    await _transport.disconnect();
    _connected = false;
  }

  Transport get transport => _transport;
}
