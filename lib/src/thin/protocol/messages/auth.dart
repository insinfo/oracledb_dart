import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../exceptions.dart';
import '../constants.dart';
import '../packet.dart';
import '../../crypto.dart';
import 'base.dart';

const _clientDriverName = 'oracledb_dart thin dev';
const _clientVersion = '0.0.1';
const _defaultProgramName = 'oracledb_dart';

class AuthMessage extends Message {
  AuthMessage({
    required this.user,
    required this.password,
    required this.serviceName,
    required this.charsetId,
    required this.ncharsetId,
    required this.capabilities,
    this.includePassword = true,
    this.verifierType = TNS_VERIFIER_TYPE_11G,
    this.initialSessionData,
  });

  final String user;
  final String password;
  final String serviceName;
  final int charsetId;
  final int ncharsetId;
  final dynamic capabilities;
  final bool includePassword;
  int verifierType;
  final Map<String, String>? initialSessionData;

  Uint8List? _comboKey;
  Uint8List? _sessionKey;
  Map<String, String> sessionData = {};

  String get traceLabel => includePassword ? 'auth-phase2' : 'auth-phase1';

  @override
  void initializeHook() {
    sessionData = initialSessionData != null
        ? Map<String, String>.from(initialSessionData!)
        : <String, String>{};
    functionCode = includePassword
        ? TNS_FUNC_AUTH_PHASE_TWO
        : TNS_FUNC_AUTH_PHASE_ONE;
  }

  Uint8List buildRequest() {
    final phaseCode = includePassword
        ? TNS_FUNC_AUTH_PHASE_TWO
        : TNS_FUNC_AUTH_PHASE_ONE;
    final body = WriteBuffer();
    body.writeUint8(TNS_MSG_TYPE_FUNCTION);
    body.writeUint8(phaseCode);
    // Write sequence number (1 byte, increments per message)
    final seqNum = connImpl?.capabilities?.getNextSeqNum() ?? 1;
    body.writeUint8(seqNum);
    // Write token_num if TTC field version >= 18 (TNS_CCAP_FIELD_VERSION_23_1_EXT_1)
    final ttcFieldVersion = connImpl?.capabilities?.ttcFieldVersion ?? 0;
    if (ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_1) {
      body.writeUB8(0); // token_num = 0
    }

    final userBytes = Uint8List.fromList(utf8.encode(user));
    final authMode = includePassword
        ? (TNS_AUTH_MODE_LOGON | TNS_AUTH_MODE_WITH_PASSWORD)
        : TNS_AUTH_MODE_LOGON;
    final keyValues = includePassword
        ? _buildPhaseTwoKeyValues()
        : _buildPhaseOneKeyValues();

    final hasUser = userBytes.isNotEmpty ? 1 : 0;
    body.writeUint8(hasUser);
    body.writeUB4(userBytes.length);
    body.writeUB4(authMode);
    body.writeUint8(1); // pointer (authivl)
    body.writeUB4(keyValues.length);
    body.writeUint8(1); // pointer (authovl)
    body.writeUint8(1); // pointer (authovln)
    if (hasUser == 1) {
      body.writeBytesWithLength(userBytes);
    }

    for (final entry in keyValues) {
      _writeKeyValue(body, entry.key, entry.value, entry.flags);
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
  void processReturnParameters(ReadBuffer buf) {
    if (buf.isEOF) {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_FAILED,
        message: 'Empty AUTH response',
      );
    }

    final parsed = <String, String>{};
    final raw = <String>[];
    final numParams = buf.readUB2();
    for (var i = 0; i < numParams; i++) {
      final key = buf.readStringWithLength();
      final value = buf.readStringWithLength();
      if (key.isEmpty) {
        buf.skipUB4();
        continue;
      }
      if (key == 'AUTH_VFR_DATA') {
        final type = buf.readUB4();
        parsed[key] = value;
        raw.add('$key=$value');
        sessionData['AUTH_VFR_DATA'] = value;
        sessionData['AUTH_VFR_TYPE'] = type.toString();
        verifierType = type;
        continue;
      }
      parsed[key] = value;
      raw.add('$key=$value');
      buf.skipUB4();
    }

    if (raw.isNotEmpty) {
      parsed['AUTH_RAW_FIELDS'] = raw.join(';');
    }

    sessionData.addAll(parsed);
    connImpl?.sessionData = {...connImpl?.sessionData ?? {}, ...sessionData};

    final statusStr = sessionData['AUTH_STATUS'];
    if (statusStr != null && statusStr != '0') {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_FAILED,
        message: 'AUTH failed with status $statusStr',
      );
    }

    if (includePassword) {
      _applySessionMetadata();
    }

    if (_comboKey != null) connImpl?.comboKey = _comboKey;
    if (_sessionKey != null) connImpl?.sessionKey = _sessionKey;
  }

  List<_AuthKeyValue> _buildPhaseOneKeyValues() {
    return [
      _AuthKeyValue('AUTH_TERMINAL', _clientTerminal()),
      _AuthKeyValue('AUTH_PROGRAM_NM', _clientProgramName()),
      _AuthKeyValue('AUTH_MACHINE', _clientMachine()),
      _AuthKeyValue('AUTH_PID', _clientPid()),
      _AuthKeyValue('AUTH_SID', _clientOsUser()),
    ];
  }

  List<_AuthKeyValue> _buildPhaseTwoKeyValues() {
    if (!sessionData.containsKey('AUTH_VFR_DATA')) {
      throw createOracleException(
        dpyCode: ERR_CONNECTION_FAILED,
        message: 'Missing verifier data in AUTH session response',
      );
    }

    final verifier = _generateVerifierPayload();
    final values = <_AuthKeyValue>[
      _AuthKeyValue('AUTH_SESSKEY', verifier.sessionKeyHex, flags: 1),
      _AuthKeyValue('AUTH_PASSWORD', verifier.encryptedPasswordHex),
      _AuthKeyValue('SESSION_CLIENT_CHARSET', charsetId.toString()),
      _AuthKeyValue(
        'SESSION_CLIENT_DRIVER_NAME',
        _clientDriverName,
      ),
      _AuthKeyValue('SESSION_CLIENT_VERSION', _clientVersion),
      _AuthKeyValue('AUTH_ALTER_SESSION', _alterSessionStatement(), flags: 1),
    ];

    if (verifier.speedyKeyHex != null) {
      values.add(_AuthKeyValue('AUTH_PBKDF2_SPEEDY_KEY', verifier.speedyKeyHex!));
    }

    return values;
  }

  _VerifierResult _generateVerifierPayload() {
    String requireField(String name) {
      final value = sessionData[name] ?? connImpl?.sessionData?[name];
      if (value == null) {
        throw createOracleException(
          dpyCode: ERR_NOT_IMPLEMENTED,
          message: 'Missing $name in AUTH session data',
        );
      }
      return value;
    }

    final verifierData = hexToBytes(requireField('AUTH_VFR_DATA'));
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    Uint8List passwordHash;
    Uint8List? passwordKey;
    int keyLength;

    if (verifierType == TNS_VERIFIER_TYPE_12C) {
      keyLength = 32;
      final iterations =
          int.tryParse(requireField('AUTH_PBKDF2_VGEN_COUNT')) ?? 4096;
      final salt = concat([
        verifierData,
        Uint8List.fromList('AUTH_PBKDF2_SPEEDY_KEY'.codeUnits),
      ]);
      passwordKey = pbkdf2Sha512(
        password: passwordBytes,
        salt: salt,
        iterations: iterations,
        keyLength: 64,
      );
      final hInput = concat([passwordKey, verifierData]);
      passwordHash = sha512Bytes(hInput).sublist(0, 32);
    } else {
      keyLength = 24;
      final sha = sha1Bytes(passwordBytes);
      final hInput = concat([sha, verifierData]);
      final h = sha1Bytes(hInput);
      passwordHash = concat([h, Uint8List(4)]);
    }

    final encodedServerKey = hexToBytes(requireField('AUTH_SESSKEY'));
    final sessionKeyPartA = aesCbcDecrypt(
      key: passwordHash,
      iv: Uint8List(16),
      ciphertext: encodedServerKey,
      zeroPadding: true,
    );
    final sessionKeyPartB = randomBytes(sessionKeyPartA.length);
    final encodedClientKey = aesCbcEncrypt(
      key: passwordHash,
      iv: Uint8List(16),
      plaintext: sessionKeyPartB,
      zeroPadding: true,
    );

    Uint8List comboKey;
    String sessionKeyHex;
    if (sessionKeyPartA.length == 48) {
      sessionKeyHex = bytesToHex(encodedClientKey).substring(0, 96);
      final xorBuf = Uint8List(24);
      for (var i = 16; i < 40; i++) {
        xorBuf[i - 16] = sessionKeyPartA[i] ^ sessionKeyPartB[i];
      }
      final part1 = md5Bytes(xorBuf.sublist(0, 16));
      final part2 = md5Bytes(xorBuf.sublist(16));
      comboKey = concat([part1, part2]).sublist(0, keyLength);
    } else {
      sessionKeyHex = bytesToHex(encodedClientKey).substring(0, 64);
      final salt = hexToBytes(requireField('AUTH_PBKDF2_CSK_SALT'));
      final iterations =
          int.tryParse(requireField('AUTH_PBKDF2_SDER_COUNT')) ?? 4096;
      final tempKey = concat([
        sessionKeyPartB.sublist(0, keyLength),
        sessionKeyPartA.sublist(0, keyLength),
      ]);
      final tempKeyHexBytes =
          Uint8List.fromList(bytesToHex(tempKey).codeUnits);
      comboKey = pbkdf2Sha512(
        password: tempKeyHexBytes,
        salt: salt,
        iterations: iterations,
        keyLength: keyLength,
      );
    }

    String? speedyKeyHex;
    if (verifierType == TNS_VERIFIER_TYPE_12C && passwordKey != null) {
      final speedyPayload = concat([randomBytes(16), passwordKey]);
      final speedyKey = aesCbcEncrypt(
        key: comboKey,
        iv: Uint8List(16),
        plaintext: speedyPayload,
        zeroPadding: true,
      );
      speedyKeyHex = bytesToHex(speedyKey.sublist(0, 80));
    }

    final encryptedPassword = _encryptPassword(comboKey);

    _comboKey = comboKey;
    _sessionKey = hexToBytes(sessionKeyHex);
    sessionData['AUTH_SESSION_KEY'] = sessionKeyHex;
    sessionData['AUTH_ENC_PWD'] = bytesToHex(encryptedPassword);

    return _VerifierResult(
      sessionKeyHex: sessionKeyHex,
      encryptedPasswordHex: bytesToHex(encryptedPassword),
      speedyKeyHex: speedyKeyHex,
    );
  }

  Uint8List _encryptPassword(Uint8List comboKey) {
    final salt = randomBytes(16);
    final pwdBytes = Uint8List.fromList(utf8.encode(password));
    final payload = concat([salt, pwdBytes]);
    return aesCbcEncrypt(
      key: comboKey,
      iv: Uint8List(16),
      plaintext: payload,
      zeroPadding: true,
    );
  }

  void _applySessionMetadata() {
    final conn = connImpl;
    if (conn == null) {
      return;
    }
    conn.sessionData = {...conn.sessionData, ...sessionData};

    conn.sessionId = int.tryParse(sessionData['AUTH_SESSION_ID'] ?? '');
    conn.serialNum = int.tryParse(sessionData['AUTH_SERIAL_NUM'] ?? '');
    conn.dbDomain = sessionData['AUTH_SC_DB_DOMAIN'] ?? conn.dbDomain;
    conn.dbName = sessionData['AUTH_SC_DBUNIQUE_NAME'] ?? conn.dbName;
    conn.maxOpenCursors =
        int.tryParse(sessionData['AUTH_MAX_OPEN_CURSORS'] ?? '') ??
            conn.maxOpenCursors;
    conn.serviceFromServer =
        sessionData['AUTH_SC_SERVICE_NAME'] ?? conn.serviceFromServer;
    conn.instanceName = sessionData['AUTH_INSTANCENAME'] ?? conn.instanceName;
    conn.maxIdentifierLength =
        int.tryParse(sessionData['AUTH_MAX_IDEN_LENGTH'] ?? '') ??
            conn.maxIdentifierLength;

    final versionRaw = sessionData['AUTH_VERSION_NO'];
    if (versionRaw != null) {
      final parsedVersion = _getVersionTuple(int.tryParse(versionRaw));
      if (parsedVersion != null) {
        conn.serverVersion = parsedVersion;
      }
    }

    conn.supportsBool =
        capabilities.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1;
    conn.edition ??= sessionData['AUTH_ORA_EDITION'];

    final ltxid = sessionData['AUTH_LTXID'];
    if (ltxid != null && ltxid.isNotEmpty) {
      conn.ltxid = hexToBytes(ltxid);
    }

    conn.sessionSignature =
        sessionData['AUTH_SESSKEY'] ?? conn.sessionSignature;
  }

  List<int>? _getVersionTuple(int? fullVersionNum) {
    if (fullVersionNum == null) {
      return null;
    }
    if (capabilities.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_18_1_EXT_1) {
      return [
        (fullVersionNum >> 24) & 0xFF,
        (fullVersionNum >> 16) & 0xFF,
        (fullVersionNum >> 12) & 0x0F,
        (fullVersionNum >> 4) & 0xFF,
        fullVersionNum & 0x0F,
      ];
    }
    return [
      (fullVersionNum >> 24) & 0xFF,
      (fullVersionNum >> 20) & 0x0F,
      (fullVersionNum >> 12) & 0x0F,
      (fullVersionNum >> 8) & 0x0F,
      fullVersionNum & 0x0F,
    ];
  }

  void _writeKeyValue(WriteBuffer buf, String key, String value,
      int flags) {
    final keyBytes = utf8.encode(key);
    final valueBytes = utf8.encode(value);
    buf.writeUB4(keyBytes.length);
    buf.writeBytesWithLength(keyBytes);
    buf.writeUB4(valueBytes.length);
    if (valueBytes.isNotEmpty) {
      buf.writeBytesWithLength(valueBytes);
    }
    buf.writeUB4(flags);
  }
}

class _AuthKeyValue {
  const _AuthKeyValue(this.key, this.value, {this.flags = 0});

  final String key;
  final String value;
  final int flags;
}

class _VerifierResult {
  const _VerifierResult({
    required this.sessionKeyHex,
    required this.encryptedPasswordHex,
    this.speedyKeyHex,
  });

  final String sessionKeyHex;
  final String encryptedPasswordHex;
  final String? speedyKeyHex;
}

String _clientProgramName() {
  final override = Platform.environment['ORACLEDB_PROGRAM'];
  final exe = _sanitizeClientString(override ?? Platform.resolvedExecutable);
  return exe.isNotEmpty ? exe : _defaultProgramName;
}

String _clientOsUser() {
  final user = Platform.environment['USERNAME'] ??
      Platform.environment['USER'];
  final sanitized = _sanitizeClientString(user ?? '');
  return sanitized.isNotEmpty ? sanitized : 'dart';
}

String _clientMachine() {
  try {
    final host = Platform.localHostname;
    final sanitized = _sanitizeClientString(host);
    if (sanitized.isNotEmpty) {
      return sanitized;
    }
  } catch (_) {
    // ignore and fall back
  }
  return 'localhost';
}

String _clientTerminal() {
  final terminal = Platform.environment['ORACLE_TERMINAL'];
  final sanitized = _sanitizeClientString(terminal ?? '');
  if (sanitized.isNotEmpty) {
    return sanitized;
  }
  return 'unknown';
}

String _clientPid() {
  final override = Platform.environment['ORACLEDB_PID'];
  final sanitized = _sanitizeClientString(override ?? '');
  if (sanitized.isNotEmpty) {
    return sanitized;
  }
  return pid.toString();
}

String _alterSessionStatement() {
  final envTz = Platform.environment['ORA_SDTZ'];
  if (envTz != null && envTz.isNotEmpty) {
    return "ALTER SESSION SET TIME_ZONE='$envTz'\x00";
  }
  final offset = DateTime.now().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absMinutes = offset.inMinutes.abs();
  final hours = (absMinutes ~/ 60).clamp(0, 23);
  final minutes = absMinutes % 60;
  final tz =
      '$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  return "ALTER SESSION SET TIME_ZONE='$tz'\x00";
}

String _sanitizeClientString(String value) {
  final sb = StringBuffer();
  for (final code in value.codeUnits) {
    if (code >= 32 && code <= 126) {
      sb.writeCharCode(code);
    }
  }
  return sb.toString();
}