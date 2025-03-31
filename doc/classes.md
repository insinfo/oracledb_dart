Arquivo: src/oracledb/aq.py

BaseQueue

Queue

AsyncQueue

DeqOptions

EnqOptions

MessageProperties

Arquivo: src/oracledb/base_impl.pyx (Implementação base em Cython)

Buffer (cdef class)

GrowableBuffer (cdef class, extends Buffer)

BaseConnImpl (cdef class)

ConnectParamsImpl (cdef class)

ConnectParamsNode (cdef class)

Address (cdef class, extends ConnectParamsNode)

AddressList (cdef class, extends ConnectParamsNode)

Description (cdef class, extends ConnectParamsNode)

DescriptionList (cdef class, extends ConnectParamsNode)

TnsnamesFile (cdef class)

TnsnamesFileReader (cdef class)

DefaultsImpl (cdef class)

BindVar (cdef class)

OracleMetadata (cdef class)

OsonDecoder (cdef class, extends Buffer)

OsonFieldName (cdef class)

OsonFieldNamesSegment (cdef class, extends GrowableBuffer)

OsonTreeSegment (cdef class, extends GrowableBuffer)

OsonEncoder (cdef class, extends GrowableBuffer)

BaseParser (cdef class)

ConnectStringParser (cdef class, extends BaseParser)

TnsnamesFileParser (cdef class, extends BaseParser)

PipelineImpl (cdef class)

PipelineOpImpl (cdef class)

PipelineOpResultImpl (cdef class)

BasePoolImpl (cdef class)

PoolParamsImpl (cdef class, extends ConnectParamsImpl)

BaseQueueImpl (cdef class)

BaseDeqOptionsImpl (cdef class)

BaseEnqOptionsImpl (cdef class)

BaseMsgPropsImpl (cdef class)

BaseSodaDbImpl (cdef class)

BaseSodaCollImpl (cdef class)

BaseSodaDocImpl (cdef class)

BaseSodaDocCursorImpl (cdef class)

BaseSubscrImpl (cdef class)

Message (cdef class - para assinaturas)

MessageQuery (cdef class - para assinaturas)

MessageRow (cdef class - para assinaturas)

MessageTable (cdef class - para assinaturas)

ApiType (cdef class)

DbType (cdef class)

BaseVarImpl (cdef class)

SparseVectorImpl (cdef class)

VectorDecoder (cdef class, extends Buffer)

VectorEncoder (cdef class, extends GrowableBuffer)

BaseCursorImpl (cdef class)

BaseDbObjectImpl (cdef class)

BaseDbObjectAttrImpl (cdef class, extends OracleMetadata)

BaseDbObjectTypeImpl (cdef class)

BaseLobImpl (cdef class)

Arquivo: src/oracledb/connection.py

BaseConnection

Connection

AsyncConnection

Arquivo: src/oracledb/connect_params.py

ConnectParams

Arquivo: src/oracledb/cursor.py

BaseCursor

Cursor

AsyncCursor

Arquivo: src/oracledb/dbobject.py

DbObject

DbObjectAttr

DbObjectType

Arquivo: src/oracledb/defaults.py

Defaults

Arquivo: src/oracledb/driver_mode.py

DriverModeManager

Arquivo: src/oracledb/enums.py

AuthMode

PipelineOpType

PoolGetMode

Purity

VectorFormat

Arquivo: src/oracledb/errors.py

_Error

Arquivo: src/oracledb/exceptions.py

Warning

Error

DatabaseError

DataError

IntegrityError

InterfaceError

InternalError

NotSupportedError

OperationalError

ProgrammingError

Arquivo: src/oracledb/fetch_info.py

FetchInfo

Arquivo: src/oracledb/future.py

Future

Arquivo: src/oracledb/thick_impl.pyx (Implementação Thick em Cython)

StringBuffer (cdef class)

ConnectionParams (cdef class - específica para Thick)

ThickXid (cdef class)

ThickConnImpl (cdef class, extends BaseConnImpl)

ThickCursorImpl (cdef class, extends BaseCursorImpl)

ThickDbObjectImpl (cdef class, extends BaseDbObjectImpl)

ThickDbObjectAttrImpl (cdef class, extends BaseDbObjectAttrImpl)

ThickDbObjectTypeImpl (cdef class, extends BaseDbObjectTypeImpl)

JsonBuffer (cdef class)

ThickLobImpl (cdef class, extends BaseLobImpl)

ThickPoolImpl (cdef class, extends BasePoolImpl)

ThickQueueImpl (cdef class, extends BaseQueueImpl)

ThickDeqOptionsImpl (cdef class, extends BaseDeqOptionsImpl)

ThickEnqOptionsImpl (cdef class, extends BaseEnqOptionsImpl)

ThickMsgPropsImpl (cdef class, extends BaseMsgPropsImpl)

ThickSodaDbImpl (cdef class, extends BaseSodaDbImpl)

ThickSodaCollImpl (cdef class, extends BaseSodaCollImpl)

ThickSodaDocImpl (cdef class, extends BaseSodaDocImpl)

ThickSodaDocCursorImpl (cdef class, extends BaseSodaDocCursorImpl)

ThickSodaOpImpl (cdef class)

ThickSubscrImpl (cdef class, extends BaseSubscrImpl)

ThickVarImpl (cdef class, extends BaseVarImpl)

Arquivo: src/oracledb/thin_impl.pyx (Implementação Thin em Cython)

Capabilities (cdef class)

BaseThinConnImpl (cdef class, extends BaseConnImpl)

ThinConnImpl (cdef class, extends BaseThinConnImpl)

AsyncThinConnImpl (cdef class, extends BaseThinConnImpl)

BaseThinCursorImpl (cdef class, extends BaseCursorImpl)

ThinCursorImpl (cdef class, extends BaseThinCursorImpl)

AsyncThinCursorImpl (cdef class, extends BaseThinCursorImpl)

DbObjectPickleBuffer (cdef class, extends GrowableBuffer)

TDSBuffer (cdef class, extends Buffer)

ThinDbObjectImpl (cdef class, extends BaseDbObjectImpl)

ThinDbObjectAttrImpl (cdef class, extends BaseDbObjectAttrImpl)

ThinDbObjectTypeImpl (cdef class, extends BaseDbObjectTypeImpl)

ThinDbObjectTypeSuperCache (cdef class)

BaseThinDbObjectTypeCache (cdef class)

ThinDbObjectTypeCache (cdef class, extends BaseThinDbObjectTypeCache)

AsyncThinDbObjectTypeCache (cdef class, extends BaseThinDbObjectTypeCache)

BaseThinLobImpl (cdef class, extends BaseLobImpl)

ThinLobImpl (cdef class, extends BaseThinLobImpl)

AsyncThinLobImpl (cdef class, extends BaseThinLobImpl)

AqArrayMessage (cdef class, extends AqBaseMessage)

AqBaseMessage (cdef class, extends Message)

AqDeqMessage (cdef class, extends AqBaseMessage)

AqEnqMessage (cdef class, extends AqBaseMessage)

AuthMessage (cdef class, extends Message)

_OracleErrorInfo (cdef class)

Message (cdef class - base para mensagens Thin)

MessageWithData (cdef class, extends Message)

CommitMessage (cdef class, extends Message)

ConnectMessage (cdef class, extends Message)

DataTypesMessage (cdef class, extends Message)

EndPipelineMessage (cdef class, extends Message)

ExecuteMessage (cdef class, extends MessageWithData)

FastAuthMessage (cdef class, extends Message)

FetchMessage (cdef class, extends MessageWithData)

LobOpMessage (cdef class, extends Message)

LogoffMessage (cdef class, extends Message)

PingMessage (cdef class, extends Message)

ProtocolMessage (cdef class, extends Message)

RollbackMessage (cdef class, extends Message)

SessionReleaseMessage (cdef class, extends Message)

TransactionChangeStateMessage (cdef class, extends Message)

TransactionSwitchMessage (cdef class, extends Message)

Packet (cdef class)

ChunkedBytesBuffer (cdef class)

ReadBuffer (cdef class, extends Buffer)

WriteBuffer (cdef class, extends Buffer)

BaseThinPoolImpl (cdef class, extends BasePoolImpl)

ThinPoolImpl (cdef class, extends BaseThinPoolImpl)

AsyncThinPoolImpl (cdef class, extends BaseThinPoolImpl)

PooledConnRequest (cdef class)

PoolCloser (cdef class)

BaseProtocol (cdef class)

Protocol (cdef class, extends BaseProtocol)

BaseAsyncProtocol (cdef class, extends BaseProtocol)

AsyncProtocol (cdef class, extends BaseAsyncProtocol)

BaseThinQueueImpl (cdef class, extends BaseQueueImpl)

ThinQueueImpl (cdef class, extends BaseThinQueueImpl)

AsyncThinQueueImpl (cdef class, extends BaseThinQueueImpl)

ThinDeqOptionsImpl (cdef class, extends BaseDeqOptionsImpl)

ThinEnqOptionsImpl (cdef class, extends BaseEnqOptionsImpl)

ThinMsgPropsImpl (cdef class, extends BaseMsgPropsImpl)

BindInfo (cdef class)

StatementParser (cdef class, extends BaseParser)

Statement (cdef class)

StatementCache (cdef class)

Transport (cdef class)

OutOfPackets (class, extends Exception)

MarkerDetected (class, extends Exception)

ConnectConstants (cdef class)

ThinVarImpl (cdef class, extends BaseVarImpl)

Arquivo: src/oracledb/interchange/buffer.py

OracleColumnBuffer (extends Buffer from protocol.py)

Arquivo: src/oracledb/interchange/column.py

OracleColumn (extends Column from protocol.py)

Arquivo: src/oracledb/interchange/dataframe.py

OracleDataFrame (extends DataFrame from protocol.py)

Arquivo: src/oracledb/interchange/protocol.py

DlpackDeviceType

DtypeKind

ColumnNullType

Buffer (ABC)

Column (ABC)

DataFrame (ABC)

Arquivo: src/oracledb/lob.py

BaseLOB

LOB

AsyncLOB

Arquivo: src/oracledb/pipeline.py

PipelineOp

PipelineOpResult

Pipeline

Arquivo: src/oracledb/pool.py

BaseConnectionPool

ConnectionPool

AsyncConnectionPool

NamedPools

Arquivo: src/oracledb/pool_params.py

PoolParams (extends ConnectParams)

Arquivo: src/oracledb/soda.py

SodaDatabase

SodaCollection

SodaDocument

SodaDocCursor

SodaOperation

Arquivo: src/oracledb/sparse_vector.py

SparseVector

Arquivo: src/oracledb/subscr.py

Subscription

Message (Pública, diferente das internas)

MessageQuery

MessageRow

MessageTable

Arquivo: src/oracledb/var.py

Var

Arquivo: src/oracledb/__init__.py

JsonId (extends bytes)