import 'dart:typed_data';

import 'constants.dart';

/// Capabilities negotiated with the server during connection establishment.
class Capabilities {
  Capabilities() {
    _initCompileCaps();
    _initRuntimeCaps();
  }

  int protocolVersion = 0;
  int ttcFieldVersion = TNS_CCAP_FIELD_VERSION_MAX;
  int charsetId = 0;
  int ncharsetId = 0;
  late Uint8List compileCaps;
  late Uint8List runtimeCaps;
  int maxStringSize = 4000;
  bool supportsFastAuth = false;
  bool supportsOob = false;
  bool supportsOobCheck = false;
  bool supportsEndOfResponse = false;
  bool supportsPipelining = false;
  bool supportsRequestBoundaries = false;
  int sdu = 8192;

  void adjustForProtocol(int version, int options, int flags) {
    protocolVersion = version;
    supportsOob = (options & TNS_GSO_CAN_RECV_ATTENTION) != 0;
    if (flags & TNS_ACCEPT_FLAG_FAST_AUTH != 0) supportsFastAuth = true;
    if (flags & TNS_ACCEPT_FLAG_CHECK_OOB != 0) supportsOobCheck = true;
    if (version >= TNS_VERSION_MIN_END_OF_RESPONSE &&
        flags & TNS_ACCEPT_FLAG_HAS_END_OF_RESPONSE != 0) {
      compileCaps[TNS_CCAP_TTC4] |= TNS_CCAP_END_OF_RESPONSE;
      supportsEndOfResponse = true;
      supportsPipelining = true;
    }
  }

  void adjustForServerCompileCaps(Uint8List serverCaps) {
    if (serverCaps[TNS_CCAP_FIELD_VERSION] < ttcFieldVersion) {
      ttcFieldVersion = serverCaps[TNS_CCAP_FIELD_VERSION];
      compileCaps[TNS_CCAP_FIELD_VERSION] = ttcFieldVersion;
    }
    if (serverCaps.length > TNS_CCAP_TTC4 &&
        serverCaps[TNS_CCAP_TTC4] & TNS_CCAP_EXPLICIT_BOUNDARY != 0) {
      supportsRequestBoundaries = true;
    }
  }

  void adjustForServerRuntimeCaps(Uint8List serverCaps) {
    if (serverCaps[TNS_RCAP_TTC] & TNS_RCAP_TTC_32K != 0) {
      maxStringSize = 32767;
    } else {
      maxStringSize = 4000;
    }
    if (serverCaps[TNS_RCAP_TTC] & TNS_RCAP_TTC_SESSION_STATE_OPS == 0) {
      supportsRequestBoundaries = false;
    }
  }

  void _initCompileCaps() {
    final c = compileCaps = Uint8List(TNS_CCAP_MAX);
    c[TNS_CCAP_SQL_VERSION] = TNS_CCAP_SQL_VERSION_MAX;
    c[TNS_CCAP_LOGON_TYPES] = TNS_CCAP_O5LOGON |
        TNS_CCAP_O5LOGON_NP |
        TNS_CCAP_O7LOGON |
        TNS_CCAP_O8LOGON_LONG_IDENTIFIER |
        TNS_CCAP_O9LOGON_LONG_PASSWORD;
    c[TNS_CCAP_FEATURE_BACKPORT] =
        TNS_CCAP_CTB_IMPLICIT_POOL | TNS_CCAP_CTB_OAUTH_MSG_ON_ERR;
    c[TNS_CCAP_FIELD_VERSION] = ttcFieldVersion;
    c[TNS_CCAP_SERVER_DEFINE_CONV] = 1;
    c[TNS_CCAP_DEQUEUE_WITH_SELECTOR] = 1;
    c[TNS_CCAP_TTC1] =
        TNS_CCAP_FAST_BVEC | TNS_CCAP_END_OF_CALL_STATUS | TNS_CCAP_IND_RCD;
    c[TNS_CCAP_OCI1] =
        TNS_CCAP_FAST_SESSION_PROPAGATE | TNS_CCAP_APP_CTX_PIGGYBACK;
    c[TNS_CCAP_TDS_VERSION] = TNS_CCAP_TDS_VERSION_MAX;
    c[TNS_CCAP_RPC_VERSION] = TNS_CCAP_RPC_VERSION_MAX;
    c[TNS_CCAP_RPC_SIG] = TNS_CCAP_RPC_SIG_VALUE;
    c[TNS_CCAP_DBF_VERSION] = TNS_CCAP_DBF_VERSION_MAX;
    c[TNS_CCAP_LOB] = TNS_CCAP_LOB_UB8_SIZE |
        TNS_CCAP_LOB_ENCS |
        TNS_CCAP_LOB_PREFETCH_LENGTH |
        TNS_CCAP_LOB_TEMP_SIZE |
        TNS_CCAP_LOB_12C |
        TNS_CCAP_LOB_PREFETCH_DATA;
    c[TNS_CCAP_UB2_DTY] = 1;
    c[TNS_CCAP_LOB2] = TNS_CCAP_LOB2_QUASI | TNS_CCAP_LOB2_2GB_PREFETCH;
    c[TNS_CCAP_TTC3] = TNS_CCAP_IMPLICIT_RESULTS |
        TNS_CCAP_BIG_CHUNK_CLR |
        TNS_CCAP_KEEP_OUT_ORDER |
        TNS_CCAP_LTXID;
    c[TNS_CCAP_TTC2] = TNS_CCAP_ZLNP;
    c[TNS_CCAP_OCI2] = TNS_CCAP_DRCP;
    c[TNS_CCAP_CLIENT_FN] = TNS_CCAP_CLIENT_FN_MAX;
    c[TNS_CCAP_SESS_SIGNATURE_VERSION] = TNS_CCAP_FIELD_VERSION_12_2;
    c[TNS_CCAP_TTC4] =
        TNS_CCAP_INBAND_NOTIFICATION | TNS_CCAP_EXPLICIT_BOUNDARY;
    c[TNS_CCAP_TTC5] = TNS_CCAP_VECTOR_SUPPORT |
        TNS_CCAP_TOKEN_SUPPORTED |
        TNS_CCAP_PIPELINING_SUPPORT |
        TNS_CCAP_PIPELINING_BREAK |
        TNS_CCAP_TTC5_SESSIONLESS_TXNS;
    c[TNS_CCAP_VECTOR_FEATURES] =
        TNS_CCAP_VECTOR_FEATURE_BINARY | TNS_CCAP_VECTOR_FEATURE_SPARSE;
    c[TNS_CCAP_OCI3] = TNS_CCAP_OCI3_OCSSYNC;
  }

  void _initRuntimeCaps() {
    final r = runtimeCaps = Uint8List(TNS_RCAP_MAX);
    r[TNS_RCAP_COMPAT] = TNS_RCAP_COMPAT_81;
    r[TNS_RCAP_TTC] = TNS_RCAP_TTC_ZERO_COPY | TNS_RCAP_TTC_32K;
  }
}
