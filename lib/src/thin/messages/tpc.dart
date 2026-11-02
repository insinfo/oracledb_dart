import 'dart:convert';
import 'dart:typed_data';

import '../buffer.dart';
import '../constants.dart';
import 'base.dart';

/// A transaction identifier for two-phase commit (TPC) transactions.
class Xid {
  const Xid(this.formatId, this.globalTransactionId, this.branchQualifier);

  final int formatId;

  /// The global transaction id (a [String] or bytes, at most 64 bytes).
  final Object globalTransactionId;

  /// The branch qualifier (a [String] or bytes, at most 64 bytes).
  final Object branchQualifier;

  Uint8List get _gtrid => _bytes(globalTransactionId);
  Uint8List get _bqual => _bytes(branchQualifier);

  static Uint8List _bytes(Object v) =>
      v is Uint8List ? v : Uint8List.fromList(utf8.encode(v as String));

  @override
  bool operator ==(Object other) =>
      other is Xid &&
      other.formatId == formatId &&
      _eq(other._gtrid, _gtrid) &&
      _eq(other._bqual, _bqual);

  static bool _eq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(formatId, Object.hashAll(_gtrid), Object.hashAll(_bqual));

  @override
  String toString() => 'Xid($formatId, $globalTransactionId, $branchQualifier)';
}

/// Writes the XID header fields; returns the padded XID bytes to write at
/// the end of the message, if any.
Uint8List? _writeXidHeader(WriteBuffer buf, Xid? xid) {
  if (xid == null) {
    buf.writeUB4(0); // format id
    buf.writeUB4(0); // global transaction id length
    buf.writeUB4(0); // branch qualifier length
    buf.writeUint8(0); // pointer (XID)
    buf.writeUB4(0); // XID length
    return null;
  }
  final gtrid = xid._gtrid, bqual = xid._bqual;
  final xidBytes = Uint8List(128)
    ..setAll(0, gtrid)
    ..setAll(gtrid.length, bqual);
  buf.writeUB4(xid.formatId);
  buf.writeUB4(gtrid.length);
  buf.writeUB4(bqual.length);
  buf.writeUint8(1); // pointer (XID)
  buf.writeUB4(xidBytes.length);
  return xidBytes;
}

/// Starts, attaches to or detaches from a TPC transaction.
class TransactionSwitchMessage extends Message {
  TransactionSwitchMessage(super.conn, this.operation,
      {this.xid, this.flags = 0, this.timeout = 0, this.context}) {
    functionCode = TNS_FUNC_TPC_TXN_SWITCH;
  }

  final int operation;
  final Xid? xid;
  final int flags;
  final int timeout;
  Uint8List? context;
  int applicationValue = 0;

  @override
  void processReturnParameters(ReadBuffer buf) {
    applicationValue = buf.readUB4();
    final length = buf.readUB2();
    context = Uint8List.fromList(buf.readRawBytes(length));
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final internalName =
        conn.internalName == null ? null : utf8.encode(conn.internalName!);
    final externalName =
        conn.externalName == null ? null : utf8.encode(conn.externalName!);
    final context = this.context;
    writeFunctionCode(buf);
    buf.writeUB4(operation);
    if (context != null) {
      buf.writeUint8(1); // pointer (transaction context)
      buf.writeUB4(context.length);
    } else {
      buf.writeUint8(0); // pointer (transaction context)
      buf.writeUB4(0); // transaction context length
    }
    final xidBytes = _writeXidHeader(buf, xid);
    buf.writeUB4(flags);
    buf.writeUB4(timeout);
    buf.writeUint8(1); // pointer (application value)
    buf.writeUint8(1); // pointer (return context)
    buf.writeUint8(1); // pointer (return context length)
    for (final name in [internalName, externalName]) {
      if (name != null) {
        buf.writeUint8(1); // pointer (name)
        buf.writeUB4(name.length);
      } else {
        buf.writeUint8(0); // pointer (name)
        buf.writeUB4(0); // length of name
      }
    }
    if (context != null) buf.writeRaw(context);
    if (xidBytes != null) buf.writeRaw(xidBytes);
    buf.writeUB4(applicationValue);
    if (internalName != null) buf.writeRaw(internalName);
    if (externalName != null) buf.writeRaw(externalName);
  }
}

/// Changes the state of a TPC transaction (prepare, commit, rollback).
class TransactionChangeStateMessage extends Message {
  TransactionChangeStateMessage(super.conn, this.operation, this.state,
      {this.xid, this.context}) {
    functionCode = TNS_FUNC_TPC_TXN_CHANGE_STATE;
  }

  final int operation;
  int state;
  final Xid? xid;
  final Uint8List? context;
  int flags = 0;

  @override
  void processReturnParameters(ReadBuffer buf) {
    state = buf.readUB4();
  }

  @override
  void writeMessage(WriteBuffer buf) {
    final context = this.context;
    writeFunctionCode(buf);
    buf.writeUB4(operation);
    if (context != null) {
      buf.writeUint8(1); // pointer (context)
      buf.writeUB4(context.length);
    } else {
      buf.writeUint8(0); // pointer (context)
      buf.writeUB4(0); // context length
    }
    final xidBytes = _writeXidHeader(buf, xid);
    buf.writeUB4(0); // timeout
    buf.writeUB4(state);
    buf.writeUint8(1); // pointer (out state)
    buf.writeUB4(flags);
    if (context != null) buf.writeRaw(context);
    if (xidBytes != null) buf.writeRaw(xidBytes);
  }
}
