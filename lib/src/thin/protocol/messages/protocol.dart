//C:\MyDartProjects\oracledb_dart\lib\src\thin\protocol\messages\protocol.dart
import 'dart:typed_data';
import '../constants.dart';
import '../packet.dart';
import 'base.dart';

const _driverName = 'python-oracledb'; // Testing with Python driver name

/// Protocol negotiation message sent after CONNECT/ACCEPT handshake.
class ProtocolMessage extends Message {
  int serverVersion = 0;
  int serverFlags = 0;
  Uint8List? serverCompileCaps;
  Uint8List? serverRuntimeCaps;
  String? serverBanner;

  void writeMessageBody(WriteBuffer body) {
    body.writeUint8(TNS_MSG_TYPE_PROTOCOL);
    body.writeUint8(6); // protocol version (8.1 and higher)
    body.writeUint8(0); // array terminator
    body.writeBytes(_driverName.codeUnits);
    body.writeUint8(0); // NULL terminator
  }

  Uint8List buildRequest() {
    final body = WriteBuffer();
    writeMessageBody(body);
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
      _processProtocolInfo(buf);
      endOfResponse = true;
    } else {
      super.processMessage(buf, messageType);
    }
  }

  void _processProtocolInfo(ReadBuffer buf) {
    serverVersion = buf.readUint8();
    buf.skipUint8(); // skip zero byte
    serverBanner = buf.readNullTerminatedString();
    final charsetId = buf.readUint16LE();
    serverFlags = buf.readUint8();
    final numElem = buf.readUint16LE();
    if (numElem > 0) {
      buf.skipBytes(numElem * 5);
    }
    final fdoLength = buf.readUint16();
    final fdo = buf.readBytes(fdoLength);
    final ix = 6 + fdo[5] + fdo[6];
    final ncharsetId = (fdo[ix + 3] << 8) + fdo[ix + 4];

    // Read server compile caps (raw byte payload)
    final compileCaps = buf.readBytesRawOrNull();
    if (compileCaps != null && compileCaps.isNotEmpty) {
      serverCompileCaps = compileCaps;
      print(
          'DEBUG: Server compile caps (${compileCaps.length} bytes): ${compileCaps.take(20).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      connImpl?.capabilities.adjustForServerCompileCaps(compileCaps);
    }

    // Read server runtime caps (raw byte payload)
    final runtimeCaps = buf.readBytesRawOrNull();
    if (runtimeCaps != null && runtimeCaps.isNotEmpty) {
      serverRuntimeCaps = runtimeCaps;
      print(
          'DEBUG: Server runtime caps (${runtimeCaps.length} bytes): ${runtimeCaps.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      connImpl?.capabilities.adjustForServerRuntimeCaps(runtimeCaps);
    }

    connImpl?.capabilities.charsetId = charsetId;
    connImpl?.capabilities.ncharsetId = ncharsetId;
    print(
        'DEBUG: Protocol response: charsetId=$charsetId, ncharsetId=$ncharsetId, serverVersion=$serverVersion, serverFlags=$serverFlags');
  }
}
