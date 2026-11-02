import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../crypto/aes.dart';
import '../../crypto/hash.dart';
import '../../crypto/rsa.dart';
import '../../exceptions.dart';
import '../../utils.dart';
import '../buffer.dart';
import '../constants.dart';
import '../data_types_table.dart';
import 'base.dart';

const String driverName = 'oracledb_dart';
const String driverVersion = '1.1.0';

/// Sends the connect packet to the listener and processes the response
/// (accept, refuse, redirect or resend).
class ConnectMessage extends Message {
  ConnectMessage(super.conn, this.connectString, this.sdu,
      {this.packetFlags = 0});

  final String connectString;
  final int sdu;
  int packetFlags;
  String? redirectData;

  @override
  void process(ReadBuffer buf) {
    buf.restorePoint();
    final packetType = conn.protocol.lastPacketType;
    if (packetType == TNS_PACKET_TYPE_REDIRECT) {
      final len = buf.readUint16BE();
      final data = buf.readRawBytes(len);
      if (len > 0) redirectData = utf8.decode(data, allowMalformed: true);
    } else if (packetType == TNS_PACKET_TYPE_ACCEPT) {
      final protocolVersion = buf.readUint16BE();
      if (protocolVersion < TNS_VERSION_MIN_ACCEPTED) {
        throw dpyError(ERR_SERVER_VERSION_NOT_SUPPORTED);
      }
      final protocolOptions = buf.readUint16BE();
      buf.skipRawBytes(10);
      final flags1 = buf.readUB1();
      if (flags1 & TNS_NSI_NA_REQUIRED != 0) {
        throw dpyError(ERR_FEATURE_NOT_SUPPORTED, args: {
          'feature': 'Native Network Encryption and Data Integrity',
          'driver_type': 'thick',
        });
      }
      buf.skipRawBytes(9);
      buf.caps.sdu = buf.readUint32BE();
      var flags2 = 0;
      if (protocolVersion >= TNS_VERSION_MIN_OOB_CHECK) {
        buf.skipRawBytes(5);
        flags2 = buf.readUint32BE();
      }
      buf.caps.adjustForProtocol(protocolVersion, protocolOptions, flags2);
      conn.protocol.transport.fullPacketSize = true;
    } else if (packetType == TNS_PACKET_TYPE_REFUSE) {
      buf.skipRawBytes(2);
      final len = buf.readUint16BE();
      String? response;
      if (len > 0) response = utf8.decode(buf.readRawBytes(len));
      var errorCode = 'unknown';
      var errorCodeInt = 0;
      if (response != null) {
        final pos = response.indexOf('(ERR=');
        if (pos > 0) {
          final endPos = response.indexOf(')', pos);
          if (endPos > 0) {
            errorCode = response.substring(pos + 5, endPos);
            errorCodeInt = int.tryParse(errorCode) ?? 0;
          }
        }
      }
      if (errorCodeInt == 0) throw dpyError(ERR_UNEXPECTED_REFUSE);
      if (errorCodeInt == TNS_ERR_INVALID_SERVICE_NAME) {
        throw dpyError(ERR_INVALID_SERVICE_NAME, args: {
          'service_name': conn.params.serviceName,
          'host': conn.params.host,
          'port': conn.params.port,
        });
      } else if (errorCodeInt == TNS_ERR_INVALID_SID) {
        throw dpyError(ERR_INVALID_SID, args: {
          'sid': conn.params.sid,
          'host': conn.params.host,
          'port': conn.params.port,
        });
      }
      throw dpyError(ERR_LISTENER_REFUSED_CONNECTION,
          args: {'error_code': errorCode});
    }
  }

  @override
  void send(WriteBuffer buf) {
    var serviceOptions = TNS_GSO_DONT_CARE;
    const connectFlags1 = 0;
    var connectFlags2 = 0;
    const nsiFlags = TNS_NSI_SUPPORT_SECURITY_RENEG | TNS_NSI_DISABLE_NA;
    if (buf.caps.supportsOob) {
      serviceOptions |= TNS_GSO_CAN_RECV_ATTENTION;
      connectFlags2 |= TNS_CHECK_OOB;
    }
    final connectBytes = utf8.encode(connectString);
    buf.startRequest(TNS_PACKET_TYPE_CONNECT, packetFlags: packetFlags);
    buf.writeUint16BE(TNS_VERSION_DESIRED);
    buf.writeUint16BE(TNS_VERSION_MINIMUM);
    buf.writeUint16BE(serviceOptions);
    buf.writeUint16BE(sdu > 65535 ? 65535 : sdu);
    buf.writeUint16BE(sdu > 65535 ? 65535 : sdu);
    buf.writeUint16BE(TNS_PROTOCOL_CHARACTERISTICS);
    buf.writeUint16BE(0); // line turnaround
    buf.writeUint16BE(1); // value of 1
    buf.writeUint16BE(connectBytes.length);
    buf.writeUint16BE(74); // offset to connect data
    buf.writeUint32BE(0); // max receivable data
    buf.writeUint8(nsiFlags);
    buf.writeUint8(nsiFlags);
    buf.writeUint64BE(0); // obsolete
    buf.writeUint64BE(0); // obsolete
    buf.writeUint64BE(0); // obsolete
    buf.writeUint32BE(sdu); // SDU (large)
    buf.writeUint32BE(sdu); // TDU (large)
    buf.writeUint32BE(connectFlags1);
    buf.writeUint32BE(connectFlags2);
    if (connectBytes.length > TNS_MAX_CONNECT_DATA) {
      buf.endRequest();
      buf.startRequest(TNS_PACKET_TYPE_DATA);
    }
    buf.writeRaw(connectBytes);
    buf.endRequest();
  }
}

/// Exchanges protocol information (versions, character sets, capabilities).
class ProtocolMessage extends Message {
  ProtocolMessage(super.conn);

  int serverVersion = 0;
  int serverFlags = 0;
  Uint8List? serverBanner;

  @override
  void writeMessage(WriteBuffer buf) {
    buf.writeUint8(TNS_MSG_TYPE_PROTOCOL);
    buf.writeUint8(6); // protocol version (8.1 and higher)
    buf.writeUint8(0); // "array" terminator
    buf.writeStr(driverName);
    buf.writeUint8(0); // NULL terminator
  }

  @override
  void processMessage(ReadBuffer buf, int messageType) {
    if (messageType == TNS_MSG_TYPE_PROTOCOL) {
      _processProtocolInfo(buf);
      if (!buf.caps.supportsEndOfResponse) endOfResponse = true;
    } else {
      super.processMessage(buf, messageType);
    }
  }

  void _processProtocolInfo(ReadBuffer buf) {
    final caps = buf.caps;
    serverVersion = buf.readUB1();
    buf.skipUB1(); // skip zero byte
    serverBanner = buf.readNullTerminatedBytes();
    caps.charsetId = buf.readUint16LE();
    serverFlags = buf.readUB1();
    final numElem = buf.readUint16LE();
    if (numElem > 0) buf.skipRawBytes(numElem * 5);
    final fdoLength = buf.readUint16BE();
    final fdo = buf.readRawBytes(fdoLength);
    final ix = 6 + fdo[5] + fdo[6];
    caps.ncharsetId = (fdo[ix + 3] << 8) + fdo[ix + 4];
    final compileCaps = buf.readBytes();
    if (compileCaps != null) {
      caps.adjustForServerCompileCaps(compileCaps);
      if (caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1) {
        conn.osonMaxFnameSize = 65535;
      }
    }
    final runtimeCaps = buf.readBytes();
    if (runtimeCaps != null) caps.adjustForServerRuntimeCaps(runtimeCaps);
  }
}

/// Exchanges the data types supported by the client and the server.
class DataTypesMessage extends Message {
  DataTypesMessage(super.conn);

  @override
  void processMessage(ReadBuffer buf, int messageType) {
    while (true) {
      final dataType = buf.readUint16BE();
      if (dataType == 0) break;
      final convDataType = buf.readUint16BE();
      if (convDataType != 0) buf.skipRawBytes(4);
    }
    if (!buf.caps.supportsEndOfResponse) endOfResponse = true;
  }

  @override
  void writeMessage(WriteBuffer buf) {
    buf.writeUint8(TNS_MSG_TYPE_DATA_TYPES);
    buf.writeUint16LE(TNS_CHARSET_UTF8);
    buf.writeUint16LE(TNS_CHARSET_UTF8);
    buf.writeUint8(TNS_ENCODING_MULTI_BYTE | TNS_ENCODING_CONV_LENGTH);
    buf.writeBytesWithLength(buf.caps.compileCaps);
    buf.writeBytesWithLength(buf.caps.runtimeCaps);
    const table = dataTypesTable;
    for (var i = 0; i < table.length; i += 3) {
      buf.writeUint16BE(table[i]);
      buf.writeUint16BE(table[i + 1]);
      buf.writeUint16BE(table[i + 2]);
      buf.writeUint16BE(0);
    }
    buf.writeUint16BE(0);
  }
}

/// Performs the two phases of authentication.
class AuthMessage extends Message {
  /// Creates the message; with an access [token], only the second phase of
  /// authentication is sent (token authentication).
  AuthMessage(super.conn, {this.token}) {
    functionCode = TNS_FUNC_AUTH_PHASE_ONE;
    final user = conn.params.user;
    if (user != null && user.isNotEmpty) userBytes = utf8.encode(user);
    password = utf8.encode(conn.params.password ?? '');
    final newPassword = conn.params.newPassword;
    if (newPassword != null) this.newPassword = utf8.encode(newPassword);
    authMode = newPassword == null ? TNS_AUTH_MODE_LOGON : 0;
    authMode |= conn.params.mode;
    resend = true;
    if (token != null) {
      functionCode = TNS_FUNC_AUTH_PHASE_TWO;
      resend = false;
      if (conn.params.privateKey != null) authMode |= TNS_AUTH_MODE_IAM_TOKEN;
    }
  }

  final String? token;

  Uint8List userBytes = Uint8List(0);
  late Uint8List password;
  Uint8List? newPassword;
  final Map<String, String> sessionData = {};
  int authMode = 0;
  int verifierType = 0;
  bool changePassword = false;
  String? encodedPassword;
  String? encodedNewPassword;
  String? sessionKey;
  String? speedyKey;

  void _encryptPasswords() {
    final comboKey = conn.comboKey!;
    final salt = randomBytes(16);
    encodedPassword = toHex(aesCbcEncrypt(comboKey, [...salt, ...password]));
    if (newPassword != null) {
      encodedNewPassword =
          toHex(aesCbcEncrypt(comboKey, [...salt, ...newPassword!]));
    }
  }

  void _generateVerifier() {
    final verifierData = fromHex(sessionData['AUTH_VFR_DATA']!);
    int keyLen;
    Uint8List passwordHash;
    Uint8List? passwordKey;
    if (verifierType == TNS_VERIFIER_TYPE_12C) {
      keyLen = 32;
      final iterations = int.parse(sessionData['AUTH_PBKDF2_VGEN_COUNT']!);
      final salt = [...verifierData, ...utf8.encode('AUTH_PBKDF2_SPEEDY_KEY')];
      passwordKey = pbkdf2Sha512(password, salt, iterations, 64);
      final h = Sha512()
        ..update(passwordKey)
        ..update(verifierData);
      passwordHash = Uint8List.sublistView(h.digest(), 0, 32);
    } else {
      keyLen = 24;
      final h = Sha1()
        ..update(password)
        ..update(verifierData);
      passwordHash = Uint8List(24)..setAll(0, h.digest());
    }

    // decrypt first half of session key and generate the second half
    final encodedServerKey = fromHex(sessionData['AUTH_SESSKEY']!);
    final sessionKeyPartA = aesCbcDecrypt(passwordHash, encodedServerKey);
    final sessionKeyPartB = randomBytes(sessionKeyPartA.length);
    final encodedClientKey = aesCbcEncrypt(passwordHash, sessionKeyPartB);

    // create session key and combo key
    Uint8List comboKey;
    if (sessionKeyPartA.length == 48) {
      sessionKey = toHex(encodedClientKey).substring(0, 96);
      final b = Uint8List(24);
      for (var i = 16; i < 40; i++) {
        b[i - 16] = sessionKeyPartA[i] ^ sessionKeyPartB[i];
      }
      final part1 = Md5.hash(Uint8List.sublistView(b, 0, 16));
      final part2 = Md5.hash(Uint8List.sublistView(b, 16));
      comboKey = Uint8List.sublistView(
          Uint8List.fromList([...part1, ...part2]), 0, keyLen);
    } else {
      sessionKey = toHex(encodedClientKey).substring(0, 64);
      final salt = fromHex(sessionData['AUTH_PBKDF2_CSK_SALT']!);
      final iterations = int.parse(sessionData['AUTH_PBKDF2_SDER_COUNT']!);
      final tempKey = [
        ...sessionKeyPartB.sublist(0, keyLen),
        ...sessionKeyPartA.sublist(0, keyLen),
      ];
      comboKey =
          pbkdf2Sha512(utf8.encode(toHex(tempKey)), salt, iterations, keyLen);
    }
    conn.comboKey = comboKey;

    // generate speedy key for 12c verifiers
    if (verifierType == TNS_VERIFIER_TYPE_12C) {
      final salt = randomBytes(16);
      final encrypted = aesCbcEncrypt(comboKey, [...salt, ...passwordKey!]);
      speedyKey = toHex(Uint8List.sublistView(encrypted, 0, 80));
    }
    _encryptPasswords();
  }

  String _alterTimezoneStatement() {
    var tzRepr = Platform.environment['ORA_SDTZ'];
    if (tzRepr == null) {
      final offset = DateTime.now().timeZoneOffset;
      final totalMinutes = offset.inMinutes.abs();
      final sign = offset.isNegative ? '-' : '+';
      final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
      final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
      tzRepr = '$sign$hours:$minutes';
    }
    return "ALTER SESSION SET TIME_ZONE='$tzRepr'\x00";
  }

  List<int> versionTuple(ReadBuffer buf) {
    final v = int.parse(sessionData['AUTH_VERSION_NO'] ?? '0');
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_18_1_EXT_1) {
      return [
        (v >> 24) & 0xff,
        (v >> 16) & 0xff,
        (v >> 12) & 0x0f,
        (v >> 4) & 0xff,
        v & 0x0f,
      ];
    }
    return [
      (v >> 24) & 0xff,
      (v >> 20) & 0x0f,
      (v >> 12) & 0x0f,
      (v >> 8) & 0x0f,
      v & 0x0f,
    ];
  }

  @override
  void processReturnParameters(ReadBuffer buf) {
    final numParams = buf.readUB2();
    for (var i = 0; i < numParams; i++) {
      final key = buf.readStrWithLength() ?? '';
      final value = buf.readStrWithLength() ?? '';
      if (key == 'AUTH_VFR_DATA') {
        verifierType = buf.readUB4();
      } else {
        buf.skipUB4(); // skip flags
      }
      sessionData[key] = value;
    }
    if (functionCode == TNS_FUNC_AUTH_PHASE_ONE) {
      functionCode = TNS_FUNC_AUTH_PHASE_TWO;
    } else if (!changePassword && conn.comboKey != null) {
      Uint8List? response;
      final value = sessionData['AUTH_SVR_RESPONSE'];
      if (value != null) {
        response = aesCbcDecrypt(conn.comboKey!, fromHex(value));
      }
      if (response == null ||
          response.length < 32 ||
          String.fromCharCodes(response.sublist(16, 32)) !=
              'SERVER_TO_CLIENT') {
        throw dpyError(ERR_INVALID_SERVER_RESPONSE);
      }
    }
  }

  void _writeKeyValue(WriteBuffer buf, String key, String value,
      [int flags = 0]) {
    final keyBytes = utf8.encode(key);
    final valueBytes = utf8.encode(value);
    buf.writeUB4(keyBytes.length);
    buf.writeBytesWithLength(keyBytes);
    buf.writeUB4(valueBytes.length);
    if (valueBytes.isNotEmpty) buf.writeBytesWithLength(valueBytes);
    buf.writeUB4(flags);
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final hasUser = userBytes.isNotEmpty ? 1 : 0;
    final params = conn.params;
    int numPairs;
    if (functionCode == TNS_FUNC_AUTH_PHASE_ONE) {
      numPairs = 5;
    } else if (changePassword) {
      _encryptPasswords();
      numPairs = 2;
    } else {
      numPairs = 4;
      if (token != null) {
        numPairs += 1;
        if (params.privateKey != null) numPairs += 2;
      } else {
        numPairs += 2;
        authMode |= TNS_AUTH_MODE_WITH_PASSWORD;
        if (verifierType == TNS_VERIFIER_TYPE_12C) {
          numPairs += 1;
        } else if (verifierType != TNS_VERIFIER_TYPE_11G_1 &&
            verifierType != TNS_VERIFIER_TYPE_11G_2) {
          throw dpyError(ERR_UNSUPPORTED_VERIFIER_TYPE,
              args: {'verifier_type': '0x${verifierType.toRadixString(16)}'});
        }
        _generateVerifier();
      }
      if (params.cclass != null) numPairs += 1;
      if (conn.effectivePurity.value != 0) numPairs += 1;
      if (newPassword != null) {
        numPairs += 1;
        authMode |= TNS_AUTH_MODE_CHANGE_PASSWORD;
      }
      if (params.proxyUser != null) numPairs += 1;
      if (params.edition != null) numPairs += 1;
      numPairs += params.appContext.length * 3;
      if (params.connectString != null) numPairs += 1;
    }

    writeFunctionCode(buf);
    buf.writeUint8(hasUser); // pointer (authusr)
    buf.writeUB4(userBytes.length);
    buf.writeUB4(authMode); // authentication mode
    buf.writeUint8(1); // pointer (authivl)
    buf.writeUB4(numPairs); // number of key/value pairs
    buf.writeUint8(1); // pointer (authovl)
    buf.writeUint8(1); // pointer (authovln)
    if (hasUser != 0) buf.writeBytesWithLength(userBytes);

    if (functionCode == TNS_FUNC_AUTH_PHASE_ONE) {
      _writeKeyValue(buf, 'AUTH_TERMINAL', params.terminal);
      _writeKeyValue(buf, 'AUTH_PROGRAM_NM', params.program);
      _writeKeyValue(buf, 'AUTH_MACHINE', params.machine);
      _writeKeyValue(buf, 'AUTH_PID', '$pid');
      _writeKeyValue(buf, 'AUTH_SID', params.osUser);
      return;
    }
    if (params.proxyUser != null) {
      _writeKeyValue(buf, 'PROXY_CLIENT_NAME', params.proxyUser!);
    }
    if (token != null) {
      _writeKeyValue(buf, 'AUTH_TOKEN', token!);
    } else if (!changePassword) {
      _writeKeyValue(buf, 'AUTH_SESSKEY', sessionKey!, 1);
      if (verifierType == TNS_VERIFIER_TYPE_12C) {
        _writeKeyValue(buf, 'AUTH_PBKDF2_SPEEDY_KEY', speedyKey!);
      }
    }
    if (encodedPassword != null) {
      _writeKeyValue(buf, 'AUTH_PASSWORD', encodedPassword!);
    }
    if (encodedNewPassword != null) {
      _writeKeyValue(buf, 'AUTH_NEWPASSWORD', encodedNewPassword!);
    }
    if (!changePassword) {
      _writeKeyValue(buf, 'SESSION_CLIENT_CHARSET', '873');
      _writeKeyValue(buf, 'SESSION_CLIENT_DRIVER_NAME',
          '$driverName thn : $driverVersion');
      _writeKeyValue(buf, 'SESSION_CLIENT_VERSION', '$_fullVersionNum');
      _writeKeyValue(buf, 'AUTH_ALTER_SESSION', _alterTimezoneStatement(), 1);
    }
    if (params.cclass != null) {
      _writeKeyValue(buf, 'AUTH_KPPL_CONN_CLASS', params.cclass!);
    }
    if (conn.effectivePurity.value != 0) {
      _writeKeyValue(
          buf, 'AUTH_KPPL_PURITY', '${conn.effectivePurity.value}', 1);
    }
    final privateKey = params.privateKey;
    if (token != null && privateKey != null) {
      // OCI IAM tokens: the request is signed with the private key
      final transport = conn.protocol.transport;
      final header = 'date: ${HttpDate.format(DateTime.now().toUtc())}\n'
          '(request-target): ${params.serviceName}\n'
          'host: ${transport.peerHost}:${transport.peerPort}';
      final signature =
          RsaPrivateKey.fromPem(privateKey).signSha256(utf8.encode(header));
      _writeKeyValue(buf, 'AUTH_HEADER', header);
      _writeKeyValue(buf, 'AUTH_SIGNATURE', base64.encode(signature));
    }
    if (params.edition != null) {
      _writeKeyValue(buf, 'AUTH_ORA_EDITION', params.edition!);
    }
    for (final entry in params.appContext) {
      // these keys require a trailing null character
      _writeKeyValue(buf, 'AUTH_APPCTX_NSPACE\x00', entry[0]);
      _writeKeyValue(buf, 'AUTH_APPCTX_ATTR\x00', entry[1]);
      _writeKeyValue(buf, 'AUTH_APPCTX_VALUE\x00', entry[2]);
    }
    if (params.connectString != null) {
      _writeKeyValue(buf, 'AUTH_CONNECT_STRING', params.connectString!);
    }
  }

  static int get _fullVersionNum {
    final parts = driverVersion.split('.').map(int.parse).toList();
    return parts[0] << 24 | parts[1] << 20 | parts[2] << 12;
  }
}

/// Sends the protocol, data types and first phase of authentication in a
/// single round trip (supported by Oracle Database 23ai and later).
class FastAuthMessage extends Message {
  FastAuthMessage(super.conn, this.protocolMessage, this.dataTypesMessage,
      this.authMessage);

  final ProtocolMessage protocolMessage;
  final DataTypesMessage dataTypesMessage;
  final AuthMessage authMessage;

  @override
  void processMessage(ReadBuffer buf, int messageType) {
    if (messageType == TNS_MSG_TYPE_PROTOCOL) {
      protocolMessage.processMessage(buf, messageType);
    } else if (messageType == TNS_MSG_TYPE_DATA_TYPES) {
      dataTypesMessage.processMessage(buf, messageType);
    } else {
      authMessage.processMessage(buf, messageType);
      endOfResponse = authMessage.endOfResponse;
    }
  }

  @override
  void process(ReadBuffer buf) {
    authMessage.endOfResponse = false;
    super.process(buf);
    callStatus = authMessage.callStatus;
    errorOccurred = authMessage.errorOccurred;
    errorInfo = authMessage.errorInfo;
  }

  @override
  void writeMessage(WriteBuffer buf) {
    buf.writeUint8(TNS_MSG_TYPE_FAST_AUTH);
    buf.writeUint8(1); // fast auth version
    buf.writeUint8(TNS_SERVER_CONVERTS_CHARS); // flag 1
    buf.writeUint8(0); // flag 2
    protocolMessage.writeMessage(buf);
    buf.writeUint16BE(0); // server charset (unused)
    buf.writeUint8(0); // server charset flag (unused)
    buf.writeUint16BE(0); // server ncharset (unused)
    buf.caps.ttcFieldVersion = TNS_CCAP_FIELD_VERSION_19_1_EXT_1;
    buf.writeUint8(buf.caps.ttcFieldVersion);
    dataTypesMessage.writeMessage(buf);
    authMessage.writeMessage(buf);
    buf.caps.ttcFieldVersion = TNS_CCAP_FIELD_VERSION_MAX;
  }
}
