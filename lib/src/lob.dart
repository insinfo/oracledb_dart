import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'exceptions.dart';
import 'thin/buffer.dart';
import 'thin/connection_impl.dart';
import 'thin/constants.dart';
import 'thin/messages/lob_op.dart';
import 'thin/types.dart';

/// A large object (CLOB, NCLOB, BLOB or BFILE) referenced by a locator.
///
/// LOBs are returned by queries when [OracleCursor.fetchLobsAsValues] is
/// false, and can be created with [OracleConnection.createLob]. Offsets
/// start at 1 and, for CLOBs and NCLOBs, offsets and amounts are measured in
/// characters (UTF-16 code units); for BLOBs they are measured in bytes.
class OracleLob {
  OracleLob.fromLocator(this._conn, this.type, this.locator);

  final ThinConnImpl _conn;

  /// The type of the LOB.
  final DbType type;

  /// The locator (internal).
  final LobLocator locator;

  bool _freed = false;

  bool get isBinary => locator.isBinary;

  /// Whether the LOB is a temporary LOB.
  bool get isTemporary => locator.isTemporary;

  Future<LobOpMessage> _process(LobOpMessage message) async {
    if (_freed) throw StateError('the LOB has been freed');
    await _conn.protocol.processSingleMessage(message);
    return message;
  }

  LobOpMessage _message(int operation) =>
      LobOpMessage(_conn, operation, locator);

  /// Returns the size of the LOB (characters for character LOBs).
  Future<int> size() async {
    if (locator.hasMetadata) return locator.size;
    final message = _message(TNS_LOB_OP_GET_LENGTH)..sendAmount = true;
    await _process(message);
    return message.amount;
  }

  /// Returns the chunk size of the LOB; reading and writing in multiples of
  /// it is most efficient.
  Future<int> chunkSize() async {
    if (locator.hasMetadata) return locator.chunkSize;
    final message = _message(TNS_LOB_OP_GET_CHUNK_SIZE)..sendAmount = true;
    await _process(message);
    return message.amount;
  }

  /// Reads [amount] characters (or bytes) starting at [offset] (1 based);
  /// by default the remainder of the LOB is read. Returns a [String] for
  /// CLOBs/NCLOBs and a [Uint8List] for BLOBs/BFILEs.
  Future<Object> read({int offset = 1, int? amount}) async {
    if (offset < 1) throw dpyError(ERR_INVALID_LOB_OFFSET);
    if (amount == null) {
      amount = await size() - offset + 1;
      if (amount <= 0) return isBinary ? Uint8List(0) : '';
    }
    if (amount > 0xffffffff) amount = 0xffffffff;
    var shouldClose = false;
    if (type == DbType.bfile && !await isOpen()) {
      shouldClose = true;
      await open();
    }
    final message = _message(TNS_LOB_OP_READ)
      ..sourceOffset = offset
      ..amount = amount
      ..sendAmount = true;
    await _process(message);
    if (shouldClose) await close();
    return _decode(message.data ?? Uint8List(0));
  }

  /// Reads the whole LOB as a [String] (character LOBs).
  Future<String> readString() async => await read() as String;

  /// Reads the whole LOB as bytes (binary LOBs).
  Future<Uint8List> readBytes() async => await read() as Uint8List;

  /// Streams the content of the LOB in pieces of [pieceSize] characters (or
  /// bytes); by default a multiple of the chunk size close to 1 MB is used.
  /// This allows LOBs larger than the available memory to be processed.
  Stream<Object> stream({int? pieceSize}) async* {
    final total = await size();
    var piece = pieceSize;
    if (piece == null) {
      final chunk = await chunkSize();
      piece = chunk <= 0 ? 1 << 20 : chunk * ((1 << 20) ~/ chunk + 1);
    }
    for (var offset = 1; offset <= total; offset += piece) {
      final remaining = total - offset + 1;
      yield await read(
          offset: offset, amount: remaining < piece ? remaining : piece);
    }
  }

  /// Writes [data] (a [String] for character LOBs, bytes for binary LOBs)
  /// starting at [offset] (1 based).
  Future<void> write(Object data, {int offset = 1}) async {
    if (offset < 1) throw dpyError(ERR_INVALID_LOB_OFFSET);
    final message = _message(TNS_LOB_OP_WRITE)
      ..sourceOffset = offset
      ..data = _encode(data);
    await _process(message);
    locator.hasMetadata = false;
  }

  /// Truncates the LOB to [newSize] characters (or bytes).
  Future<void> trim([int newSize = 0]) async {
    final message = _message(TNS_LOB_OP_TRIM)
      ..amount = newSize
      ..sendAmount = true;
    await _process(message);
    locator.hasMetadata = false;
  }

  /// Opens the LOB; while it is open, writes do not update indexes until it
  /// is closed, which makes many small writes cheaper.
  Future<void> open() async {
    if (type == DbType.bfile) {
      await _process(_message(TNS_LOB_OP_FILE_OPEN)
        ..amount = TNS_LOB_OPEN_READ_ONLY
        ..sendAmount = true);
    } else {
      await _process(_message(TNS_LOB_OP_OPEN)
        ..amount = TNS_LOB_OPEN_READ_WRITE
        ..sendAmount = true);
    }
  }

  Future<void> close() async {
    await _process(_message(
        type == DbType.bfile ? TNS_LOB_OP_FILE_CLOSE : TNS_LOB_OP_CLOSE));
  }

  Future<bool> isOpen() async {
    final message = _message(
        type == DbType.bfile ? TNS_LOB_OP_FILE_ISOPEN : TNS_LOB_OP_IS_OPEN);
    await _process(message);
    return message.boolFlag;
  }

  /// Returns whether the file referenced by a BFILE exists.
  Future<bool> fileExists() async {
    final message = _message(TNS_LOB_OP_FILE_EXISTS);
    await _process(message);
    return message.boolFlag;
  }

  /// Returns the directory alias and file name of a BFILE.
  (String, String) get fileName {
    final loc = locator.locator;
    const dirOffset = TNS_LOB_LOC_FIXED_OFFSET + 2;
    final dirLen = (loc[TNS_LOB_LOC_FIXED_OFFSET] << 8) |
        loc[TNS_LOB_LOC_FIXED_OFFSET + 1];
    final fileOffset = dirOffset + dirLen + 2;
    final fileLen =
        (loc[dirOffset + dirLen] << 8) | loc[dirOffset + dirLen + 1];
    return (
      utf8.decode(loc.sublist(dirOffset, dirOffset + dirLen)),
      utf8.decode(loc.sublist(fileOffset, fileOffset + fileLen)),
    );
  }

  /// Frees a temporary LOB (on the next round trip to the database). Has no
  /// effect for persistent LOBs.
  void free() {
    if (_freed) return;
    _freed = true;
    if (isTemporary) {
      _conn.tempLobsToClose.add(locator.locator);
      _conn.tempLobsTotalSize += locator.locator.length;
    }
  }

  Object _decode(Uint8List data) {
    if (isBinary) return data;
    if (locator.usesUtf16) return decodeUtf16(data, 0, data.length);
    return utf8.decode(data, allowMalformed: true);
  }

  Uint8List _encode(Object data) {
    if (isBinary) {
      if (data is! List<int>) {
        throw ArgumentError('only bytes can be written to BLOBs');
      }
      return data is Uint8List ? data : Uint8List.fromList(data);
    }
    if (data is! String) {
      throw ArgumentError('only strings can be written to CLOBs and NCLOBs');
    }
    return locator.usesUtf16 ? encodeUtf16(data) : utf8.encode(data);
  }

  /// Creates a temporary LOB of the given type.
  static Future<OracleLob> createTemporary(
      ThinConnImpl conn, DbType type) async {
    final locator = LobLocator(type.oraTypeNum, type.csfrm, Uint8List(40));
    final message = LobOpMessage(conn, TNS_LOB_OP_CREATE_TEMP, locator)
      ..destLength = TNS_DURATION_SESSION
      ..sourceOffset = type.csfrm
      ..destOffset = type.oraTypeNum;
    await conn.protocol.processSingleMessage(message);
    return OracleLob.fromLocator(conn, type, locator);
  }

  @override
  String toString() => 'OracleLob(${type.name})';
}
