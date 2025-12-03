// lib/src/thin/protocol/capabilities.dart

import 'dart:typed_data';
import 'package:oracledb_dart/src/exceptions.dart';
import 'constants.dart';

/// Represents the negotiated capabilities between the client and server.
/// This class holds information about supported features, protocol versions,
/// character sets, and other parameters determined during the connection handshake.
class Capabilities {
  late int protocolVersion;
  late int ttcFieldVersion;
  int charsetId = TNS_CHARSET_UTF8; // default UTF-8
  int ncharsetId = TNS_CHARSET_UTF16; // default UTF-16
  late Uint8List compileCaps;
  late Uint8List runtimeCaps;
  late int maxStringSize;
  bool supportsFastAuth = false;
  bool supportsOob = false;
  bool supportsOobCheck = false;
  bool supportsEndOfResponse = false;
  bool supportsPipelining = false;
  bool supportsRequestBoundaries = false;
  int sdu = 8192; // initial value to use

  Capabilities() {
    _initCompileCaps();
    _initRuntimeCaps();
  }

  /// Adjusts protocol capabilities based on the server's initial response.
  void adjustForProtocol(int protocolVersion, int protocolOptions, int flags) {
    this.protocolVersion = protocolVersion;
    supportsOob = (protocolOptions & TNS_GSO_CAN_RECV_ATTENTION) != 0;
    if ((flags & TNS_ACCEPT_FLAG_FAST_AUTH) != 0) {
      supportsFastAuth = true;
    }
    if ((flags & TNS_ACCEPT_FLAG_CHECK_OOB) != 0) {
      supportsOobCheck = true;
    }
    if (protocolVersion >= TNS_VERSION_MIN_END_OF_RESPONSE) {
      if ((flags & TNS_ACCEPT_FLAG_HAS_END_OF_RESPONSE) != 0) {
        compileCaps[TNS_CCAP_TTC4] |= TNS_CCAP_END_OF_RESPONSE;
        supportsEndOfResponse = true;
        supportsPipelining = true;
      }
    }
  }

  /// Adjusts capabilities based on the server's reported compile-time capabilities.
  void adjustForServerCompileCaps(Uint8List serverCaps) {
    if (serverCaps[TNS_CCAP_FIELD_VERSION] < ttcFieldVersion) {
      ttcFieldVersion = serverCaps[TNS_CCAP_FIELD_VERSION];
      compileCaps[TNS_CCAP_FIELD_VERSION] = ttcFieldVersion;
    }
    if ((serverCaps[TNS_CCAP_TTC4] & TNS_CCAP_EXPLICIT_BOUNDARY) != 0) {
      supportsRequestBoundaries = true;
    }
  }

  /// Adjusts capabilities based on the server's reported run-time capabilities.
  void adjustForServerRuntimeCaps(Uint8List serverCaps) {
    if ((serverCaps[TNS_RCAP_TTC] & TNS_RCAP_TTC_32K) != 0) {
      maxStringSize = 32767;
    } else {
      maxStringSize = 4000;
    }
    if ((serverCaps[TNS_RCAP_TTC] & TNS_RCAP_TTC_SESSION_STATE_OPS) == 0) {
      supportsRequestBoundaries = false;
    }
  }

  /// Checks if the national character set ID is supported (currently only UTF16).
  /// Throws [OracleNotSupportedError] if not supported.
  void checkNCharsetId() {
    if (ncharsetId != TNS_CHARSET_UTF16) {
      throw createOracleException(
        dpyCode: ERR_NCHAR_CS_NOT_SUPPORTED,
        message: 'National character set id $ncharsetId is not supported',
        context: 'The thin driver currently only supports AL16UTF16',
      );
    }
  }

  /// Initializes the client's compile-time capabilities array.
  void _initCompileCaps() {
    ttcFieldVersion = TNS_CCAP_FIELD_VERSION_MAX;
    compileCaps = Uint8List(TNS_CCAP_MAX); // Dart equivalent of bytearray

    compileCaps[TNS_CCAP_SQL_VERSION] = TNS_CCAP_SQL_VERSION_MAX;
    compileCaps[TNS_CCAP_LOGON_TYPES] = TNS_CCAP_O5LOGON |
        TNS_CCAP_O5LOGON_NP |
        TNS_CCAP_O7LOGON |
        TNS_CCAP_O8LOGON_LONG_IDENTIFIER |
        TNS_CCAP_O9LOGON_LONG_PASSWORD;
    compileCaps[TNS_CCAP_FEATURE_BACKPORT] = TNS_CCAP_CTB_IMPLICIT_POOL;
    compileCaps[TNS_CCAP_FIELD_VERSION] = ttcFieldVersion;
    compileCaps[TNS_CCAP_SERVER_DEFINE_CONV] = 1;
    compileCaps[TNS_CCAP_DEQUEUE_WITH_SELECTOR] = 1;
    compileCaps[TNS_CCAP_TTC1] = TNS_CCAP_FAST_BVEC |
        TNS_CCAP_END_OF_CALL_STATUS |
        TNS_CCAP_IND_RCD;
    compileCaps[TNS_CCAP_OCI1] = TNS_CCAP_FAST_SESSION_PROPAGATE |
        TNS_CCAP_APP_CTX_PIGGYBACK;
    compileCaps[TNS_CCAP_TDS_VERSION] = TNS_CCAP_TDS_VERSION_MAX;
    compileCaps[TNS_CCAP_RPC_VERSION] = TNS_CCAP_RPC_VERSION_MAX;
    compileCaps[TNS_CCAP_RPC_SIG] = TNS_CCAP_RPC_SIG_VALUE;
    compileCaps[TNS_CCAP_DBF_VERSION] = TNS_CCAP_DBF_VERSION_MAX;
    compileCaps[TNS_CCAP_LOB] = TNS_CCAP_LOB_UB8_SIZE |
        TNS_CCAP_LOB_ENCS |
        TNS_CCAP_LOB_PREFETCH_LENGTH |
        TNS_CCAP_LOB_TEMP_SIZE |
        TNS_CCAP_LOB_12C |
        TNS_CCAP_LOB_PREFETCH_DATA;
    compileCaps[TNS_CCAP_UB2_DTY] = 1;
    compileCaps[TNS_CCAP_LOB2] = TNS_CCAP_LOB2_QUASI |
        TNS_CCAP_LOB2_2GB_PREFETCH;
    compileCaps[TNS_CCAP_TTC3] = TNS_CCAP_IMPLICIT_RESULTS |
        TNS_CCAP_BIG_CHUNK_CLR |
        TNS_CCAP_KEEP_OUT_ORDER |
        TNS_CCAP_LTXID;
    compileCaps[TNS_CCAP_TTC2] = TNS_CCAP_ZLNP;
    compileCaps[TNS_CCAP_OCI2] = TNS_CCAP_DRCP;
    compileCaps[TNS_CCAP_CLIENT_FN] = TNS_CCAP_CLIENT_FN_MAX;
    compileCaps[TNS_CCAP_SESS_SIGNATURE_VERSION] = TNS_CCAP_FIELD_VERSION_12_2;
    compileCaps[TNS_CCAP_TTC4] = TNS_CCAP_INBAND_NOTIFICATION |
        TNS_CCAP_EXPLICIT_BOUNDARY;
    compileCaps[TNS_CCAP_TTC5] = TNS_CCAP_VECTOR_SUPPORT |
        TNS_CCAP_TOKEN_SUPPORTED |
        TNS_CCAP_PIPELINING_SUPPORT |
        TNS_CCAP_PIPELINING_BREAK;
    compileCaps[TNS_CCAP_VECTOR_FEATURES] = TNS_CCAP_VECTOR_FEATURE_BINARY |
        TNS_CCAP_VECTOR_FEATURE_SPARSE;
  }

  /// Initializes the client's run-time capabilities array.
  void _initRuntimeCaps() {
    runtimeCaps = Uint8List(TNS_RCAP_MAX); // Dart equivalent of bytearray

    runtimeCaps[TNS_RCAP_COMPAT] = TNS_RCAP_COMPAT_81;
    runtimeCaps[TNS_RCAP_TTC] = TNS_RCAP_TTC_ZERO_COPY | TNS_RCAP_TTC_32K;
  }
}
