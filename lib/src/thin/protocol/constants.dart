// lib/src/thin/protocol/constants.dart

// ignore_for_file: constant_identifier_names

// packet types
const int TNS_PACKET_TYPE_CONNECT = 1;
const int TNS_PACKET_TYPE_ACCEPT = 2;
const int TNS_PACKET_TYPE_REFUSE = 4;
const int TNS_PACKET_TYPE_DATA = 6;
const int TNS_PACKET_TYPE_RESEND = 11;
const int TNS_PACKET_TYPE_MARKER = 12;
const int TNS_PACKET_TYPE_CONTROL = 14;
const int TNS_PACKET_TYPE_REDIRECT = 5;

// packet flags
const int TNS_PACKET_FLAG_REDIRECT = 0x04;
const int TNS_PACKET_FLAG_TLS_RENEG = 0x08;

// data flags
const int TNS_DATA_FLAGS_BEGIN_PIPELINE = 0x1000;
const int TNS_DATA_FLAGS_END_OF_REQUEST = 0x800;
const int TNS_DATA_FLAGS_END_OF_RESPONSE = 0x2000;
const int TNS_DATA_FLAGS_EOF = 0x0040;

// marker types
const int TNS_MARKER_TYPE_BREAK = 1;
const int TNS_MARKER_TYPE_RESET = 2;
const int TNS_MARKER_TYPE_INTERRUPT = 3;

// AQ delivery modes
const int TNS_AQ_MSG_BUFFERED = 2;
const int TNS_AQ_MSG_PERSISTENT = 1;
const int TNS_AQ_MSG_PERSISTENT_OR_BUFFERED = 3;

// AQ dequeue modes
const int TNS_AQ_DEQ_BROWSE = 1;
const int TNS_AQ_DEQ_LOCKED = 2;
const int TNS_AQ_DEQ_REMOVE = 3;
const int TNS_AQ_DEQ_REMOVE_NODATA = 4;

// AQ dequeue navigation modes
const int TNS_AQ_DEQ_FIRST_MSG = 1;
const int TNS_AQ_DEQ_NEXT_MSG = 3;
const int TNS_AQ_DEQ_NEXT_TRANSACTION = 2;

// AQ dequeue visibility modes
const int TNS_AQ_DEQ_IMMEDIATE = 1;
const int TNS_AQ_DEQ_ON_COMMIT = 2;

// AQ dequeue wait modes
const int TNS_AQ_DEQ_NO_WAIT = 0;
const int TNS_AQ_DEQ_WAIT_FOREVER = 0xFFFFFFFF; // 4294967295

// AQ enqueue visibility modes
const int TNS_AQ_ENQ_IMMEDIATE = 1;
const int TNS_AQ_ENQ_ON_COMMIT = 2;

// AQ message states
const int TNS_AQ_MSG_EXPIRED = 3;
const int TNS_AQ_MSG_PROCESSED = 2;
const int TNS_AQ_MSG_READY = 0;
const int TNS_AQ_MSG_WAITING = 1;

// AQ other constants
const int TNS_AQ_MSG_NO_DELAY = 0;
const int TNS_AQ_MSG_NO_EXPIRATION = -1;
const int TNS_AQ_ARRAY_ENQ = 0x01;
const int TNS_AQ_ARRAY_DEQ = 0x02;
const int TNS_AQ_ARRAY_FLAGS_RETURN_MESSAGE_ID = 0x01;
const int TNS_TTC_ENQ_STREAMING_ENABLED = 0x00000001;
const int TNS_TTC_ENQ_STREAMING_DISABLED = 0x00000000;

// AQ flags
const int TNS_KPD_AQ_BUFMSG = 0x02;
const int TNS_KPD_AQ_EITHER = 0x10;

// errors (internal TNS codes, not usually exposed directly as exceptions)
const int TNS_ERR_INCONSISTENT_DATA_TYPES = 932;
const int TNS_ERR_VAR_NOT_IN_SELECT_LIST = 1007;
const int TNS_ERR_INBAND_MESSAGE = 12573;
const int TNS_ERR_INVALID_SERVICE_NAME = 12514;
const int TNS_ERR_INVALID_SID = 12505;
const int TNS_ERR_NO_DATA_FOUND = 1403;
const int TNS_ERR_SESSION_SHUTDOWN = 12572;
const int TNS_ERR_ARRAY_DML_ERRORS = 24381;
const int TNS_ERR_EXCEEDED_IDLE_TIME = 2396;
const int TNS_ERR_NO_MESSAGES_FOUND = 25228;

// message types
const int TNS_MSG_TYPE_PROTOCOL = 1;
const int TNS_MSG_TYPE_DATA_TYPES = 2;
const int TNS_MSG_TYPE_FUNCTION = 3;
const int TNS_MSG_TYPE_ERROR = 4;
const int TNS_MSG_TYPE_ROW_HEADER = 6;
const int TNS_MSG_TYPE_ROW_DATA = 7;
const int TNS_MSG_TYPE_PARAMETER = 8;
const int TNS_MSG_TYPE_STATUS = 9;
const int TNS_MSG_TYPE_IO_VECTOR = 11;
const int TNS_MSG_TYPE_LOB_DATA = 14;
const int TNS_MSG_TYPE_WARNING = 15;
const int TNS_MSG_TYPE_DESCRIBE_INFO = 16;
const int TNS_MSG_TYPE_PIGGYBACK = 17;
const int TNS_MSG_TYPE_FLUSH_OUT_BINDS = 19;
const int TNS_MSG_TYPE_BIT_VECTOR = 21;
const int TNS_MSG_TYPE_SERVER_SIDE_PIGGYBACK = 23;
const int TNS_MSG_TYPE_ONEWAY_FN = 26;
const int TNS_MSG_TYPE_IMPLICIT_RESULTSET = 27;
const int TNS_MSG_TYPE_RENEGOTIATE = 28;
const int TNS_MSG_TYPE_END_OF_RESPONSE = 29;
const int TNS_MSG_TYPE_TOKEN = 33;
const int TNS_MSG_TYPE_FAST_AUTH = 34;

// parameter keyword numbers
const int TNS_KEYWORD_NUM_CURRENT_SCHEMA = 168;
const int TNS_KEYWORD_NUM_EDITION = 172;

// bind flags
const int TNS_BIND_USE_INDICATORS = 0x0001;
const int TNS_BIND_ARRAY = 0x0040;

// bind directions
const int TNS_BIND_DIR_OUTPUT = 16;
const int TNS_BIND_DIR_INPUT = 32;
const int TNS_BIND_DIR_INPUT_OUTPUT = 48;

// database object image flags
const int TNS_OBJ_IS_VERSION_81 = 0x80;
const int TNS_OBJ_IS_DEGENERATE = 0x10;
const int TNS_OBJ_IS_COLLECTION = 0x08;
const int TNS_OBJ_NO_PREFIX_SEG = 0x04;
const int TNS_OBJ_IMAGE_VERSION = 1;

// database object flags
const int TNS_OBJ_MAX_SHORT_LENGTH = 245;
const int TNS_OBJ_ATOMIC_NULL = 253;
const int TNS_OBJ_NON_NULL_OID = 0x02;
const int TNS_OBJ_HAS_EXTENT_OID = 0x08;
const int TNS_OBJ_TOP_LEVEL = 0x01;
const int TNS_OBJ_HAS_INDEXES = 0x10;

// database object collection types
const int TNS_OBJ_PLSQL_INDEX_TABLE = 1;
const int TNS_OBJ_NESTED_TABLE = 2;
const int TNS_OBJ_VARRAY = 3;

// database object TDS type codes
const int TNS_OBJ_TDS_TYPE_CHAR = 1;
const int TNS_OBJ_TDS_TYPE_DATE = 2;
const int TNS_OBJ_TDS_TYPE_FLOAT = 5;
const int TNS_OBJ_TDS_TYPE_NUMBER = 6;
const int TNS_OBJ_TDS_TYPE_VARCHAR = 7;
const int TNS_OBJ_TDS_TYPE_BOOLEAN = 8;
const int TNS_OBJ_TDS_TYPE_RAW = 19;
const int TNS_OBJ_TDS_TYPE_TIMESTAMP = 21;
const int TNS_OBJ_TDS_TYPE_TIMESTAMP_TZ = 23;
const int TNS_OBJ_TDS_TYPE_OBJ = 27;
const int TNS_OBJ_TDS_TYPE_COLL = 28;
const int TNS_OBJ_TDS_TYPE_CLOB = 29;
const int TNS_OBJ_TDS_TYPE_BLOB = 30;
const int TNS_OBJ_TDS_TYPE_TIMESTAMP_LTZ = 33;
const int TNS_OBJ_TDS_TYPE_BINARY_FLOAT = 37;
const int TNS_OBJ_TDS_TYPE_START_EMBED_ADT = 39;
const int TNS_OBJ_TDS_TYPE_END_EMBED_ADT = 40;
const int TNS_OBJ_TDS_TYPE_SUBTYPE_MARKER = 43;
const int TNS_OBJ_TDS_TYPE_EMBED_ADT_INFO = 44;
const int TNS_OBJ_TDS_TYPE_BINARY_DOUBLE = 45;

// xml type constants
const int TNS_XML_TYPE_LOB = 0x0001;
const int TNS_XML_TYPE_STRING = 0x0004;
const int TNS_XML_TYPE_FLAG_SKIP_NEXT_4 = 0x100000;

// execute options
const int TNS_EXEC_OPTION_PARSE = 0x01;
const int TNS_EXEC_OPTION_BIND = 0x08;
const int TNS_EXEC_OPTION_DEFINE = 0x10;
const int TNS_EXEC_OPTION_EXECUTE = 0x20;
const int TNS_EXEC_OPTION_FETCH = 0x40;
const int TNS_EXEC_OPTION_COMMIT = 0x100;
const int TNS_EXEC_OPTION_COMMIT_REEXECUTE = 0x1;
const int TNS_EXEC_OPTION_PLSQL_BIND = 0x400;
const int TNS_EXEC_OPTION_NOT_PLSQL = 0x8000;
const int TNS_EXEC_OPTION_DESCRIBE = 0x20000;
const int TNS_EXEC_OPTION_NO_COMPRESSED_FETCH = 0x40000;
const int TNS_EXEC_OPTION_BATCH_ERRORS = 0x80000;

// execute flags
const int TNS_EXEC_FLAGS_DML_ROWCOUNTS = 0x4000;
const int TNS_EXEC_FLAGS_IMPLICIT_RESULTSET = 0x8000;
const int TNS_EXEC_FLAGS_SCROLLABLE = 0x02;

// fetch orientations
const int TNS_FETCH_ORIENTATION_ABSOLUTE = 0x20;
const int TNS_FETCH_ORIENTATION_CURRENT = 0x01;
const int TNS_FETCH_ORIENTATION_FIRST = 0x04;
const int TNS_FETCH_ORIENTATION_LAST = 0x08;
const int TNS_FETCH_ORIENTATION_NEXT = 0x02;
const int TNS_FETCH_ORIENTATION_PRIOR = 0x10;
const int TNS_FETCH_ORIENTATION_RELATIVE = 0x40;

// server side piggyback op codes
const int TNS_SERVER_PIGGYBACK_QUERY_CACHE_INVALIDATION = 1;
const int TNS_SERVER_PIGGYBACK_OS_PID_MTS = 2;
const int TNS_SERVER_PIGGYBACK_TRACE_EVENT = 3;
const int TNS_SERVER_PIGGYBACK_SESS_RET = 4;
const int TNS_SERVER_PIGGYBACK_SYNC = 5;
const int TNS_SERVER_PIGGYBACK_LTXID = 7;
const int TNS_SERVER_PIGGYBACK_AC_REPLAY_CONTEXT = 8;
const int TNS_SERVER_PIGGYBACK_EXT_SYNC = 9;
const int TNS_SERVER_PIGGYBACK_SESS_SIGNATURE = 10;

// session return constants
const int TNS_SESSGET_SESSION_CHANGED = 4;

// LOB operations
const int TNS_LOB_OP_GET_LENGTH = 0x0001;
const int TNS_LOB_OP_READ = 0x0002;
const int TNS_LOB_OP_TRIM = 0x0020;
const int TNS_LOB_OP_WRITE = 0x0040;
const int TNS_LOB_OP_GET_CHUNK_SIZE = 0x4000;
const int TNS_LOB_OP_CREATE_TEMP = 0x0110;
const int TNS_LOB_OP_FREE_TEMP = 0x0111;
const int TNS_LOB_OP_OPEN = 0x8000;
const int TNS_LOB_OP_CLOSE = 0x10000;
const int TNS_LOB_OP_IS_OPEN = 0x11000;
const int TNS_LOB_OP_ARRAY = 0x80000;
const int TNS_LOB_OP_FILE_EXISTS = 0x0800;
const int TNS_LOB_OP_FILE_OPEN = 0x0100;
const int TNS_LOB_OP_FILE_CLOSE = 0x0200;
const int TNS_LOB_OP_FILE_ISOPEN = 0x0400;

// LOB locator constants
const int TNS_LOB_LOC_OFFSET_FLAG_1 = 4;
const int TNS_LOB_LOC_OFFSET_FLAG_3 = 6;
const int TNS_LOB_LOC_OFFSET_FLAG_4 = 7;
const int TNS_LOB_QLOCATOR_VERSION = 4;
const int TNS_LOB_LOC_FIXED_OFFSET = 16;

// LOB locator flags (byte 1)
const int TNS_LOB_LOC_FLAGS_BLOB = 0x01;
const int TNS_LOB_LOC_FLAGS_VALUE_BASED = 0x20;
const int TNS_LOB_LOC_FLAGS_ABSTRACT = 0x40;

// LOB locator flags (byte 2)
const int TNS_LOB_LOC_FLAGS_INIT = 0x08;

// LOB locator flags (byte 4)
const int TNS_LOB_LOC_FLAGS_TEMP = 0x01;
const int TNS_LOB_LOC_FLAGS_VAR_LENGTH_CHARSET = 0x80;

// other LOB constants
const int TNS_LOB_OPEN_READ_WRITE = 2;
const int TNS_LOB_OPEN_READ_ONLY = 11;
const int TNS_LOB_PREFETCH_FLAG = 0x2000000;

// end-to-end metrics
const int TNS_END_TO_END_ACTION = 0x0010;
const int TNS_END_TO_END_CLIENT_IDENTIFIER = 0x0001;
const int TNS_END_TO_END_CLIENT_INFO = 0x0100;
const int TNS_END_TO_END_DBOP = 0x0200;
const int TNS_END_TO_END_MODULE = 0x0008;

// versions
const int TNS_VERSION_DESIRED = 319;
const int TNS_VERSION_MINIMUM = 300;
const int TNS_VERSION_MIN_ACCEPTED = 315;      // 12.1
const int TNS_VERSION_MIN_LARGE_SDU = 315;
const int TNS_VERSION_MIN_OOB_CHECK = 318;
const int TNS_VERSION_MIN_END_OF_RESPONSE = 319;

// control packet types
const int TNS_CONTROL_TYPE_INBAND_NOTIFICATION = 8;
const int TNS_CONTROL_TYPE_RESET_OOB = 9;

// connect flags
const int TNS_GSO_DONT_CARE = 0x0001;
const int TNS_GSO_CAN_RECV_ATTENTION = 0x0400;
const int TNS_NSI_NA_REQUIRED = 0x10;
const int TNS_NSI_DISABLE_NA = 0x04;
const int TNS_NSI_SUPPORT_SECURITY_RENEG = 0x80;

// other connection constants
const int TNS_PROTOCOL_CHARACTERISTICS = 0x4f98;
const int TNS_CHECK_OOB = 0x01;

// TTC functions
const int TNS_FUNC_AUTH_PHASE_ONE = 118;
const int TNS_FUNC_AUTH_PHASE_TWO = 115;
const int TNS_FUNC_CLOSE_CURSORS = 105;
const int TNS_FUNC_COMMIT = 14;
const int TNS_FUNC_EXECUTE = 94;
const int TNS_FUNC_FETCH = 5;
const int TNS_FUNC_LOB_OP = 96;
const int TNS_FUNC_AQ_ENQ = 121;
const int TNS_FUNC_AQ_DEQ = 122;
const int TNS_FUNC_ARRAY_AQ = 145;
const int TNS_FUNC_LOGOFF = 9;
const int TNS_FUNC_PING = 147;
const int TNS_FUNC_PIPELINE_BEGIN = 199;
const int TNS_FUNC_PIPELINE_END = 200;
const int TNS_FUNC_ROLLBACK = 15;
const int TNS_FUNC_SET_END_TO_END_ATTR = 135;
const int TNS_FUNC_REEXECUTE = 4;
const int TNS_FUNC_REEXECUTE_AND_FETCH = 78;
const int TNS_FUNC_SESSION_GET = 162;
const int TNS_FUNC_SESSION_RELEASE = 163;
const int TNS_FUNC_SESSION_STATE = 176;
const int TNS_FUNC_SET_SCHEMA = 152;
const int TNS_FUNC_TPC_TXN_SWITCH = 103;
const int TNS_FUNC_TPC_TXN_CHANGE_STATE = 104;

// TTC authentication modes
const int TNS_AUTH_MODE_LOGON = 0x00000001;
const int TNS_AUTH_MODE_CHANGE_PASSWORD = 0x00000002;
const int TNS_AUTH_MODE_SYSDBA = 0x00000020;
const int TNS_AUTH_MODE_SYSOPER = 0x00000040;
const int TNS_AUTH_MODE_WITH_PASSWORD = 0x00000100;
const int TNS_AUTH_MODE_SYSASM = 0x00400000;
const int TNS_AUTH_MODE_SYSBKP = 0x01000000;
const int TNS_AUTH_MODE_SYSDGD = 0x02000000;
const int TNS_AUTH_MODE_SYSKMT = 0x04000000;
const int TNS_AUTH_MODE_SYSRAC = 0x08000000;
const int TNS_AUTH_MODE_IAM_TOKEN = 0x20000000;

// character sets and encodings
const int TNS_CHARSET_UTF8 = 873;
const int TNS_CHARSET_UTF16 = 2000;
const int TNS_ENCODING_MULTI_BYTE = 0x01;
const int TNS_ENCODING_CONV_LENGTH = 0x02;

// compile time capability indices
const int TNS_CCAP_SQL_VERSION = 0;
const int TNS_CCAP_LOGON_TYPES = 4;
const int TNS_CCAP_FEATURE_BACKPORT = 5;
const int TNS_CCAP_FIELD_VERSION = 7;
const int TNS_CCAP_SERVER_DEFINE_CONV = 8;
const int TNS_CCAP_DEQUEUE_WITH_SELECTOR = 9;
const int TNS_CCAP_TTC1 = 15;
const int TNS_CCAP_OCI1 = 16;
const int TNS_CCAP_TDS_VERSION = 17;
const int TNS_CCAP_RPC_VERSION = 18;
const int TNS_CCAP_RPC_SIG = 19;
const int TNS_CCAP_DBF_VERSION = 21;
const int TNS_CCAP_LOB = 23;
const int TNS_CCAP_TTC2 = 26;
const int TNS_CCAP_UB2_DTY = 27;
const int TNS_CCAP_OCI2 = 31;
const int TNS_CCAP_CLIENT_FN = 34;
const int TNS_CCAP_TTC3 = 37;
const int TNS_CCAP_SESS_SIGNATURE_VERSION = 39;
const int TNS_CCAP_TTC4 = 40;
const int TNS_CCAP_LOB2 = 42;
const int TNS_CCAP_TTC5 = 44;
const int TNS_CCAP_VECTOR_FEATURES = 52;
const int TNS_CCAP_MAX = 53;

// compile time capability values
const int TNS_CCAP_SQL_VERSION_MAX = 6;
const int TNS_CCAP_FIELD_VERSION_11_2 = 6;
const int TNS_CCAP_FIELD_VERSION_12_1 = 7;
const int TNS_CCAP_FIELD_VERSION_12_2 = 8;
const int TNS_CCAP_FIELD_VERSION_12_2_EXT1 = 9;
const int TNS_CCAP_FIELD_VERSION_18_1 = 10;
const int TNS_CCAP_FIELD_VERSION_18_1_EXT_1 = 11;
const int TNS_CCAP_FIELD_VERSION_19_1 = 12;
const int TNS_CCAP_FIELD_VERSION_19_1_EXT_1 = 13;
const int TNS_CCAP_FIELD_VERSION_20_1 = 14;
const int TNS_CCAP_FIELD_VERSION_20_1_EXT_1 = 15;
const int TNS_CCAP_FIELD_VERSION_21_1 = 16;
const int TNS_CCAP_FIELD_VERSION_23_1 = 17;
const int TNS_CCAP_FIELD_VERSION_23_1_EXT_1 = 18;
const int TNS_CCAP_FIELD_VERSION_23_1_EXT_2 = 19;
const int TNS_CCAP_FIELD_VERSION_23_1_EXT_3 = 20;
const int TNS_CCAP_FIELD_VERSION_23_1_EXT_4 = 21;
const int TNS_CCAP_FIELD_VERSION_23_1_EXT_5 = 22;
const int TNS_CCAP_FIELD_VERSION_23_3_EXT_6 = 23;
const int TNS_CCAP_FIELD_VERSION_23_4 = 24;
const int TNS_CCAP_FIELD_VERSION_MAX = 24;
const int TNS_CCAP_O5LOGON = 8;
const int TNS_CCAP_O5LOGON_NP = 2;
const int TNS_CCAP_O7LOGON = 32;
const int TNS_CCAP_O8LOGON_LONG_IDENTIFIER = 64;
const int TNS_CCAP_O9LOGON_LONG_PASSWORD = 0x80;
const int TNS_CCAP_CTB_IMPLICIT_POOL = 0x08;
const int TNS_CCAP_END_OF_CALL_STATUS = 0x01;
const int TNS_CCAP_IND_RCD = 0x08;
const int TNS_CCAP_FAST_BVEC = 0x20;
const int TNS_CCAP_FAST_SESSION_PROPAGATE = 0x10;
const int TNS_CCAP_APP_CTX_PIGGYBACK = 0x80;
const int TNS_CCAP_TDS_VERSION_MAX = 3;
const int TNS_CCAP_RPC_VERSION_MAX = 7;
const int TNS_CCAP_RPC_SIG_VALUE = 3;
const int TNS_CCAP_DBF_VERSION_MAX = 1;
const int TNS_CCAP_LTXID = 0x08;
const int TNS_CCAP_IMPLICIT_RESULTS = 0x10;
const int TNS_CCAP_BIG_CHUNK_CLR = 0x20;
const int TNS_CCAP_KEEP_OUT_ORDER = 0x80;
const int TNS_CCAP_LOB_UB8_SIZE = 0x01;
const int TNS_CCAP_LOB_ENCS = 0x02;
const int TNS_CCAP_LOB_PREFETCH_DATA = 0x04;
const int TNS_CCAP_LOB_TEMP_SIZE = 0x08;
const int TNS_CCAP_LOB_PREFETCH_LENGTH = 0x40;
const int TNS_CCAP_LOB_12C = 0x80;
const int TNS_CCAP_LOB2_QUASI = 0x01;
const int TNS_CCAP_LOB2_2GB_PREFETCH = 0x04;
const int TNS_CCAP_DRCP = 0x10;
const int TNS_CCAP_ZLNP = 0x04;
const int TNS_CCAP_INBAND_NOTIFICATION = 0x04;
const int TNS_CCAP_EXPLICIT_BOUNDARY = 0x40;
const int TNS_CCAP_END_OF_RESPONSE = 0x20;
const int TNS_CCAP_CLIENT_FN_MAX = 12;
const int TNS_CCAP_VECTOR_SUPPORT = 0x08;
const int TNS_CCAP_TOKEN_SUPPORTED = 0x02;
const int TNS_CCAP_PIPELINING_SUPPORT = 0x04;
const int TNS_CCAP_PIPELINING_BREAK = 0x10;
const int TNS_CCAP_VECTOR_FEATURE_BINARY = 0x01;
const int TNS_CCAP_VECTOR_FEATURE_SPARSE = 0x02;

// runtime capability indices
const int TNS_RCAP_COMPAT = 0;
const int TNS_RCAP_TTC = 6;
const int TNS_RCAP_MAX = 11;

// runtime capability values
const int TNS_RCAP_COMPAT_81 = 2;
const int TNS_RCAP_TTC_ZERO_COPY = 0x01;
const int TNS_RCAP_TTC_32K = 0x04;
const int TNS_RCAP_TTC_SESSION_STATE_OPS = 0x10;

// verifier types
const int TNS_VERIFIER_TYPE_11G_1 = 0xb152;
const int TNS_VERIFIER_TYPE_11G_2 = 0x1b25;
const int TNS_VERIFIER_TYPE_12C = 0x4815;

// UDS flags
const int TNS_UDS_FLAGS_IS_JSON = 0x00000100;
const int TNS_UDS_FLAGS_IS_OSON = 0x00000800;

// end of call status flags
const int TNS_EOCS_FLAGS_TXN_IN_PROGRESS = 0x00000002;
const int TNS_EOCS_FLAGS_SESS_RELEASE = 0x00008000;

// accept flags
const int TNS_ACCEPT_FLAG_CHECK_OOB = 0x00000001;
const int TNS_ACCEPT_FLAG_FAST_AUTH = 0x10000000;
const int TNS_ACCEPT_FLAG_HAS_END_OF_RESPONSE = 0x02000000;

// transaction switching op codes
const int TNS_TPC_TXN_START = 0x01;
const int TNS_TPC_TXN_DETACH = 0x02;

// transaction change state op codes
const int TNS_TPC_TXN_COMMIT = 0x01;
const int TNS_TPC_TXN_ABORT = 0x02;
const int TNS_TPC_TXN_PREPARE = 0x03;
const int TNS_TPC_TXN_FORGET = 0x04;

// transaction states
const int TNS_TPC_TXN_STATE_PREPARE = 0;
const int TNS_TPC_TXN_STATE_REQUIRES_COMMIT = 1;
const int TNS_TPC_TXN_STATE_COMMITTED = 2;
const int TNS_TPC_TXN_STATE_ABORTED = 3;
const int TNS_TPC_TXN_STATE_READ_ONLY = 4;
const int TNS_TPC_TXN_STATE_FORGOTTEN = 5;

// pipeline modes
const int TNS_PIPELINE_MODE_CONTINUE_ON_ERROR = 1;
const int TNS_PIPELINE_MODE_ABORT_ON_ERROR = 2;

// AQ extension keywords
const int TNS_AQ_EXT_KEYWORD_AGENT_NAME = 64;
const int TNS_AQ_EXT_KEYWORD_AGENT_ADDRESS = 65;
const int TNS_AQ_EXT_KEYWORD_AGENT_PROTOCOL = 66;
const int TNS_AQ_EXT_KEYWORD_ORIGINAL_MSGID = 69;

// session state flags
const int TNS_SESSION_STATE_REQUEST_BEGIN = 0x04;
const int TNS_SESSION_STATE_REQUEST_END = 0x08;
const int TNS_SESSION_STATE_EXPLICIT_BOUNDARY = 0x40;

// other constants
const int TNS_ESCAPE_CHAR = 253;
const int TNS_MAX_ROWID_LENGTH = 18;
const int TNS_DURATION_SESSION = 10;
const int TNS_MAX_LONG_LENGTH = 0x7fffffff; // 2147483647
const int TNS_MAX_CONNECT_DATA = 230;
const int TNS_MAX_UROWID_LENGTH = 5267;
const int TNS_SERVER_CONVERTS_CHARS = 0x01;
const int TNS_JSON_MAX_LENGTH = 32 * 1024 * 1024; // 33554432
const int TNS_VECTOR_MAX_LENGTH = 1 * 1024 * 1024; // 1048576
const int TNS_AQ_MESSAGE_ID_LENGTH = 16;
const int TNS_AQ_MESSAGE_VERSION = 1;

// base 64 encoding alphabet (as List<int> for direct use)
final List<int> TNS_BASE64_ALPHABET_ARRAY =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'.codeUnits;
// final Uint8List TNS_EXTENT_OID = Uint8List.fromList(
//    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]); // Hex '00000000000000000000000000010001'

// drcp release mode
const int DRCP_DEAUTHENTICATE = 0x00000002;