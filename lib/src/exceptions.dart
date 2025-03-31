// -----------------------------------------------
// Driver-specific Error Codes (DPY-xxxx)
// -----------------------------------------------

// InterfaceError Range (1000-1999)
const int ERR_MISSING_ERROR = 1000;
const int ERR_NOT_CONNECTED = 1001;
const int ERR_POOL_NOT_OPEN = 1002;
const int ERR_NOT_A_QUERY = 1003;
const int ERR_NO_STATEMENT_EXECUTED = 1004;
const int ERR_POOL_HAS_BUSY_CONNECTIONS = 1005;
const int ERR_CURSOR_NOT_OPEN = 1006;

// ProgrammingError Range (2000-2999)
const int ERR_MESSAGE_HAS_NO_PAYLOAD = 2000;
const int ERR_NO_STATEMENT = 2001;
const int ERR_NO_STATEMENT_PREPARED = 2002;
const int ERR_WRONG_EXECUTE_PARAMETERS_TYPE = 2003;
const int ERR_WRONG_EXECUTEMANY_PARAMETERS_TYPE = 2004;
const int ERR_ARGS_AND_KEYWORD_ARGS = 2005;
const int ERR_MIXED_POSITIONAL_AND_NAMED_BINDS = 2006;
const int ERR_EXPECTING_TYPE = 2007;
const int ERR_WRONG_OBJECT_TYPE = 2008;
const int ERR_WRONG_SCROLL_MODE = 2009;
const int ERR_MIXED_ELEMENT_TYPES = 2010;
const int ERR_WRONG_ARRAY_DEFINITION = 2011;
const int ERR_ARGS_MUST_BE_LIST_OR_TUPLE = 2012;
const int ERR_KEYWORD_ARGS_MUST_BE_DICT = 2013;
const int ERR_DUPLICATED_PARAMETER = 2014;
const int ERR_EXPECTING_VAR = 2015;
const int ERR_INCORRECT_VAR_ARRAYSIZE = 2016;
const int ERR_LIBRARY_ALREADY_INITIALIZED = 2017;
const int ERR_WALLET_FILE_MISSING = 2018;
const int ERR_THIN_CONNECTION_ALREADY_CREATED = 2019;
const int ERR_INVALID_MAKEDSN_ARG = 2020;
const int ERR_INIT_ORACLE_CLIENT_NOT_CALLED = 2021;
const int ERR_INVALID_OCI_ATTR_TYPE = 2022;
const int ERR_INVALID_CONN_CLASS = 2023;
const int ERR_INVALID_CONNECT_PARAMS = 2025;
const int ERR_INVALID_POOL_CLASS = 2026;
const int ERR_INVALID_POOL_PARAMS = 2027;
const int ERR_EXPECTING_LIST_FOR_ARRAY_VAR = 2028;
const int ERR_HTTPS_PROXY_REQUIRES_TCPS = 2029;
const int ERR_INVALID_LOB_OFFSET = 2030;
const int ERR_INVALID_ACCESS_TOKEN_PARAM = 2031;
const int ERR_INVALID_ACCESS_TOKEN_RETURNED = 2032;
const int ERR_EXPIRED_ACCESS_TOKEN = 2033;
const int ERR_ACCESS_TOKEN_REQUIRES_TCPS = 2034;
const int ERR_INVALID_OBJECT_TYPE_NAME = 2035;
const int ERR_OBJECT_IS_NOT_A_COLLECTION = 2036;
const int ERR_MISSING_TYPE_NAME_FOR_OBJECT_VAR = 2037;
const int ERR_INVALID_COLL_INDEX_GET = 2038;
const int ERR_INVALID_COLL_INDEX_SET = 2039;
const int ERR_EXECUTE_MODE_ONLY_FOR_DML = 2040;
const int ERR_MISSING_ENDING_SINGLE_QUOTE = 2041;
const int ERR_MISSING_ENDING_DOUBLE_QUOTE = 2042;
const int ERR_DBOBJECT_ATTR_MAX_SIZE_VIOLATED = 2043;
const int ERR_DBOBJECT_ELEMENT_MAX_SIZE_VIOLATED = 2044;
const int ERR_INVALID_ARRAYSIZE = 2045;
const int ERR_CURSOR_HAS_BEEN_CLOSED = 2046;
const int ERR_INVALID_LOB_AMOUNT = 2047;
const int ERR_DML_RETURNING_DUP_BINDS = 2048;
const int ERR_MISSING_ADDRESS = 2049;
const int ERR_INVALID_TPC_BEGIN_FLAGS = 2050;
const int ERR_INVALID_TPC_END_FLAGS = 2051;
const int ERR_MISMATCHED_TOKEN = 2052;
const int ERR_THICK_MODE_ENABLED = 2053;
const int ERR_NAMED_POOL_MISSING = 2054;
const int ERR_NAMED_POOL_EXISTS = 2055;
const int ERR_PROTOCOL_HANDLER_FAILED = 2056;
const int ERR_PASSWORD_TYPE_HANDLER_FAILED = 2057;
const int ERR_PLAINTEXT_PASSWORD_IN_CONFIG = 2058;
const int ERR_MISSING_CONNECT_DESCRIPTOR = 2059;
const int ERR_ARROW_C_API_ERROR = 2060;
const int ERR_PARAMS_HOOK_HANDLER_FAILED = 2061;
const int ERR_PAYLOAD_CANNOT_BE_ENQUEUED = 2062;
const int ERR_SCROLL_OUT_OF_RESULT_SET = 2063;

// NotSupportedError Range (3000-3999)
const int ERR_TIME_NOT_SUPPORTED = 3000;
const int ERR_FEATURE_NOT_SUPPORTED = 3001;
const int ERR_PYTHON_VALUE_NOT_SUPPORTED = 3002;
const int ERR_PYTHON_TYPE_NOT_SUPPORTED = 3003;
const int ERR_UNSUPPORTED_TYPE_SET = 3004;
const int ERR_ARRAYS_OF_ARRAYS = 3005;
const int ERR_ORACLE_TYPE_NOT_SUPPORTED = 3006;
const int ERR_DB_TYPE_NOT_SUPPORTED = 3007;
const int ERR_UNSUPPORTED_INBAND_NOTIFICATION = 3008;
const int ERR_SELF_BIND_NOT_SUPPORTED = 3009;
const int ERR_SERVER_VERSION_NOT_SUPPORTED = 3010;
const int ERR_NCHAR_CS_NOT_SUPPORTED = 3012;
const int ERR_UNSUPPORTED_PYTHON_TYPE_FOR_DB_TYPE = 3013;
const int ERR_LOB_OF_WRONG_TYPE = 3014;
const int ERR_UNSUPPORTED_VERIFIER_TYPE = 3015;
const int ERR_NO_CRYPTOGRAPHY_PACKAGE = 3016;
const int ERR_ORACLE_TYPE_NAME_NOT_SUPPORTED = 3017;
const int ERR_TDS_TYPE_NOT_SUPPORTED = 3018;
const int ERR_OSON_NODE_TYPE_NOT_SUPPORTED = 3019;
const int ERR_OSON_FIELD_NAME_LIMITATION = 3020;
const int ERR_OSON_VERSION_NOT_SUPPORTED = 3021;
const int ERR_NAMED_TIMEZONE_NOT_SUPPORTED = 3022;
const int ERR_VECTOR_VERSION_NOT_SUPPORTED = 3023;
const int ERR_VECTOR_FORMAT_NOT_SUPPORTED = 3024;
const int ERR_OPERATION_NOT_SUPPORTED_ON_BFILE = 3025;
const int ERR_OPERATION_ONLY_SUPPORTED_ON_BFILE = 3026;
const int ERR_CURSOR_DIFF_CONNECTION = 3027;
const int ERR_UNSUPPORTED_PIPELINE_OPERATION = 3028;
const int ERR_INVALID_NETWORK_NAME = 3029;
const int ERR_ARROW_UNSUPPORTED_DATA_TYPE = 3030;

// DatabaseError Range (4000-4999)
const int ERR_TNS_ENTRY_NOT_FOUND = 4000;
const int ERR_NO_CREDENTIALS = 4001;
const int ERR_COLUMN_TRUNCATED = 4002;
const int ERR_ORACLE_NUMBER_NO_REPR = 4003;
const int ERR_INVALID_NUMBER = 4004;
const int ERR_POOL_NO_CONNECTION_AVAILABLE = 4005;
const int ERR_ARRAY_DML_ROW_COUNTS_NOT_ENABLED = 4006;
const int ERR_INCONSISTENT_DATATYPES = 4007;
const int ERR_INVALID_BIND_NAME = 4008;
const int ERR_WRONG_NUMBER_OF_POSITIONAL_BINDS = 4009;
const int ERR_MISSING_BIND_VALUE = 4010;
const int ERR_CONNECTION_CLOSED = 4011;
const int ERR_NUMBER_WITH_INVALID_EXPONENT = 4012;
const int ERR_NUMBER_STRING_OF_ZERO_LENGTH = 4013;
const int ERR_NUMBER_STRING_TOO_LONG = 4014;
const int ERR_NUMBER_WITH_EMPTY_EXPONENT = 4015;
const int ERR_CONTENT_INVALID_AFTER_NUMBER = 4016;
const int ERR_INVALID_CONNECT_DESCRIPTOR = 4017;
const int ERR_CANNOT_PARSE_CONNECT_STRING = 4018;
const int ERR_INVALID_REDIRECT_DATA = 4019;
const int ERR_INVALID_PROTOCOL = 4021;
const int ERR_INVALID_ENUM_VALUE = 4022;
const int ERR_CALL_TIMEOUT_EXCEEDED = 4024;
const int ERR_INVALID_REF_CURSOR = 4025;
const int ERR_MISSING_FILE = 4026;
const int ERR_NO_CONFIG_DIR = 4027;
const int ERR_INVALID_SERVER_TYPE = 4028;
const int ERR_TOO_MANY_BATCH_ERRORS = 4029;
const int ERR_IFILE_CYCLE_DETECTED = 4030;
const int ERR_INVALID_VECTOR = 4031;
const int ERR_INVALID_SSL_VERSION = 4032;
const int ERR_EXCEEDED_IDLE_TIME = 4033;
const int ERR_INVALID_PASSWORD_TYPE = 4034;

// InternalError Range (5000-5999)
const int ERR_MESSAGE_TYPE_UNKNOWN = 5000;
const int ERR_BUFFER_LENGTH_INSUFFICIENT = 5001;
const int ERR_INTEGER_TOO_LARGE = 5002;
const int ERR_UNEXPECTED_NEGATIVE_INTEGER = 5003;
const int ERR_UNEXPECTED_DATA = 5004;
const int ERR_UNEXPECTED_REFUSE = 5005;
const int ERR_UNEXPECTED_END_OF_DATA = 5006;
const int ERR_UNEXPECTED_XML_TYPE = 5007;
const int ERR_UNKNOWN_SERVER_PIGGYBACK = 5009;
const int ERR_UNKNOWN_TRANSACTION_STATE = 5010;
const int ERR_UNEXPECTED_PIPELINE_FAILURE = 5011;
const int ERR_NOT_IMPLEMENTED = 5012;

// OperationalError Range (6000-6999)
const int ERR_LISTENER_REFUSED_CONNECTION = 6000;
const int ERR_INVALID_SERVICE_NAME = 6001;
const int ERR_INVALID_SERVER_CERT_DN = 6002;
const int ERR_INVALID_SID = 6003;
const int ERR_PROXY_FAILURE = 6004;
const int ERR_CONNECTION_FAILED = 6005;
const int ERR_INVALID_SERVER_NAME = 6006;

// Warning Range (7000-7999)
const int WRN_COMPILATION_ERROR = 7000;


/// Base class for all Oracle DB related exceptions and warnings in Dart.
class OracleException implements Exception {
  /// The error message.
  final String message;

  /// The original Oracle Database error code (ORA-xxxxx), if applicable.
  final int? code;

  /// The internal driver error code (DPY-xxxx), if applicable.
  final String? fullCode;

  /// Offset within the SQL statement where the error occurred, if applicable.
  final int? offset;

  /// Indicates if the error might be recoverable (e.g., temporary network issue).
  final bool isRecoverable;

  /// Indicates if the database session is considered unusable after this error.
  final bool isSessionDead;

  /// Additional context information about the error, if available.
  final String? context;

  /// The original exception that caused this one, if any.
  final Object? cause;

  OracleException(
    this.message, {
    this.code,
    this.fullCode,
    this.offset,
    this.isRecoverable = false,
    this.isSessionDead = false,
    this.context,
    this.cause,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    if (fullCode != null) {
      buffer.write('$fullCode: ');
    } else if (code != null) {
      buffer.write('ORA-${code!.toString().padLeft(5, '0')}: ');
    }
    buffer.write(message);
    if (context != null) {
      buffer.write('\nContext: $context');
    }
    if (cause != null) {
      buffer.write('\nCause: $cause');
    }
    // TODO: Implement help URL logic here if desired, using _troubleshootingAvailable
    // if (_troubleshootingAvailable.contains(fullCode)) { ... }
    return buffer.toString();
  }
}

/// Represents database warnings. Base class for specific warning types if needed.
class OracleWarning extends OracleException {
  OracleWarning(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          isRecoverable: true, // Warnings are generally recoverable
          isSessionDead: false,
          context: context,
          cause: cause,
        );
}

/// Base class for database errors. Corresponds to Python's DatabaseError.
class OracleDatabaseError extends OracleException {
  OracleDatabaseError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    bool isRecoverable = false,
    bool isSessionDead = false,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          isRecoverable: isRecoverable,
          isSessionDead: isSessionDead,
          context: context,
          cause: cause,
        );
}

/// Errors related to data processing. Corresponds to Python's DataError.
class OracleDataError extends OracleDatabaseError {
  OracleDataError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          context: context,
          cause: cause,
        );
}

/// Errors related to database integrity (e.g., constraint violations).
/// Corresponds to Python's IntegrityError.
class OracleIntegrityError extends OracleDatabaseError {
  OracleIntegrityError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          context: context,
          cause: cause,
        );
}

/// Errors related to the driver's interface (e.g., closed connection/cursor).
/// Corresponds to Python's InterfaceError.
class OracleInterfaceError extends OracleException {
  OracleInterfaceError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          context: context,
          cause: cause,
        );
}

/// Internal driver errors. Corresponds to Python's InternalError.
class OracleInternalError extends OracleDatabaseError {
  OracleInternalError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          context: context,
          cause: cause,
        );
}

/// Errors indicating an unsupported feature or operation.
/// Corresponds to Python's NotSupportedError.
class OracleNotSupportedError extends OracleDatabaseError {
  OracleNotSupportedError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          context: context,
          cause: cause,
        );
}

/// Errors related to database operations (e.g., connection loss).
/// Corresponds to Python's OperationalError.
class OracleOperationalError extends OracleDatabaseError {
  OracleOperationalError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    bool isRecoverable = false,
    bool isSessionDead = false,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          isRecoverable: isRecoverable,
          isSessionDead: isSessionDead,
          context: context,
          cause: cause,
        );
}

/// Errors related to programming mistakes (e.g., wrong parameters).
/// Corresponds to Python's ProgrammingError.
class OracleProgrammingError extends OracleDatabaseError {
  OracleProgrammingError(
    String message, {
    int? code,
    String? fullCode,
    int? offset,
    String? context,
    Object? cause,
  }) : super(
          message,
          code: code,
          fullCode: fullCode,
          offset: offset,
          context: context,
          cause: cause,
        );
}

// -----------------------------------------------
// Error Handling Internals (Maps, Helper)
// -----------------------------------------------

const String _errPrefix = "DPY";

// Map internal DPY error numbers to their corresponding exception types
final Map<int, Type> _exceptionTypeMap = {
  1: OracleInterfaceError,
  2: OracleProgrammingError,
  3: OracleNotSupportedError,
  4: OracleDatabaseError,
  5: OracleInternalError,
  6: OracleOperationalError,
  7: OracleWarning,
};

// Map internal DPY error numbers to their message formats
// (Placeholders like {name} would be replaced during error creation)
final Map<int, String> _errorMessageFormats = {
  1000: "missing error {error_num}", // ERR_MISSING_ERROR
  1001: "not connected to database", // ERR_NOT_CONNECTED
  // ... (rest of the messages copied from the previous response) ...
   ERR_ACCESS_TOKEN_REQUIRES_TCPS: (
        "access_token requires use of the tcps protocol"
    ),
    ERR_ARGS_MUST_BE_LIST_OR_TUPLE: "arguments must be a list or tuple",
    ERR_ARGS_AND_KEYWORD_ARGS: (
        "expecting positional arguments or keyword arguments, not both"
    ),
    ERR_ARRAY_DML_ROW_COUNTS_NOT_ENABLED: (
        "array DML row counts mode is not enabled"
    ),
    ERR_ARRAYS_OF_ARRAYS: "arrays of arrays are not supported",
    ERR_BUFFER_LENGTH_INSUFFICIENT: (
        "internal error: buffer of length {actual_buffer_len} "
        "insufficient to hold {required_buffer_len} bytes"
    ),
    ERR_CALL_TIMEOUT_EXCEEDED: "call timeout of {timeout} ms exceeded",
    ERR_CANNOT_PARSE_CONNECT_STRING: 'cannot parse connect string "{data}"',
    ERR_COLUMN_TRUNCATED: (
        "column truncated to {col_value_len} {unit}. "
        "Untruncated was {actual_len}"
    ),
    ERR_CONNECTION_FAILED: (
        "cannot connect to database (CONNECTION_ID={connection_id})."
    ),
    ERR_CONTENT_INVALID_AFTER_NUMBER: "invalid number (content after number)",
    ERR_CURSOR_DIFF_CONNECTION: (
        "binding a cursor from a different connection is not supported"
    ),
    ERR_CURSOR_NOT_OPEN: "cursor is not open",
    ERR_CURSOR_HAS_BEEN_CLOSED: "cursor has been closed by the database",
    ERR_DBOBJECT_ATTR_MAX_SIZE_VIOLATED: (
        "attribute {attr_name} of type {type_name} exceeds its maximum size "
        "(actual: {actual_size}, maximum: {max_size})"
    ),
    ERR_DBOBJECT_ELEMENT_MAX_SIZE_VIOLATED: (
        "element {index} of type {type_name} exceeds its maximum size "
        "(actual: {actual_size}, maximum: {max_size})"
    ),
    ERR_DB_TYPE_NOT_SUPPORTED: 'database type "{name}" is not supported',
    ERR_DML_RETURNING_DUP_BINDS: (
        'the bind variable placeholder ":{name}" cannot be used both before '
        "and after the RETURNING clause in a DML RETURNING statement"
    ),
    ERR_DUPLICATED_PARAMETER: (
        '"{deprecated_name}" and "{new_name}" cannot be specified together'
    ),
    ERR_EXCEEDED_IDLE_TIME: (
        "the database closed the connection because the connection's idle "
        "time has been exceeded"
    ),
    ERR_EXECUTE_MODE_ONLY_FOR_DML: (
        'parameters "batcherrors" and "arraydmlrowcounts" may only be '
        "true when used with insert, update, delete and merge statements"
    ),
    ERR_EXPECTING_LIST_FOR_ARRAY_VAR: (
        "expecting list when setting array variables"
    ),
    ERR_EXPECTING_TYPE: "expected a type",
    ERR_EXPECTING_VAR: (
        "type handler should return None or the value returned by a call "
        "to cursor.var()"
    ),
    ERR_EXPIRED_ACCESS_TOKEN: "access token has expired",
    ERR_FEATURE_NOT_SUPPORTED: (
        "{feature} is only supported in python-oracledb {driver_type} mode"
    ),
    ERR_HTTPS_PROXY_REQUIRES_TCPS: (
        "https_proxy requires use of the tcps protocol"
    ),
    ERR_IFILE_CYCLE_DETECTED: (
        "file '{including_file_name}' includes file '{included_file_name}', "
        "which forms a cycle"
    ),
    ERR_INCONSISTENT_DATATYPES: (
        "cannot convert from data type {input_type} to {output_type}"
    ),
    ERR_INCORRECT_VAR_ARRAYSIZE: (
        "variable array size of {var_arraysize} is "
        "too small (should be at least {required_arraysize})"
    ),
    ERR_INIT_ORACLE_CLIENT_NOT_CALLED: (
        "init_oracle_client() must be called first"
    ),
    ERR_INTEGER_TOO_LARGE: (
        "internal error: read integer of length {length} when expecting "
        "integer of no more than length {max_length}"
    ),
    ERR_INVALID_ACCESS_TOKEN_PARAM: (
        "invalid access token: value must be a string (for OAuth), a "
        "2-tuple containing the token and private key strings (for IAM), "
        "or a callable that returns a string or 2-tuple"
    ),
    ERR_INVALID_ACCESS_TOKEN_RETURNED: (
        "invalid access token returned from callable: value must be a "
        "string (for OAuth) or a 2-tuple containing the token and private "
        "key strings (for IAM)"
    ),
    ERR_INVALID_ARRAYSIZE: "arraysize must be an integer greater than zero",
    ERR_INVALID_BIND_NAME: (
        'no bind placeholder named ":{name}" was found in the SQL text'
    ),
    ERR_INVALID_CONN_CLASS: "invalid connection class",
    ERR_INVALID_CONNECT_DESCRIPTOR: 'invalid connect descriptor "{data}"',
    ERR_INVALID_CONNECT_PARAMS: "invalid connection params",
    ERR_INVALID_COLL_INDEX_GET: "element at index {index} does not exist",
    ERR_INVALID_COLL_INDEX_SET: (
        "given index {index} must be in the range of {min_index} to "
        "{max_index}"
    ),
    ERR_INVALID_ENUM_VALUE: "invalid value for enumeration {name}: {value}",
    ERR_INVALID_LOB_AMOUNT: "LOB amount must be greater than zero",
    ERR_INVALID_LOB_OFFSET: "LOB offset must be greater than zero",
    ERR_INVALID_MAKEDSN_ARG: '"{name}" argument contains invalid values',
    ERR_INVALID_NUMBER: "invalid number",
    ERR_INVALID_OBJECT_TYPE_NAME: 'invalid object type name: "{name}"',
    ERR_INVALID_OCI_ATTR_TYPE: "invalid OCI attribute type {attr_type}",
    ERR_INVALID_PASSWORD_TYPE: 'invalid password type "{password_type}"',
    ERR_INVALID_POOL_CLASS: "invalid connection pool class",
    ERR_INVALID_POOL_PARAMS: "invalid pool params",
    ERR_INVALID_PROTOCOL: 'invalid protocol "{protocol}"',
    ERR_INVALID_REDIRECT_DATA: "invalid redirect data {data}",
    ERR_INVALID_REF_CURSOR: "invalid REF CURSOR: never opened in PL/SQL",
    ERR_INVALID_SERVER_CERT_DN: (
        "The distinguished name (DN) on the server certificate does not "
        "match the expected value: {expected_dn}"
    ),
    ERR_INVALID_SERVER_NAME: (
        "The name on the server certificate does not match the expected "
        'value: "{expected_name}"'
    ),
    ERR_INVALID_SERVER_TYPE: "invalid server_type: {server_type}",
    ERR_INVALID_SERVICE_NAME: (
        'Service "{service_name}" is not registered with the listener at '
        'host "{host}" port {port}. (Similar to ORA-12514)'
    ),
    ERR_INVALID_SID: (
        'SID "{sid}" is not registered with the listener at host "{host}" '
        "port {port}. (Similar to ORA-12505)"
    ),
    ERR_INVALID_SSL_VERSION: 'invalid value for ssl_version: "{ssl_version}"',
    ERR_INVALID_TPC_BEGIN_FLAGS: "invalid flags for tpc_begin()",
    ERR_INVALID_TPC_END_FLAGS: "invalid flags for tpc_end()",
    ERR_INVALID_VECTOR: "vector cannot contain zero dimensions",
    ERR_KEYWORD_ARGS_MUST_BE_DICT: (
        '"keyword_parameters" argument must be a dict'
    ),
    ERR_LIBRARY_ALREADY_INITIALIZED: (
        "init_oracle_client() was already called with different arguments"
    ),
    ERR_LISTENER_REFUSED_CONNECTION: (
        "Listener refused connection. (Similar to ORA-{error_code})"
    ),
    ERR_LOB_OF_WRONG_TYPE: (
        "LOB is of type {actual_type_name} but must be of type "
        "{expected_type_name}"
    ),
    ERR_MESSAGE_HAS_NO_PAYLOAD: "message has no payload",
    ERR_MESSAGE_TYPE_UNKNOWN: (
        "internal error: unknown protocol message type {message_type} "
        "at position {position}"
    ),
    ERR_MISMATCHED_TOKEN: (
        "internal error: pipeline token number {token_num} does not match "
        "expected token number {expected_token_num}"
    ),
    ERR_MISSING_ADDRESS: (
        "no addresses are defined in connect descriptor: {connect_string}"
    ),
    ERR_MISSING_BIND_VALUE: (
        'a bind variable replacement value for placeholder ":{name}" was '
        "not provided"
    ),
    ERR_MISSING_CONNECT_DESCRIPTOR: (
        '"connect_descriptor" key missing from configuration'
    ),
    ERR_MISSING_FILE: "file '{file_name}' is missing or unreadable",
    ERR_MISSING_ENDING_DOUBLE_QUOTE: 'missing ending quote (")',
    ERR_MISSING_ENDING_SINGLE_QUOTE: "missing ending quote (')",
    ERR_MISSING_TYPE_NAME_FOR_OBJECT_VAR: (
        "no object type specified for object variable"
    ),
    ERR_MIXED_ELEMENT_TYPES: (
        "element {element} is not the same data type as previous elements"
    ),
    ERR_MIXED_POSITIONAL_AND_NAMED_BINDS: (
        "positional and named binds cannot be intermixed"
    ),
    ERR_NAMED_POOL_EXISTS: (
        'connection pool with alias "{alias}" already exists'
    ),
    ERR_NAMED_POOL_MISSING: (
        'connection pool with alias "{alias}" does not exist'
    ),
    ERR_NAMED_TIMEZONE_NOT_SUPPORTED: (
        "named time zones are not supported in thin mode"
    ),
    ERR_NCHAR_CS_NOT_SUPPORTED: (
        "national character set id {charset_id} is not supported by "
        "python-oracledb in thin mode"
    ),
    ERR_NO_CONFIG_DIR: "no configuration directory specified",
    ERR_NO_CREDENTIALS: "no credentials specified",
    ERR_NO_CRYPTOGRAPHY_PACKAGE: (
        "python-oracledb thin mode cannot be used because the "
        "cryptography package cannot be imported"
    ),
    ERR_NO_STATEMENT: "no statement specified and no prior statement prepared",
    ERR_NO_STATEMENT_EXECUTED: "no statement executed",
    ERR_NO_STATEMENT_PREPARED: "statement must be prepared first",
    ERR_NOT_A_QUERY: "the executed statement does not return rows",
    //ERR_NOT_CONNECTED: "not connected to database",
    ERR_NOT_IMPLEMENTED: "not implemented",
    ERR_NUMBER_STRING_OF_ZERO_LENGTH: "invalid number: zero length string",
    ERR_NUMBER_STRING_TOO_LONG: "invalid number: string too long",
    ERR_NUMBER_WITH_EMPTY_EXPONENT: "invalid number: empty exponent",
    ERR_NUMBER_WITH_INVALID_EXPONENT: "invalid number: invalid exponent",
    ERR_OBJECT_IS_NOT_A_COLLECTION: "object {name} is not a collection",
    ERR_OPERATION_NOT_SUPPORTED_ON_BFILE: (
        "operation is not supported on BFILE LOBs"
    ),
    ERR_OPERATION_ONLY_SUPPORTED_ON_BFILE: (
        "operation is only supported on BFILE LOBs"
    ),
    ERR_ORACLE_NUMBER_NO_REPR: (
        "value cannot be represented as an Oracle number"
    ),
    ERR_ORACLE_TYPE_NAME_NOT_SUPPORTED: (
        'Oracle data type name "{name}" is not supported'
    ),
    ERR_ORACLE_TYPE_NOT_SUPPORTED: "Oracle data type {num} is not supported",
    ERR_OSON_FIELD_NAME_LIMITATION: (
        "OSON field names may not exceed {max_fname_size} UTF-8 encoded bytes"
    ),
    ERR_OSON_NODE_TYPE_NOT_SUPPORTED: (
        "OSON node type 0x{node_type:x} is not supported"
    ),
    ERR_OSON_VERSION_NOT_SUPPORTED: "OSON version {version} is not supported",
    ERR_PARAMS_HOOK_HANDLER_FAILED: (
        "registered handler for params hook failed"
    ),
    ERR_PASSWORD_TYPE_HANDLER_FAILED: (
        'registered handler for password type "{password_type}" failed'
    ),
    ERR_PAYLOAD_CANNOT_BE_ENQUEUED: (
        "payload cannot be enqueued since it does not match the payload type "
        "supported by the queue"
    ),
    ERR_PLAINTEXT_PASSWORD_IN_CONFIG: (
        "password in configuration must specify a type"
    ),
    ERR_POOL_HAS_BUSY_CONNECTIONS: (
        "connection pool cannot be closed because connections are busy"
    ),
    ERR_POOL_NO_CONNECTION_AVAILABLE: (
        "timed out waiting for the connection pool to return a connection"
    ),
    ERR_POOL_NOT_OPEN: "connection pool is not open",
    ERR_PROTOCOL_HANDLER_FAILED: (
        'registered handler for protocol "{protocol}" failed for arg "{arg}"'
    ),
    ERR_PROXY_FAILURE: "network proxy failed: response was {response}",
    ERR_PYTHON_TYPE_NOT_SUPPORTED: "Python type {typ} is not supported",
    ERR_PYTHON_VALUE_NOT_SUPPORTED: (
        'Python value of type "{type_name}" is not supported'
    ),
    ERR_SCROLL_OUT_OF_RESULT_SET: (
        "scroll operation would go out of the result set"
    ),
    ERR_SELF_BIND_NOT_SUPPORTED: "binding to self is not supported",
    ERR_CONNECTION_CLOSED: "the database or network closed the connection",
    ERR_SERVER_VERSION_NOT_SUPPORTED: (
        "connections to this database server version are not supported "
        "by python-oracledb in thin mode"
    ),
    ERR_TDS_TYPE_NOT_SUPPORTED: "Oracle TDS data type {num} is not supported",
    ERR_THICK_MODE_ENABLED: (
        "python-oracledb thin mode cannot be used because thick mode has "
        "already been enabled"
    ),
    ERR_THIN_CONNECTION_ALREADY_CREATED: (
        "python-oracledb thick mode cannot be used because thin mode has "
        "already been enabled or a thin mode connection has already been "
        "created"
    ),
    ERR_TIME_NOT_SUPPORTED: (
        "Oracle Database does not support time only variables"
    ),
    ERR_TNS_ENTRY_NOT_FOUND: 'unable to find "{name}" in {file_name}',
    ERR_TOO_MANY_BATCH_ERRORS: (
        "the number of batch errors from executemany() exceeds 65535"
    ),
    ERR_UNEXPECTED_PIPELINE_FAILURE: "unexpected pipeline failure",
    ERR_UNEXPECTED_DATA: "unexpected data received: {data}",
    ERR_UNEXPECTED_END_OF_DATA: (
        "unexpected end of data: want {num_bytes_wanted} bytes but "
        "only {num_bytes_available} bytes are available"
    ),
    ERR_UNEXPECTED_NEGATIVE_INTEGER: (
        "internal error: read a negative integer when expecting a "
        "positive integer"
    ),
    ERR_UNEXPECTED_REFUSE: (
        "the listener refused the connection but an unexpected error "
        "format was returned"
    ),
    ERR_UNEXPECTED_XML_TYPE: "unexpected XMLType with flag {flag}",
    ERR_UNKNOWN_SERVER_PIGGYBACK: (
        "internal error: unknown server side piggyback opcode {opcode}"
    ),
    ERR_UNKNOWN_TRANSACTION_STATE: (
        "internal error: unknown transaction state {state}"
    ),
    ERR_UNSUPPORTED_PIPELINE_OPERATION: (
        "unsupported pipeline operation type: {op_type}"
    ),
    ERR_UNSUPPORTED_INBAND_NOTIFICATION: (
        "unsupported in-band notification with error number {err_num}"
    ),
    ERR_UNSUPPORTED_PYTHON_TYPE_FOR_DB_TYPE: (
        "unsupported Python type {py_type_name} for database type "
        "{db_type_name}"
    ),
    ERR_UNSUPPORTED_TYPE_SET: "type {db_type_name} does not support being set",
    ERR_UNSUPPORTED_VERIFIER_TYPE: (
        "password verifier type 0x{verifier_type:x} is not supported by "
        "python-oracledb in thin mode"
    ),
    ERR_VECTOR_FORMAT_NOT_SUPPORTED: (
        "VECTOR type {vector_format} is not supported"
    ),
    ERR_VECTOR_VERSION_NOT_SUPPORTED: (
        "VECTOR version {version} is not supported"
    ),
    ERR_WALLET_FILE_MISSING: "wallet file {name} was not found",
    ERR_WRONG_ARRAY_DEFINITION: (
        "expecting a list of two elements [type, numelems]"
    ),
    ERR_WRONG_EXECUTE_PARAMETERS_TYPE: (
        "expecting a dictionary, list or tuple, or keyword args"
    ),
    ERR_WRONG_EXECUTEMANY_PARAMETERS_TYPE: (
        '"parameters" argument should be a list of sequences or '
        "dictionaries, or an integer specifying the number of "
        "times to execute the statement"
    ),
    ERR_WRONG_NUMBER_OF_POSITIONAL_BINDS: (
        "{expected_num} positional bind values are required but "
        "{actual_num} were provided"
    ),
    ERR_WRONG_OBJECT_TYPE: (
        'found object of type "{actual_schema}.{actual_name}" when '
        'expecting object of type "{expected_schema}.{expected_name}"'
    ),
    ERR_WRONG_SCROLL_MODE: (
        "scroll mode must be relative, absolute, first or last"
    ),
    WRN_COMPILATION_ERROR: "creation succeeded with compilation errors",
    ERR_INVALID_NETWORK_NAME: (
        '"{name}" includes characters that are not allowed'
    ),
    ERR_ARROW_UNSUPPORTED_DATA_TYPE: (
        "conversion from Oracle Database type {db_type_name} to Apache "
        "Arrow format is not supported"
    ),
    ERR_ARROW_C_API_ERROR: (
        "Arrow C Data Interface operation failed with error code {code}"
    ),
  // Add the rest of the DPY messages here...
};

// Map Oracle ORA codes to Dart exception types (if different from default DatabaseError)
final Map<int, Type> _oraCodeExceptionTypeMap = {
  // Integrity Errors
  1: OracleIntegrityError,
  1400: OracleIntegrityError,
  1438: OracleIntegrityError,
  2290: OracleIntegrityError,
  2291: OracleIntegrityError,
  2292: OracleIntegrityError,
  21525: OracleIntegrityError,
  40479: OracleIntegrityError,

  // Interface Errors
  24422: OracleInterfaceError,

  // Operational Errors
  22: OracleOperationalError,
  378: OracleOperationalError,
  600: OracleOperationalError,
  602: OracleOperationalError,
  603: OracleOperationalError,
  604: OracleOperationalError,
  609: OracleOperationalError,
  1012: OracleOperationalError,
  1013: OracleOperationalError,
  1033: OracleOperationalError,
  1034: OracleOperationalError,
  1041: OracleOperationalError,
  1043: OracleOperationalError,
  1089: OracleOperationalError,
  1090: OracleOperationalError,
  1092: OracleOperationalError,
  3111: OracleOperationalError,
  3113: OracleOperationalError,
  3114: OracleOperationalError,
  3122: OracleOperationalError,
  3135: OracleOperationalError,
  12153: OracleOperationalError,
  12203: OracleOperationalError,
  12500: OracleOperationalError,
  12571: OracleOperationalError,
  27146: OracleOperationalError,
  28511: OracleOperationalError,

  // Warnings
  24344: OracleWarning,
};

// Map DPY codes to session dead status
final Set<int> _sessionDeadDpyCodes = {
  ERR_CONNECTION_CLOSED,
};

// Map ORA codes to session dead status
final Set<int> _sessionDeadOraCodes = {
  22, 28, 31, 45, 378, 600, 602, 603, 609, 1012, 1041, 1043, 1089, 1092,
  2396, 3113, 3114, 3122, 3135, 12153, 12537, 12547, 12570, 12583,
  27146, 28511, 56600,
};

/*
// Map full codes (DPY-xxxx) to troubleshooting availability (Commented out as unused currently)
final Set<String> _troubleshootingAvailable = {
  "DPI-1047", // Oracle Client library cannot be loaded
  "DPI-1072", // Oracle Client library version is unsupported
  "DPY-3010", // connections to Oracle Database version not supported
  "DPY-3015", // password verifier type is not supported
  "DPY-4011", // the database or network closed the connection
};
*/

// Internal helper to create exceptions (example, likely part of error handling logic)
OracleException createOracleException(
    {required String message,
    int? oraCode,
    int? dpyCode,
    int? offset,
    bool isRecoverable = false,
    String? context,
    Object? cause}) {

  String? fullCode;
  Type exceptionType = OracleDatabaseError; // Default
  bool isSessionDead = false;

  if (dpyCode != null) {
    fullCode = '$_errPrefix-${dpyCode.toString().padLeft(4, '0')}';
    exceptionType = _exceptionTypeMap[dpyCode ~/ 1000] ?? OracleDatabaseError;
    isSessionDead = _sessionDeadDpyCodes.contains(dpyCode);
    final format = _errorMessageFormats[dpyCode];
    if (format != null) {
      // Basic placeholder replacement (real implementation needs more robust formatting)
      var formattedMessage = format.replaceAll('{error_num}', dpyCode.toString());
      // Add more replacements as needed based on args in the Python version
      message = '$formattedMessage\n$message';
    } else {
       message = '$_errorMessageFormats[ERR_MISSING_ERROR]'.replaceAll('{error_num}', dpyCode.toString()) + '\n$message'; // Use missing error format
    }
  } else if (oraCode != null) {
    exceptionType = _oraCodeExceptionTypeMap[oraCode] ?? OracleDatabaseError;
    isSessionDead = _sessionDeadOraCodes.contains(oraCode);
  }

  // Determine the final class to instantiate
  OracleException instance;
  if (exceptionType == OracleIntegrityError) {
    instance = OracleIntegrityError(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else if (exceptionType == OracleInterfaceError) {
     instance = OracleInterfaceError(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else if (exceptionType == OracleOperationalError) {
     instance = OracleOperationalError(message, code: oraCode, fullCode: fullCode, offset: offset, isRecoverable: isRecoverable, isSessionDead: isSessionDead, context: context, cause: cause);
  } else if (exceptionType == OracleInternalError) {
     instance = OracleInternalError(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else if (exceptionType == OracleNotSupportedError) {
     instance = OracleNotSupportedError(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else if (exceptionType == OracleProgrammingError) {
     instance = OracleProgrammingError(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else if (exceptionType == OracleDataError) {
     instance = OracleDataError(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else if (exceptionType == OracleWarning) {
    instance = OracleWarning(message, code: oraCode, fullCode: fullCode, offset: offset, context: context, cause: cause);
  } else { // Default to OracleDatabaseError
    instance = OracleDatabaseError(message, code: oraCode, fullCode: fullCode, offset: offset, isRecoverable: isRecoverable, isSessionDead: isSessionDead, context: context, cause: cause);
  }

  return instance;
}