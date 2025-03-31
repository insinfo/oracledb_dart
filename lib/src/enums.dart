// ignore_for_file: camel_case_types

/// AQ Delivery Modes
enum AqDeliveryMode {
  persistent(1),
  buffered(2),
  persistentOrBuffered(3);

  final int value;
  const AqDeliveryMode(this.value);
}

/// AQ Dequeue Modes
enum AqDequeueMode {
  browse(1),
  locked(2),
  remove(3),
  removeNoData(4);

  final int value;
  const AqDequeueMode(this.value);
}

/// AQ Dequeue Navigation Modes
enum AqNavigationMode {
  firstMsg(1),
  nextTransaction(2),
  nextMsg(3);

  final int value;
  const AqNavigationMode(this.value);
}

/// AQ Visibility Modes (combines Dequeue and Enqueue)
enum AqVisibilityMode {
  immediate(1),
  onCommit(2);

  final int value;
  const AqVisibilityMode(this.value);
}

/// AQ Message States
enum AqMessageState {
  ready(0),
  waiting(1),
  processed(2),
  expired(3);

  final int value;
  const AqMessageState(this.value);
}

/// Database Shutdown Modes
enum DbShutdownMode {
  transactional(1),
  transactionalLocal(2),
  immediate(3),
  abort(4),
  final_(5); // Using final_ to avoid keyword conflict

  final int value;
  const DbShutdownMode(this.value);
}

/// Subscription Grouping Classes
enum SubscrGroupingClass {
  none(0),
  time(1);

  final int value;
  const SubscrGroupingClass(this.value);
}

/// Subscription Grouping Types
enum SubscrGroupingType {
  summary(1),
  last(2);

  final int value;
  const SubscrGroupingType(this.value);
}

/// Subscription Namespaces
enum SubscrNamespace {
  aq(1),
  dbChange(2);

  final int value;
  const SubscrNamespace(this.value);
}

/// Subscription Protocols
enum SubscrProtocol {
  callback(0),
  mail(1),
  server(2),
  http(3);

  final int value;
  const SubscrProtocol(this.value);
}

/// Event Types for Subscriptions
enum OracleEventType {
  none(0),
  startup(1),
  shutdown(2),
  shutdownAny(3),
  dereg(5),
  objChange(6),
  queryChange(7),
  aq(100);

  final int value;
  const OracleEventType(this.value);
}

/// Authentication Modes (Mapped from Python's AuthMode IntFlag)
/// Note: Dart enums don't directly support bit flags like Python's IntFlag.
/// These represent individual modes. Combinations might need bitwise ops on the integer values.
enum OracleAuthMode {
  default_(0x0001), // base_impl.AUTH_MODE_DEFAULT = 0x0001
  prelim(0x0008), // base_impl.AUTH_MODE_PRELIM = 0x0008
  sysasm(0x8000), // base_impl.AUTH_MODE_SYSASM = 0x8000
  sysbkp(0x20000), // base_impl.AUTH_MODE_SYSBKP = 0x20000
  sysdba(0x0002), // base_impl.AUTH_MODE_SYSDBA = 0x0002
  sysdgd(0x40000), // base_impl.AUTH_MODE_SYSDGD = 0x40000
  syskmt(0x80000), // base_impl.AUTH_MODE_SYSKMT = 0x80000
  sysoper(0x0004), // base_impl.AUTH_MODE_SYSOPER = 0x0004
  sysrac(0x100000); // base_impl.AUTH_MODE_SYSRAC = 0x100000

  final int value;
  const OracleAuthMode(this.value);
}

/// Pipeline Operation Types
enum PipelineOpType {
  // Values seem distinct, not flags, based on Python implementation detail
  callFunc, // = base_impl.PIPELINE_OP_TYPE_CALL_FUNC
  callProc, // = base_impl.PIPELINE_OP_TYPE_CALL_PROC
  commit, // = base_impl.PIPELINE_OP_TYPE_COMMIT
  execute, // = base_impl.PIPELINE_OP_TYPE_EXECUTE
  executeMany, // = base_impl.PIPELINE_OP_TYPE_EXECUTE_MANY
  fetchAll, // = base_impl.PIPELINE_OP_TYPE_FETCH_ALL
  fetchMany, // = base_impl.PIPELINE_OP_TYPE_FETCH_MANY
  fetchOne; // = base_impl.PIPELINE_OP_TYPE_FETCH_ONE
}

/// Pool Get Modes
enum PoolGetMode {
  wait(0), // base_impl.POOL_GETMODE_WAIT = 0
  noWait(1), // base_impl.POOL_GETMODE_NOWAIT = 1
  forceGet(2), // base_impl.POOL_GETMODE_FORCEGET = 2
  timedWait(3); // base_impl.POOL_GETMODE_TIMEDWAIT = 3

  final int value;
  const PoolGetMode(this.value);
}

/// Purity Levels for DRCP
enum Purity {
  default_(0), // base_impl.PURITY_DEFAULT = 0
  new_(1), // base_impl.PURITY_NEW = 1, using new_ to avoid keyword conflict
  self(2); // base_impl.PURITY_SELF = 2

  final int value;
  const Purity(this.value);
}

/// Vector Storage Formats
enum VectorFormat {
  float32(1), // base_impl.VECTOR_FORMAT_FLOAT32 = 1
  float64(2), // base_impl.VECTOR_FORMAT_FLOAT64 = 2
  int8(3), // base_impl.VECTOR_FORMAT_INT8 = 3
  binary(4); // base_impl.VECTOR_FORMAT_BINARY = 4

  final int value;
  const VectorFormat(this.value);
}

// Aliases provided at the end of enums.py are now integrated into the enums/consts above.