import 'dart:convert';
import 'dart:typed_data';

import 'connection.dart';
import 'dbobject.dart';
import 'exceptions.dart';
import 'thin/constants.dart';
import 'thin/messages/aq.dart';

/// How messages are delivered: persistent messages are stored in the queue
/// table, buffered messages are kept in memory.
enum AqDeliveryMode {
  persistent(TNS_AQ_MSG_PERSISTENT),
  buffered(TNS_AQ_MSG_BUFFERED),
  persistentOrBuffered(TNS_AQ_MSG_PERSISTENT_OR_BUFFERED);

  const AqDeliveryMode(this.value);

  final int value;

  int get dequeueFlags => switch (this) {
        persistent => 0,
        buffered => TNS_KPD_AQ_BUFMSG,
        persistentOrBuffered => TNS_KPD_AQ_EITHER,
      };
}

/// Whether enqueue and dequeue operations are part of the current
/// transaction ([onCommit]) or take effect immediately.
enum AqVisibility {
  immediate(TNS_AQ_DEQ_IMMEDIATE),
  onCommit(TNS_AQ_DEQ_ON_COMMIT);

  const AqVisibility(this.value);

  final int value;
}

/// Locking behavior of dequeue operations.
enum AqDeqMode {
  browse(TNS_AQ_DEQ_BROWSE),
  locked(TNS_AQ_DEQ_LOCKED),
  remove(TNS_AQ_DEQ_REMOVE),
  removeNoData(TNS_AQ_DEQ_REMOVE_NODATA);

  const AqDeqMode(this.value);

  final int value;
}

/// The position of the message that is dequeued.
enum AqDeqNavigation {
  firstMessage(TNS_AQ_DEQ_FIRST_MSG),
  nextTransaction(TNS_AQ_DEQ_NEXT_TRANSACTION),
  nextMessage(TNS_AQ_DEQ_NEXT_MSG);

  const AqDeqNavigation(this.value);

  final int value;
}

/// The state of a dequeued message.
enum AqMessageState {
  ready(TNS_AQ_MSG_READY),
  waiting(TNS_AQ_MSG_WAITING),
  processed(TNS_AQ_MSG_PROCESSED),
  expired(TNS_AQ_MSG_EXPIRED);

  const AqMessageState(this.value);

  final int value;

  static AqMessageState fromValue(int value) =>
      values.firstWhere((s) => s.value == value, orElse: () => ready);
}

/// Options used when enqueuing messages.
class AqEnqOptions {
  AqVisibility visibility = AqVisibility.onCommit;
  AqDeliveryMode deliveryMode = AqDeliveryMode.persistent;
}

/// Options used when dequeuing messages.
class AqDeqOptions {
  /// Waits until a message is available.
  static const int waitForever = -1;

  /// Returns immediately when no message is available.
  static const int noWait = 0;

  /// A condition (like a WHERE clause) the messages must satisfy, using
  /// `tab_user_data` for the payload attributes.
  String? condition;

  /// The consumer, for multi-consumer queues.
  String? consumerName;

  /// The correlation identifier of the messages to dequeue (`%` and `_` are
  /// wildcards).
  String? correlation;

  AqDeliveryMode deliveryMode = AqDeliveryMode.persistent;
  AqDeqMode mode = AqDeqMode.remove;

  /// The identifier of the message to dequeue.
  Uint8List? msgId;
  AqDeqNavigation navigation = AqDeqNavigation.nextMessage;
  AqVisibility visibility = AqVisibility.onCommit;

  /// The number of seconds to wait for a message ([waitForever] or
  /// [noWait] are also accepted).
  int wait = waitForever;
}

/// A message enqueued into or dequeued from a queue.
class OracleMessage {
  OracleMessage({
    this.payload,
    this.correlation,
    this.delay = TNS_AQ_MSG_NO_DELAY,
    this.expiration = TNS_AQ_MSG_NO_EXPIRATION,
    this.exceptionQueue,
    this.priority = 0,
    this.recipients,
  });

  /// The payload: a [String] or bytes for RAW queues, a JSON value for JSON
  /// queues or an [OracleDbObject] for queues of an object type.
  Object? payload;

  String? correlation;

  /// The number of seconds before the message is available for dequeuing.
  int delay;

  /// The number of seconds the message is available for dequeuing (-1 for
  /// no expiration).
  int expiration;

  /// The queue that receives the message if it cannot be processed.
  String? exceptionQueue;
  int priority;

  /// The consumers of the message, for multi-consumer queues.
  List<String>? recipients;

  // values set by the database
  Uint8List? msgId;
  Uint8List? originalMsgId;
  DateTime? enqTime;
  int numAttempts = 0;
  AqMessageState state = AqMessageState.ready;
  AqDeliveryMode deliveryMode = AqDeliveryMode.persistent;

  Uint8List get rawPayload {
    final p = payload;
    return p is String ? utf8.encode(p) : p as Uint8List;
  }

  @override
  String toString() => 'OracleMessage($payload)';
}

/// A queue of Oracle Database Advanced Queuing (AQ), created with
/// [OracleConnection.queue].
class OracleQueue {
  OracleQueue(this.connection, this.name,
      {this.payloadType, this.isJson = false})
      : payloadToid = isJson
            ? _toid(0x47)
            : payloadType != null
                ? payloadType.oid!
                : _toid(0x17);

  static Uint8List _toid(int last) => Uint8List(16)..[15] = last;

  final OracleConnection connection;
  final String name;

  /// The type of the payloads (null for RAW and JSON queues).
  final OracleDbObjectType? payloadType;

  /// Whether the payloads are JSON values.
  final bool isJson;
  final Uint8List payloadToid;
  final AqDeqOptions deqOptions = AqDeqOptions();
  final AqEnqOptions enqOptions = AqEnqOptions();

  void _verify(OracleMessage message) {
    final payload = message.payload;
    if (payload == null) throw dpyError(ERR_MESSAGE_HAS_NO_PAYLOAD);
    final ok = payloadType != null
        ? payload is OracleDbObject && payload.type == payloadType
        : isJson
            ? payload is Map || payload is List
            : payload is String || payload is Uint8List;
    if (!ok) throw dpyError(ERR_PAYLOAD_CANNOT_BE_ENQUEUED);
  }

  /// Enqueues a message; its [OracleMessage.msgId] is set.
  Future<void> enqOne(OracleMessage message) {
    connection.checkConnected();
    _verify(message);
    return connection.impl.protocol
        .processSingleMessage(AqEnqMessage(this, message));
  }

  /// Enqueues many messages in a single round trip.
  Future<void> enqMany(List<OracleMessage> messages) {
    connection.checkConnected();
    messages.forEach(_verify);
    return connection.impl.protocol
        .processSingleMessage(AqArrayMessage.enqueue(this, messages));
  }

  /// Dequeues a message, returning null if none is available within the
  /// wait time of [deqOptions].
  Future<OracleMessage?> deqOne() async {
    connection.checkConnected();
    final message = AqDeqMessage(this);
    await connection.impl.protocol.processSingleMessage(message);
    return message.noMsgFound ? null : message.props;
  }

  /// Dequeues up to [maxMessages] messages in a single round trip.
  Future<List<OracleMessage>> deqMany(int maxMessages) async {
    connection.checkConnected();
    final message = AqArrayMessage.dequeue(this, maxMessages);
    await connection.impl.protocol.processSingleMessage(message);
    if (message.noMsgFound) return [];
    return message.props.sublist(0, message.numIters);
  }

  @override
  String toString() => 'OracleQueue($name)';
}
