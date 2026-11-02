/// Pure Dart driver for Oracle Database (thin mode).
library;

export 'src/connect_params.dart'
    show AccessTokenCallback, AuthMode, ConnectParams, Purity;
export 'src/connection.dart' show OracleConnection;
export 'src/cursor.dart' show OracleCursor, OracleResult, OracleVar;
export 'src/exceptions.dart'
    show
        OracleException,
        OracleWarning,
        OracleDatabaseError,
        OracleDataError,
        OracleIntegrityError,
        OracleInterfaceError,
        OracleInternalError,
        OracleNotSupportedError,
        OracleOperationalError,
        OracleProgrammingError;
export 'src/hooks.dart'
    show
        ParamsHook,
        PasswordTypeHook,
        ProtocolHook,
        applyConfig,
        registerParamsHook,
        registerPasswordType,
        registerProtocol,
        resolvePassword,
        unregisterParamsHook;
export 'src/lob.dart' show OracleLob;
export 'src/placeholders.dart' show PlaceholderIdentifier;
export 'src/pool.dart' show OracleConnectionPool, PoolGetMode, SessionCallback;
export 'src/thin/codecs.dart' show IntervalYM;
export 'src/thin/messages/base.dart' show BatchError;
export 'src/thin/types.dart' show ColumnMetadata, DbType;
export 'src/thin/vector.dart' show BinaryVector, SparseVector;
