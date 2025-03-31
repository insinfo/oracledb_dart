// ignore_for_file: constant_identifier_names

// mandated DB API constants
const String API_LEVEL = "2.0";
const int THREAD_SAFETY = 2;
const String PARAM_STYLE = "named";

// AQ dequeue wait modes
const int DEQ_NO_WAIT = 0;
// Note: 2**32 - 1 is the maximum value for an unsigned 32-bit integer
const int DEQ_WAIT_FOREVER = 0xFFFFFFFF; // 4294967295

// AQ other constants
const int MSG_NO_DELAY = 0;
const int MSG_NO_EXPIRATION = -1;

// subscription quality of service (Flags - use const int)
const int SUBSCR_QOS_BEST_EFFORT = 0x10;
const int SUBSCR_QOS_DEFAULT = 0;
const int SUBSCR_QOS_DEREG_NFY = 0x02;
const int SUBSCR_QOS_QUERY = 0x08;
const int SUBSCR_QOS_RELIABLE = 0x01;
const int SUBSCR_QOS_ROWIDS = 0x04;

// operation codes (Flags - use const int)
const int OPCODE_ALLOPS = 0;
const int OPCODE_ALLROWS = 0x01;
const int OPCODE_ALTER = 0x10;
const int OPCODE_DELETE = 0x08;
const int OPCODE_DROP = 0x20;
const int OPCODE_INSERT = 0x02;
const int OPCODE_UPDATE = 0x04;

// flags for tpc_begin() (Flags - use const int)
const int TPC_BEGIN_JOIN = 0x00000002;
const int TPC_BEGIN_NEW = 0x00000001;
const int TPC_BEGIN_PROMOTE = 0x00000008;
const int TPC_BEGIN_RESUME = 0x00000004;

// flags for tpc_end() (Flags - use const int)
const int TPC_END_NORMAL = 0;
const int TPC_END_SUSPEND = 0x00100000;

// vector metadata flags (Flags - use const int)
const int VECTOR_META_FLAG_FLEXIBLE_DIM = 0x01;
const int VECTOR_META_FLAG_SPARSE_VECTOR = 0x02;

// -----------------------------------------------
// Internal TNS Constants (from constants.pxi)
// These might be better placed in internal implementation files (e.g., src/thin/protocol)
// -----------------------------------------------

// TNS JSON constants
const int TNS_JSON_MAGIC_BYTE_1 = 0xff;
const int TNS_JSON_MAGIC_BYTE_2 = 0x4a; // 'J'
const int TNS_JSON_MAGIC_BYTE_3 = 0x5a; // 'Z'
const int TNS_JSON_VERSION_MAX_FNAME_255 = 1;
const int TNS_JSON_VERSION_MAX_FNAME_65535 = 3;
const int TNS_JSON_FLAG_HASH_ID_UINT8 = 0x0100;
const int TNS_JSON_FLAG_NUM_FNAMES_UINT16 = 0x0400;
const int TNS_JSON_FLAG_FNAMES_SEG_UINT32 = 0x0800;
const int TNS_JSON_FLAG_TINY_NODES_STAT = 0x2000;
const int TNS_JSON_FLAG_TREE_SEG_UINT32 = 0x1000;
const int TNS_JSON_FLAG_REL_OFFSET_MODE = 0x01;
const int TNS_JSON_FLAG_INLINE_LEAF = 0x02;
const int TNS_JSON_FLAG_LEN_IN_PCODE = 0x04;
const int TNS_JSON_FLAG_NUM_FNAMES_UINT32 = 0x08;
const int TNS_JSON_FLAG_IS_SCALAR = 0x10;
const int TNS_JSON_FLAG_SEC_FNAMES_SEG_UINT16 = 0x0100;

// TNS JSON data types
const int TNS_JSON_TYPE_NULL = 0x30;
const int TNS_JSON_TYPE_TRUE = 0x31;
const int TNS_JSON_TYPE_FALSE = 0x32;
const int TNS_JSON_TYPE_STRING_LENGTH_UINT8 = 0x33;
const int TNS_JSON_TYPE_NUMBER_LENGTH_UINT8 = 0x34;
const int TNS_JSON_TYPE_BINARY_DOUBLE = 0x36;
const int TNS_JSON_TYPE_STRING_LENGTH_UINT16 = 0x37;
const int TNS_JSON_TYPE_STRING_LENGTH_UINT32 = 0x38;
const int TNS_JSON_TYPE_TIMESTAMP = 0x39;
const int TNS_JSON_TYPE_BINARY_LENGTH_UINT16 = 0x3a;
const int TNS_JSON_TYPE_BINARY_LENGTH_UINT32 = 0x3b;
const int TNS_JSON_TYPE_DATE = 0x3c;
const int TNS_JSON_TYPE_INTERVAL_YM = 0x3d;
const int TNS_JSON_TYPE_INTERVAL_DS = 0x3e;
const int TNS_JSON_TYPE_TIMESTAMP_TZ = 0x7c;
const int TNS_JSON_TYPE_TIMESTAMP7 =
    0x7d; // Timestamp with 0 fractional seconds
const int TNS_JSON_TYPE_ID = 0x7e;
const int TNS_JSON_TYPE_BINARY_FLOAT = 0x7f;
const int TNS_JSON_TYPE_OBJECT = 0x84;
const int TNS_JSON_TYPE_ARRAY = 0xc0;
const int TNS_JSON_TYPE_EXTENDED = 0x7b;
const int TNS_JSON_TYPE_VECTOR = 0x01; // Extended type sub-code

// TNS VECTOR constants
const int TNS_VECTOR_MAGIC_BYTE = 0xDB;
const int TNS_VECTOR_VERSION_BASE = 0;
const int TNS_VECTOR_VERSION_WITH_BINARY = 1;
const int TNS_VECTOR_VERSION_WITH_SPARSE = 2;

// TNS VECTOR flags
const int TNS_VECTOR_FLAG_NORM = 0x0002;
const int TNS_VECTOR_FLAG_NORM_RESERVED = 0x0010;
const int TNS_VECTOR_FLAG_SPARSE = 0x0020;

// TNS General constants
const int TNS_MAX_SHORT_LENGTH = 252;
const int TNS_DURATION_MID = 0x80000000;
const int TNS_DURATION_OFFSET = 60;
const int TNS_CHUNK_SIZE = 32767;
const int TNS_HAS_REGION_ID = 0x80;

// TNS Timezone offsets
const int TZ_HOUR_OFFSET = 20;
const int TZ_MINUTE_OFFSET = 60;

// Network name chars - kept as string, might be used for validation
const String VALID_NETWORK_NAME_CHARS =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\"'<>/\,.:;-_\$+*#&!%?@";

// error numbers that result in DatabaseError
// const ERR_TNS_ENTRY_NOT_FOUND = 4000;
// const ERR_NO_CREDENTIALS = 4001;
// const ERR_COLUMN_TRUNCATED = 4002;
// const ERR_ORACLE_NUMBER_NO_REPR = 4003;
// const ERR_INVALID_NUMBER = 4004;
// const ERR_POOL_NO_CONNECTION_AVAILABLE = 4005;
// const ERR_ARRAY_DML_ROW_COUNTS_NOT_ENABLED = 4006;
// const ERR_INCONSISTENT_DATATYPES = 4007;
// const ERR_INVALID_BIND_NAME = 4008;
// const ERR_WRONG_NUMBER_OF_POSITIONAL_BINDS = 4009;
// const ERR_MISSING_BIND_VALUE = 4010;
// const ERR_CONNECTION_CLOSED = 4011;
// const ERR_NUMBER_WITH_INVALID_EXPONENT = 4012;
// const ERR_NUMBER_STRING_OF_ZERO_LENGTH = 4013;
// const ERR_NUMBER_STRING_TOO_LONG = 4014;
// const ERR_NUMBER_WITH_EMPTY_EXPONENT = 4015;
// const ERR_CONTENT_INVALID_AFTER_NUMBER = 4016;
// const ERR_INVALID_CONNECT_DESCRIPTOR = 4017;
// const ERR_CANNOT_PARSE_CONNECT_STRING = 4018;
// const ERR_INVALID_REDIRECT_DATA = 4019;
// const ERR_INVALID_PROTOCOL = 4021;
// const ERR_INVALID_ENUM_VALUE = 4022;
// const ERR_CALL_TIMEOUT_EXCEEDED = 4024;
// const ERR_INVALID_REF_CURSOR = 4025;
// const ERR_MISSING_FILE = 4026;
// const ERR_NO_CONFIG_DIR = 4027;
// const ERR_INVALID_SERVER_TYPE = 4028;
// const ERR_TOO_MANY_BATCH_ERRORS = 4029;
// const ERR_IFILE_CYCLE_DETECTED = 4030;
// const ERR_INVALID_VECTOR = 4031;
// const ERR_INVALID_SSL_VERSION = 4032;
// const ERR_EXCEEDED_IDLE_TIME = 4033;
// const ERR_INVALID_PASSWORD_TYPE = 4034;
