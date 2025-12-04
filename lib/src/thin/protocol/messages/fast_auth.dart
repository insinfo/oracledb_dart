import 'dart:typed_data';

import '../constants.dart';
import '../packet.dart';
import 'auth.dart';
import 'base.dart';
import 'data_types.dart';
import 'protocol.dart';

/// Fast authentication message used when the server supports bundling the
/// protocol, data types and initial AUTH negotiation in a single round-trip.
class FastAuthMessage extends Message {
  FastAuthMessage({
    required this.protocolMessage,
    required this.dataTypesMessage,
    required this.authMessage,
  });

  final ProtocolMessage protocolMessage;
  final DataTypesMessage dataTypesMessage;
  final AuthMessage authMessage;

  @override
  void initializeHook() {
    // Child messages must already be initialized with the same connection.
  }

  Uint8List buildRequest() {
    final body = WriteBuffer();
    body.writeUint8(TNS_MSG_TYPE_FAST_AUTH);
    body.writeUint8(1); // fast auth version
    body.writeUint8(TNS_SERVER_CONVERTS_CHARS); // flag 1
    body.writeUint8(0); // flag 2
    protocolMessage.writeMessageBody(body);
    body.writeUint16(0); // server charset (unused)
    body.writeUint8(0); // server charset flag (unused)
    body.writeUint16(0); // server ncharset (unused)

    final caps = connImpl.capabilities;
    final previousFieldVersion = caps.ttcFieldVersion;
    caps.ttcFieldVersion = TNS_CCAP_FIELD_VERSION_19_1_EXT_1;
    try {
      body.writeUint8(caps.ttcFieldVersion);
      dataTypesMessage.writeMessageBody(body);
      authMessage.writeMessageBody(body);
    } finally {
      caps.ttcFieldVersion = previousFieldVersion;
    }

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
    if (messageType == TNS_MSG_TYPE_PROTOCOL) {
      protocolMessage.processMessage(buf, messageType);
    } else if (messageType == TNS_MSG_TYPE_DATA_TYPES) {
      dataTypesMessage.processMessage(buf, messageType);
    } else {
      authMessage.processMessage(buf, messageType);
      endOfResponse = authMessage.endOfResponse;
      errorOccurred = authMessage.errorOccurred;
      if (authMessage.errorOccurred) {
        errorInfo = authMessage.errorInfo;
      }
    }
  }
}
