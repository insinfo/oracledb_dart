import '../../../exceptions.dart';
import '../constants.dart';
import '../packet.dart';
import 'base.dart';

/// Minimal AUTH message placeholder: writes basic session/auth info and parses
/// simple success/failure responses. Full password verifier negotiation is TODO.
class AuthMessage extends Message {
  AuthMessage({
    required this.user,
    required this.password,
    required this.serviceName,
    required this.charsetId,
    required this.ncharsetId,
    required this.capabilities,
  });

  final String user;
  final String password;
  final String serviceName;
  final int charsetId;
  final int ncharsetId;
  final dynamic capabilities; // Capabilities instance

  Uint8List buildRequest() {
    final buf = WriteBuffer();
    // This mirrors python-oracledb structure superficially; detailed fields
    // (verifier types, version negotiation) are still TODO.
    buf.writeUint8(TNS_MSG_TYPE_FUNCTION);
    buf.writeUint8(0); // function code placeholder
    buf.writeUint16(0); // call status placeholder

    // Client caps and charset info
    buf.writeBytes((capabilities.compileCaps));
    buf.writeBytes((capabilities.runtimeCaps));
    buf.writeUint16(charsetId);
    buf.writeUint16(ncharsetId);

    // Basic credentials (plaintext for now; replace with verifier negotiation)
    _writeStringWithLength(buf, user);
    _writeStringWithLength(buf, password);
    _writeStringWithLength(buf, serviceName);

    return buf.toBytes();
  }

  void processResponse(ReadBuffer buf) {
    if (buf.isEOF) return;
    final status = buf.readUint8();
    if (status != 0) {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_FAILED,
        message: 'AUTH failed with status $status',
      );
    }
  }

  void _writeStringWithLength(WriteBuffer buf, String value) {
    final bytes = value.codeUnits;
    buf.writeUint16(bytes.length);
    buf.writeBytes(bytes);
  }
}
