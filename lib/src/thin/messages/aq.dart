import 'dart:convert';
import 'dart:typed_data';

import '../../aq.dart';
import '../../dbobject.dart';
import '../../exceptions.dart';
import '../buffer.dart';
import '../codecs.dart';
import '../constants.dart';
import '../oson.dart';
import 'base.dart';

/// Base class for the messages used to enqueue and dequeue AQ messages.
abstract class AqBaseMessage extends Message {
  AqBaseMessage(this.queue) : super(queue.connection.impl);

  final OracleQueue queue;
  bool noMsgFound = false;

  @override
  void processErrorInfo(ReadBuffer buf) {
    super.processErrorInfo(buf);
    if (errorInfo.num == TNS_ERR_NO_MESSAGES_FOUND) {
      errorInfo.num = 0;
      errorOccurred = false;
      noMsgFound = true;
    }
  }

  DateTime? _processDate(ReadBuffer buf) {
    if (buf.readUB4() == 0) return null;
    final n = buf.readBytesRef();
    return n < 0 ? null : decodeDate(buf.refData, buf.refOffset, n);
  }

  void _processExtensions(ReadBuffer buf, OracleMessage props) {
    final numExtensions = buf.readUB4();
    if (numExtensions == 0) return;
    buf.skipUB1();
    for (var i = 0; i < numExtensions; i++) {
      final textValue = buf.readBytesWithLength();
      final binaryValue = buf.readBytesWithLength();
      final value = textValue ?? binaryValue;
      final keyword = buf.readUB2();
      if (value != null && keyword == TNS_AQ_EXT_KEYWORD_ORIGINAL_MSGID) {
        props.originalMsgId = value;
      }
    }
  }

  void processMsgProps(ReadBuffer buf, OracleMessage props) {
    props
      ..priority = buf.readSB4()
      ..delay = buf.readSB4()
      ..expiration = buf.readSB4()
      ..correlation = buf.readStrWithLength()
      ..numAttempts = buf.readSB4()
      ..exceptionQueue = buf.readStrWithLength()
      ..state = AqMessageState.fromValue(buf.readSB4())
      ..enqTime = _processDate(buf);
    buf.readBytesWithLength(); // enqueue transaction id
    _processExtensions(buf, props);
    if (buf.readUB4() > 0) {
      throw dpyError(ERR_NOT_IMPLEMENTED); // user properties
    }
    buf.skipUB4(); // csn
    buf.skipUB4(); // dsn
    final flags = buf.readUB4();
    props.deliveryMode = flags == TNS_KPD_AQ_BUFMSG
        ? AqDeliveryMode.buffered
        : AqDeliveryMode.persistent;
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_21_1) {
      buf.skipUB4(); // shard number
    }
  }

  Object? processPayload(ReadBuffer buf) {
    final payloadType = queue.payloadType;
    if (payloadType != null) {
      return readDbObject(buf, payloadType) ?? payloadType.newObject();
    }
    buf.readBytesWithLength(); // TOID
    buf.readBytesWithLength(); // OID
    buf.readBytesWithLength(); // snapshot
    buf.skipUB2(); // version
    final imageLength = buf.readUB4();
    buf.skipUB2(); // flags
    if (imageLength > 0) {
      final image = buf.readBytes()!;
      final payload = Uint8List.sublistView(image, 4, imageLength);
      return queue.isJson ? decodeOson(payload) : Uint8List.fromList(payload);
    }
    return queue.isJson ? null : Uint8List(0);
  }

  void processRecipients(ReadBuffer buf) {
    if (buf.readUB4() > 0) throw dpyError(ERR_NOT_IMPLEMENTED);
  }

  void writeMsgProps(WriteBuffer buf, OracleMessage props) {
    buf.writeUB4(props.priority);
    buf.writeUB4(props.delay);
    buf.writeSB4(props.expiration);
    _writeValueWithLength(buf, props.correlation);
    buf.writeUB4(0); // number of attempts
    _writeValueWithLength(buf, props.exceptionQueue);
    buf.writeUB4(props.state.value);
    buf.writeUB4(0); // enqueue time length
    buf.writeUB4(0); // enqueue transaction id length
    buf.writeUB4(4); // number of extensions
    buf.writeUint8(0x0e); // unknown extra byte
    _writeKeywordValuePair(buf, null, null, TNS_AQ_EXT_KEYWORD_AGENT_NAME);
    _writeKeywordValuePair(buf, null, null, TNS_AQ_EXT_KEYWORD_AGENT_ADDRESS);
    _writeKeywordValuePair(
        buf, null, const [0], TNS_AQ_EXT_KEYWORD_AGENT_PROTOCOL);
    _writeKeywordValuePair(buf, null, null, TNS_AQ_EXT_KEYWORD_ORIGINAL_MSGID);
    buf.writeUB4(0); // user property
    buf.writeUB4(0); // cscn
    buf.writeUB4(0); // dscn
    buf.writeUB4(0); // flags
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_21_1) {
      buf.writeUB4(0xffffffff); // shard id
    }
  }

  void writePayload(WriteBuffer buf, OracleMessage props) {
    if (queue.isJson) {
      final data =
          encodeOson(props.payload, maxFieldNameSize: conn.osonMaxFnameSize);
      buf.writeQLocator(data.length, writeLength: false);
      buf.writeBytesWithLength(data);
    } else if (queue.payloadType != null) {
      writeDbObject(buf, props.payload as OracleDbObject);
    } else {
      buf.writeRaw(props.rawPayload);
    }
  }

  void writeRecipients(WriteBuffer buf, OracleMessage props) {
    var index = 0;
    for (final recipient in props.recipients!) {
      _writeKeywordValuePair(buf, recipient, null, index);
      _writeKeywordValuePair(buf, null, null, index + 1);
      _writeKeywordValuePair(buf, null, const [0], index + 2);
      index += 3;
    }
  }

  void _writeKeywordValuePair(
      WriteBuffer buf, String? textValue, List<int>? binaryValue, int keyword) {
    _writeValueWithLength(buf, textValue);
    _writeValueWithLength(buf, binaryValue);
    buf.writeUB2(keyword);
  }

  void _writeValueWithLength(WriteBuffer buf, Object? value) {
    if (value == null) {
      buf.writeUB4(0);
      return;
    }
    final bytes = value is String ? utf8.encode(value) : value as List<int>;
    buf.writeUB4(bytes.length);
    buf.writeBytesWithLength(bytes);
  }
}

/// Enqueues a single message.
class AqEnqMessage extends AqBaseMessage {
  AqEnqMessage(super.queue, this.props) {
    functionCode = TNS_FUNC_AQ_ENQ;
  }

  final OracleMessage props;

  @override
  void processReturnParameters(ReadBuffer buf) {
    props.msgId =
        Uint8List.fromList(buf.readRawBytes(TNS_AQ_MESSAGE_ID_LENGTH));
    buf.skipUB2(); // extensions length
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final options = queue.enqOptions;
    final queueName = utf8.encode(queue.name);
    final recipients = props.recipients;
    writeFunctionCode(buf);
    buf.writeUint8(1); // queue name (pointer)
    buf.writeUB4(queueName.length); // queue name length
    writeMsgProps(buf, props);
    if (recipients == null) {
      buf.writeUint8(0); // recipients (pointer)
      buf.writeUB4(0); // number of key/value pairs
    } else {
      buf.writeUint8(1); // recipients (pointer)
      buf.writeUB4(3 * recipients.length);
    }
    buf.writeUB4(options.visibility.value);
    buf.writeUint8(0); // relative message id
    buf.writeUB4(0); // relative message length
    buf.writeUB4(0); // sequence deviation
    buf.writeUint8(1); // TOID of payload (pointer)
    buf.writeUB4(16); // TOID of payload length
    buf.writeUB2(TNS_AQ_MESSAGE_VERSION);
    if (queue.isJson) {
      buf.writeUint8(0); // payload (pointer)
      buf.writeUint8(0); // RAW payload (pointer)
      buf.writeUB4(0); // RAW payload length
    } else if (queue.payloadType != null) {
      buf.writeUint8(1); // payload (pointer)
      buf.writeUint8(0); // RAW payload (pointer)
      buf.writeUB4(0); // RAW payload length
    } else {
      buf.writeUint8(0); // payload (pointer)
      buf.writeUint8(1); // RAW payload (pointer)
      buf.writeUB4(props.rawPayload.length);
    }
    buf.writeUint8(1); // return message id (pointer)
    buf.writeUB4(TNS_AQ_MESSAGE_ID_LENGTH); // return message id length
    buf.writeUB4(options.deliveryMode == AqDeliveryMode.buffered
        ? TNS_KPD_AQ_BUFMSG
        : 0); // enqueue flags
    buf.writeUint8(0); // extensions 1 (pointer)
    buf.writeUB4(0); // number of extensions 1
    buf.writeUint8(0); // extensions 2 (pointer)
    buf.writeUB4(0); // number of extensions 2
    buf.writeUint8(0); // source sequence number
    buf.writeUB4(0); // source sequence length
    buf.writeUint8(0); // max sequence number
    buf.writeUB4(0); // max sequence length
    buf.writeUint8(0); // output ack length
    buf.writeUint8(0); // correlation (pointer)
    buf.writeUB4(0); // correlation length
    buf.writeUint8(0); // sender name (pointer)
    buf.writeUB4(0); // sender name length
    buf.writeUint8(0); // sender address (pointer)
    buf.writeUB4(0); // sender address length
    buf.writeUint8(0); // sender charset id (pointer)
    buf.writeUint8(0); // sender ncharset id (pointer)
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_20_1) {
      buf.writeUint8(queue.isJson ? 1 : 0); // JSON payload (pointer)
    }
    buf.writeBytesWithLength(queueName);
    if (recipients != null) writeRecipients(buf, props);
    buf.writeRaw(queue.payloadToid);
    writePayload(buf, props);
  }
}

/// Dequeues a single message.
class AqDeqMessage extends AqBaseMessage {
  AqDeqMessage(super.queue) {
    functionCode = TNS_FUNC_AQ_DEQ;
  }

  final OracleMessage props = OracleMessage();

  @override
  void processReturnParameters(ReadBuffer buf) {
    if (buf.readUB4() == 0) return;
    processMsgProps(buf, props);
    processRecipients(buf);
    props.payload = processPayload(buf);
    props.msgId =
        Uint8List.fromList(buf.readRawBytes(TNS_AQ_MESSAGE_ID_LENGTH));
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final options = queue.deqOptions;
    final queueName = utf8.encode(queue.name);
    final consumerName = _encodeOrNull(options.consumerName);
    final correlation = _encodeOrNull(options.correlation);
    final condition = _encodeOrNull(options.condition);
    final msgId = options.msgId;
    writeFunctionCode(buf);
    buf.writeUint8(1); // queue name (pointer)
    buf.writeUB4(queueName.length); // queue name length
    buf.writeUint8(1); // message properties
    buf.writeUint8(1); // msg props length
    buf.writeUint8(1); // recipient list
    buf.writeUint8(1); // recipient list length
    _writePointerAndLength(buf, consumerName);
    buf.writeSB4(options.mode.value);
    buf.writeSB4(options.navigation.value);
    buf.writeSB4(options.visibility.value);
    buf.writeSB4(options.wait);
    if (msgId != null) {
      buf.writeUint8(1); // select message id
      buf.writeUB4(TNS_AQ_MESSAGE_ID_LENGTH);
    } else {
      buf.writeUint8(0); // select message id
      buf.writeUB4(0); // select message id length
    }
    _writePointerAndLength(buf, correlation);
    buf.writeUint8(1); // toid of payload
    buf.writeUB4(16); // toid length
    buf.writeUB2(TNS_AQ_MESSAGE_VERSION);
    buf.writeUint8(1); // payload
    buf.writeUint8(1); // return msg id
    buf.writeUB4(TNS_AQ_MESSAGE_ID_LENGTH);
    buf.writeUB4(options.deliveryMode.dequeueFlags); // dequeue flags
    _writePointerAndLength(buf, condition);
    buf.writeUint8(0); // extensions
    buf.writeUB4(0); // number of extensions
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_20_1) {
      buf.writeUint8(0); // JSON payload
    }
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_21_1) {
      buf.writeUB4(0xffffffff); // shard id
    }
    buf.writeBytesWithLength(queueName);
    if (consumerName != null) buf.writeBytesWithLength(consumerName);
    if (msgId != null) buf.writeRaw(_paddedMsgId(msgId));
    if (correlation != null) buf.writeBytesWithLength(correlation);
    buf.writeRaw(queue.payloadToid);
    if (condition != null) buf.writeBytesWithLength(condition);
  }

  static void _writePointerAndLength(WriteBuffer buf, List<int>? value) {
    if (value != null) {
      buf.writeUint8(1);
      buf.writeUB4(value.length);
    } else {
      buf.writeUint8(0);
      buf.writeUB4(0);
    }
  }
}

/// Enqueues or dequeues many messages in a single round trip.
class AqArrayMessage extends AqBaseMessage {
  AqArrayMessage.enqueue(super.queue, this.props)
      : operation = TNS_AQ_ARRAY_ENQ,
        numIters = props.length {
    functionCode = TNS_FUNC_ARRAY_AQ;
  }

  AqArrayMessage.dequeue(super.queue, this.numIters)
      : operation = TNS_AQ_ARRAY_DEQ,
        props = [for (var i = 0; i < numIters; i++) OracleMessage()] {
    functionCode = TNS_FUNC_ARRAY_AQ;
  }

  final int operation;
  final List<OracleMessage> props;
  int numIters;

  @override
  void processReturnParameters(ReadBuffer buf) {
    final n = buf.readUB4();
    for (var i = 0; i < n; i++) {
      final p = props[i];
      if (buf.readUB2() > 0) {
        buf.skipUB1();
        processMsgProps(buf, p);
      }
      processRecipients(buf);
      if (buf.readUB2() > 0) p.payload = processPayload(buf);
      final msgId = buf.readBytesWithLength();
      if (msgId != null) {
        if (operation == TNS_AQ_ARRAY_ENQ) {
          for (var j = 0; j < props.length; j++) {
            props[j].msgId = Uint8List.fromList(
                Uint8List.sublistView(msgId, j * 16, (j + 1) * 16));
          }
        } else {
          p.msgId = msgId;
        }
      }
      if (buf.readUB2() > 0) throw dpyError(ERR_NOT_IMPLEMENTED); // extensions
      buf.skipUB2(); // output ack
    }
    numIters = operation == TNS_AQ_ARRAY_ENQ ? buf.readUB4() : n;
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final enq = operation == TNS_AQ_ARRAY_ENQ;
    writeFunctionCode(buf);
    if (enq) {
      buf.writeUint8(0); // input params
      buf.writeUB4(0); // length
    } else {
      buf.writeUint8(1);
      buf.writeUB4(numIters);
    }
    buf.writeUB4(TNS_AQ_ARRAY_FLAGS_RETURN_MESSAGE_ID);
    buf.writeUint8(1); // output params
    buf.writeUint8(enq ? 0 : 1); // length
    buf.writeSB4(operation);
    buf.writeUint8(enq ? 1 : 0); // num iters (pointer)
    if (buf.caps.ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_21_1) {
      buf.writeUB4(0xffff); // shard id
    }
    if (enq) {
      buf.writeUB4(numIters);
      _writeArrayEnq(buf);
    } else {
      _writeArrayDeq(buf);
    }
  }

  void _writeArrayDeq(WriteBuffer buf) {
    final options = queue.deqOptions;
    final queueName = utf8.encode(queue.name);
    final msgId = options.msgId;
    for (final p in props) {
      buf.writeUB4(queueName.length);
      buf.writeBytesWithLength(queueName);
      writeMsgProps(buf, p);
      buf.writeUB4(0); // num recipients
      _writeValueWithLength(buf, options.consumerName);
      buf.writeSB4(options.mode.value);
      buf.writeSB4(options.navigation.value);
      buf.writeSB4(options.visibility.value);
      buf.writeSB4(options.wait);
      _writeValueWithLength(buf, msgId == null ? null : _paddedMsgId(msgId));
      _writeValueWithLength(buf, options.correlation);
      _writeValueWithLength(buf, options.condition);
      buf.writeUB4(0); // extensions
      buf.writeUB4(0); // rel msg id
      buf.writeSB4(0); // seq deviation
      buf.writeUB4(16); // toid length
      buf.writeBytesWithLength(queue.payloadToid);
      buf.writeUB2(TNS_AQ_MESSAGE_VERSION);
      buf.writeUB4(0); // payload length
      buf.writeUB4(0); // raw pay length
      buf.writeUB4(0);
      buf.writeUB4(options.deliveryMode.dequeueFlags);
      buf.writeUB4(0); // extensions len
      buf.writeUB4(0); // source seq len
    }
  }

  void _writeArrayEnq(WriteBuffer buf) {
    final options = queue.enqOptions;
    final queueName = utf8.encode(queue.name);
    final flags =
        options.deliveryMode == AqDeliveryMode.buffered ? TNS_KPD_AQ_BUFMSG : 0;
    buf.writeUB4(0); // rel msgid len
    buf.writeUint8(TNS_MSG_TYPE_ROW_HEADER);
    buf.writeUB4(queueName.length);
    buf.writeBytesWithLength(queueName);
    buf.writeRaw(queue.payloadToid);
    buf.writeUB2(TNS_AQ_MESSAGE_VERSION);
    buf.writeUB4(flags);
    for (final p in props) {
      buf.writeUint8(TNS_MSG_TYPE_ROW_DATA);
      buf.writeUB4(flags); // aqi flags
      writeMsgProps(buf, p);
      final recipients = p.recipients;
      if (recipients == null) {
        buf.writeUB4(0); // num recipients
      } else {
        buf.writeUB4(3 * recipients.length);
        writeRecipients(buf, p);
      }
      buf.writeSB4(options.visibility.value);
      buf.writeUB4(0); // relative msg id
      buf.writeSB4(0); // seq deviation
      if (queue.payloadType == null && !queue.isJson) {
        buf.writeUB4(p.rawPayload.length);
      }
      writePayload(buf, p);
    }
    buf.writeUint8(TNS_MSG_TYPE_STATUS);
  }
}

List<int>? _encodeOrNull(String? value) =>
    value == null || value.isEmpty ? null : utf8.encode(value);

Uint8List _paddedMsgId(Uint8List msgId) {
  final padded = Uint8List(16);
  padded.setRange(0, msgId.length < 16 ? msgId.length : 16, msgId);
  return padded;
}
