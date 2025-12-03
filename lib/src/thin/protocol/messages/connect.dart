import '../../../exceptions.dart';
import '../constants.dart';
import '../packet.dart';
import 'base.dart';

/// Thin CONNECT/ACCEPT handshake message scaffold.
///
/// This is a partial port of python-oracledb's ConnectMessage. It prepares the
/// structure for building the connect packet; the actual TTC payload crafting
/// is still TODO.
class ConnectMessage extends Message {
  ConnectMessage({
    required this.connectStringBytes,
    required this.host,
    required this.port,
    required this.sdu,
    this.packetFlags = 0,
  });

  final List<int> connectStringBytes;
  final String host;
  final int port;
  final int sdu;
  final int packetFlags;

  int get connectStringLen => connectStringBytes.length;

  /// Process ACCEPT / REFUSE / REDIRECT responses (partial).
  void process(ReadBuffer buf, int packetType) {
    if (packetType == TNS_PACKET_TYPE_ACCEPT) {
      final protocolVersion = buf.readUint16();
      if (protocolVersion < TNS_VERSION_MIN_ACCEPTED) {
        throw createOracleException(
          dpyCode: ERR_SERVER_VERSION_NOT_SUPPORTED,
          message: 'Server protocol $protocolVersion is below minimum',
        );
      }
      final protocolOptions = buf.readUint16();
      buf.skipBytes(10);
      final flags1 = buf.readUint8();
      if ((flags1 & TNS_NSI_NA_REQUIRED) != 0) {
        throw createOracleException(
          dpyCode: ERR_FEATURE_NOT_SUPPORTED,
          message: 'Native Network Encryption required by server',
        );
      }
      buf.skipBytes(9);
      final sdu = buf.readUint32();
      int flags2 = 0;
      if (protocolVersion >= TNS_VERSION_MIN_OOB_CHECK) {
        buf.skipBytes(5);
        flags2 = buf.readUint32();
      }
      connImpl?.capabilities
          ?._adjustForProtocol(protocolVersion, protocolOptions, flags2);
      connImpl?.transport.setFullPacketSize(true);
      connImpl?.transport.setSdu(sdu);
    } else if (packetType == TNS_PACKET_TYPE_REFUSE) {
      throw createOracleException(
        dpyCode: ERR_LISTENER_REFUSED_CONNECTION,
        message: errorInfo.message ?? 'Listener refused connection',
      );
    } else if (packetType == TNS_PACKET_TYPE_REDIRECT) {
      final redirectLen = buf.readUint16();
      if (redirectLen > 0) {
        final data = buf.readBytes(redirectLen);
        errorInfo.message =
            String.fromCharCodes(data); // stash redirect for caller
      }
    }
  }

  /// Build the CONNECT packet payload into [buf].
  Uint8List buildPacket() {
    final serviceOptions = TNS_GSO_DONT_CARE;
    const nsiFlags = TNS_NSI_SUPPORT_SECURITY_RENEG | TNS_NSI_DISABLE_NA;
    const connectFlags1 = 0;
    var connectFlags2 = 0;

    // We don't know if OOB is supported yet; initial CONNECT uses defaults.
    final body = WriteBuffer();
    body.writeUint16(TNS_VERSION_DESIRED);
    body.writeUint16(TNS_VERSION_MINIMUM);
    body.writeUint16(serviceOptions);
    body.writeUint16(sdu);
    body.writeUint16(sdu); // TDU
    body.writeUint16(TNS_PROTOCOL_CHARACTERISTICS);
    body.writeUint16(0); // line turnaround
    body.writeUint16(1); // value of 1
    body.writeUint16(connectStringLen);
    body.writeUint16(74); // offset to connect data
    body.writeUint32(0); // max receivable data
    body.writeUint8(nsiFlags);
    body.writeUint8(nsiFlags);
    body.writeUint64(0); // obsolete
    body.writeUint64(0); // obsolete
    body.writeUint64(0); // obsolete
    body.writeUint32(sdu); // SDU (large)
    body.writeUint32(sdu); // TDU (large)
    body.writeUint32(connectFlags1);
    body.writeUint32(connectFlags2);
    body.writeBytes(connectStringBytes);

    final bodyBytes = body.toBytes();
    final totalLen = packetHeaderSize + bodyBytes.length;
    final packet = Uint8List(totalLen);
    final header = ByteData.sublistView(packet, 0, packetHeaderSize);

    // Initial CONNECT uses 2-byte length.
    header.setUint16(0, totalLen, Endian.big);
    header.setUint16(2, 0, Endian.big);
    packet[4] = TNS_PACKET_TYPE_CONNECT;
    packet[5] = packetFlags;
    header.setUint16(6, 0, Endian.big);

    packet.setRange(packetHeaderSize, totalLen, bodyBytes);
    return packet;
  }
}
