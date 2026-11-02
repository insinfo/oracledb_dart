// Encoding and decoding of OSON, the binary JSON format used by the native
// JSON type of Oracle Database 21c and later.

import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import 'codecs.dart';
import 'constants.dart';
import 'vector.dart';

/// Decodes an OSON image into Dart values: [Map], [List], [String], [num]
/// (or [BigInt]), [bool], null, [DateTime], [Duration], [Uint8List] and
/// vectors.
Object? decodeOson(Uint8List data) => _OsonDecoder(data).decode();

/// Encodes a Dart value as an OSON image.
Uint8List encodeOson(Object? value, {int maxFieldNameSize = 255}) =>
    _OsonEncoder(maxFieldNameSize).encode(value);

class _OsonDecoder {
  _OsonDecoder(this.data) : bd = ByteData.sublistView(data);

  final Uint8List data;
  final ByteData bd;
  int pos = 0;
  int fieldIdLength = 1;
  bool relativeOffsets = false;
  int treeSegPos = 0;
  late List<String> fieldNames;

  int _u8() => data[pos++];
  int _u16() {
    final v = bd.getUint16(pos);
    pos += 2;
    return v;
  }

  int _u32() {
    final v = bd.getUint32(pos);
    pos += 4;
    return v;
  }

  Uint8List _raw(int n) {
    final v = Uint8List.sublistView(data, pos, pos + n);
    pos += n;
    return v;
  }

  Object? decode() {
    if (data.length < 4 ||
        data[0] != TNS_JSON_MAGIC_BYTE_1 ||
        data[1] != TNS_JSON_MAGIC_BYTE_2 ||
        data[2] != TNS_JSON_MAGIC_BYTE_3) {
      throw dpyError(ERR_UNEXPECTED_DATA, args: {'data': 'OSON header'});
    }
    pos = 3;
    final version = _u8();
    if (version != TNS_JSON_VERSION_MAX_FNAME_255 &&
        version != TNS_JSON_VERSION_MAX_FNAME_65535) {
      throw dpyError(ERR_OSON_VERSION_NOT_SUPPORTED,
          args: {'version': version});
    }
    final primaryFlags = _u16();
    relativeOffsets = primaryFlags & TNS_JSON_FLAG_REL_OFFSET_MODE != 0;
    if (primaryFlags & TNS_JSON_FLAG_IS_SCALAR != 0) {
      pos += primaryFlags & TNS_JSON_FLAG_TREE_SEG_UINT32 != 0 ? 4 : 2;
      return _decodeNode();
    }
    int numShortFieldNames;
    if (primaryFlags & TNS_JSON_FLAG_NUM_FNAMES_UINT32 != 0) {
      numShortFieldNames = _u32();
      fieldIdLength = 4;
    } else if (primaryFlags & TNS_JSON_FLAG_NUM_FNAMES_UINT16 != 0) {
      numShortFieldNames = _u16();
      fieldIdLength = 2;
    } else {
      numShortFieldNames = _u8();
      fieldIdLength = 1;
    }
    int shortOffsetsSize, shortSegSize;
    if (primaryFlags & TNS_JSON_FLAG_FNAMES_SEG_UINT32 != 0) {
      shortOffsetsSize = 4;
      shortSegSize = _u32();
    } else {
      shortOffsetsSize = 2;
      shortSegSize = _u16();
    }
    var numLongFieldNames = 0, longOffsetsSize = 0, longSegSize = 0;
    if (version == TNS_JSON_VERSION_MAX_FNAME_65535) {
      final secondaryFlags = _u16();
      longOffsetsSize =
          secondaryFlags & TNS_JSON_FLAG_SEC_FNAMES_SEG_UINT16 != 0 ? 2 : 4;
      numLongFieldNames = _u32();
      longSegSize = _u32();
    }
    if (primaryFlags & TNS_JSON_FLAG_TREE_SEG_UINT32 != 0) {
      _u32(); // tree segment size
    } else {
      _u16();
    }
    _u16(); // number of tiny nodes
    fieldNames = [
      if (numShortFieldNames > 0)
        ..._fieldNames(numShortFieldNames, shortOffsetsSize, shortSegSize, 1),
      if (numLongFieldNames > 0)
        ..._fieldNames(numLongFieldNames, longOffsetsSize, longSegSize, 2),
    ];
    treeSegPos = pos;
    return _decodeNode();
  }

  List<String> _fieldNames(
      int numFields, int offsetsSize, int segSize, int hashAndLengthSize) {
    pos += numFields * hashAndLengthSize; // hash id array
    final offsetsPos = pos;
    pos += numFields * offsetsSize;
    final seg = _raw(segSize);
    final finalPos = pos;
    pos = offsetsPos;
    final names = List<String>.filled(numFields, '');
    for (var i = 0; i < numFields; i++) {
      final offset = offsetsSize == 2 ? _u16() : _u32();
      if (hashAndLengthSize == 1) {
        final len = seg[offset];
        names[i] = utf8.decode(seg.sublist(offset + 1, offset + 1 + len));
      } else {
        final len = (seg[offset] << 8) | seg[offset + 1];
        names[i] = utf8.decode(seg.sublist(offset + 2, offset + 2 + len));
      }
    }
    pos = finalPos;
    return names;
  }

  (int, bool) _numChildren(int nodeType) {
    final bits = nodeType & 0x18;
    if (bits == 0x18) return (0, true);
    if (bits == 0) return (_u8(), false);
    if (bits == 0x08) return (_u16(), false);
    return (_u32(), false);
  }

  int _offset(int nodeType) => nodeType & 0x20 != 0 ? _u32() : _u16();

  Object _decodeContainer(int nodeType) {
    final isObject = nodeType & 0x40 == 0;
    final containerOffset = pos - treeSegPos - 1;
    var (numChildren, isShared) = _numChildren(nodeType);
    int fieldIdsPos = 0, offsetsPos;
    if (isShared) {
      final offset = _offset(nodeType);
      offsetsPos = pos;
      pos = treeSegPos + offset;
      final sharedType = _u8();
      (numChildren, _) = _numChildren(sharedType);
      fieldIdsPos = pos;
    } else if (isObject) {
      fieldIdsPos = pos;
      offsetsPos = pos + fieldIdLength * numChildren;
    } else {
      offsetsPos = pos;
    }
    final map = isObject ? <String, Object?>{} : null;
    final list = isObject ? null : List<Object?>.filled(numChildren, null);
    for (var i = 0; i < numChildren; i++) {
      String? name;
      if (isObject) {
        pos = fieldIdsPos;
        final id =
            switch (fieldIdLength) { 1 => _u8(), 2 => _u16(), _ => _u32() };
        name = fieldNames[id - 1];
        fieldIdsPos = pos;
      }
      pos = offsetsPos;
      var offset = _offset(nodeType);
      if (relativeOffsets) offset += containerOffset;
      offsetsPos = pos;
      pos = treeSegPos + offset;
      final value = _decodeNode();
      if (isObject) {
        map![name!] = value;
      } else {
        list![i] = value;
      }
    }
    return map ?? list!;
  }

  Object? _decodeNode() {
    final nodeType = _u8();
    if (nodeType & 0x80 != 0) return _decodeContainer(nodeType);
    switch (nodeType) {
      case TNS_JSON_TYPE_NULL:
        return null;
      case TNS_JSON_TYPE_TRUE:
        return true;
      case TNS_JSON_TYPE_FALSE:
        return false;
      case TNS_JSON_TYPE_DATE:
      case TNS_JSON_TYPE_TIMESTAMP7:
        return decodeDate(_raw(7), 0, 7);
      case TNS_JSON_TYPE_TIMESTAMP:
        return decodeDate(_raw(11), 0, 11);
      case TNS_JSON_TYPE_TIMESTAMP_TZ:
        return decodeDate(_raw(13), 0, 13);
      case TNS_JSON_TYPE_BINARY_FLOAT:
        return decodeBinaryFloat(_raw(4), 0);
      case TNS_JSON_TYPE_BINARY_DOUBLE:
        return decodeBinaryDouble(_raw(8), 0);
      case TNS_JSON_TYPE_INTERVAL_DS:
        return decodeIntervalDS(_raw(11), 0);
      case TNS_JSON_TYPE_INTERVAL_YM:
        return decodeIntervalYM(_raw(5), 0);
      case TNS_JSON_TYPE_STRING_LENGTH_UINT8:
        return utf8.decode(_raw(_u8()));
      case TNS_JSON_TYPE_STRING_LENGTH_UINT16:
        return utf8.decode(_raw(_u16()));
      case TNS_JSON_TYPE_STRING_LENGTH_UINT32:
        return utf8.decode(_raw(_u32()));
      case TNS_JSON_TYPE_NUMBER_LENGTH_UINT8:
        final n = _u8();
        return decodeNumber(_raw(n), 0, n, false);
      case TNS_JSON_TYPE_ID:
        return Uint8List.fromList(_raw(_u8()));
      case TNS_JSON_TYPE_BINARY_LENGTH_UINT16:
        return Uint8List.fromList(_raw(_u16()));
      case TNS_JSON_TYPE_BINARY_LENGTH_UINT32:
        return Uint8List.fromList(_raw(_u32()));
      case TNS_JSON_TYPE_EXTENDED:
        final extended = _u8();
        if (extended == TNS_JSON_TYPE_VECTOR) {
          return decodeVector(Uint8List.fromList(_raw(_u32())));
        }
        throw dpyError(ERR_OSON_NODE_TYPE_NOT_SUPPORTED,
            args: {'node_type': extended});
    }
    // number with the length stored in the node type
    if (nodeType & 0xf0 == 0x20 || nodeType & 0xf0 == 0x60) {
      final n = (nodeType & 0x0f) + 1;
      return decodeNumber(_raw(n), 0, n, false);
    }
    if (nodeType & 0xf0 == 0x40 || nodeType & 0xf0 == 0x50) {
      final n = nodeType & 0x0f;
      return decodeNumber(_raw(n), 0, n, false);
    }
    // string with the length stored in the node type
    if (nodeType & 0xe0 == 0) {
      return nodeType == 0 ? '' : utf8.decode(_raw(nodeType));
    }
    throw dpyError(ERR_OSON_NODE_TYPE_NOT_SUPPORTED,
        args: {'node_type': nodeType});
  }
}

/// Growable byte buffer used to build OSON images.
class _Bytes {
  Uint8List _data = Uint8List(256);
  int length = 0;

  void _ensure(int n) {
    if (length + n <= _data.length) return;
    var size = _data.length * 2;
    while (size < length + n) {
      size *= 2;
    }
    _data = Uint8List(size)..setRange(0, length, _data);
  }

  void u8(int v) {
    _ensure(1);
    _data[length++] = v;
  }

  void u16(int v) {
    _ensure(2);
    _data[length++] = (v >> 8) & 0xff;
    _data[length++] = v & 0xff;
  }

  void u32(int v) {
    _ensure(4);
    _data[length++] = (v >>> 24) & 0xff;
    _data[length++] = (v >> 16) & 0xff;
    _data[length++] = (v >> 8) & 0xff;
    _data[length++] = v & 0xff;
  }

  void setU32(int pos, int v) {
    _data[pos] = (v >>> 24) & 0xff;
    _data[pos + 1] = (v >> 16) & 0xff;
    _data[pos + 2] = (v >> 8) & 0xff;
    _data[pos + 3] = v & 0xff;
  }

  void bytes(List<int> b) {
    _ensure(b.length);
    _data.setRange(length, length + b.length, b);
    length += b.length;
  }

  /// Reserves [n] bytes and returns their position.
  int reserve(int n) {
    _ensure(n);
    final p = length;
    length += n;
    return p;
  }

  Uint8List toBytes() => Uint8List.sublistView(_data, 0, length);
}

class _FieldName {
  _FieldName(this.name, this.bytes) {
    var h = 0x811C9DC5;
    for (final b in bytes) {
      h = ((h ^ b) * 16777619) & 0xffffffff;
    }
    hashId = h;
  }

  final String name;
  final Uint8List bytes;
  late final int hashId;
  int offset = 0;
  int fieldId = 0;

  static int compare(_FieldName a, _FieldName b) {
    var c = (a.hashId & 0xff).compareTo(b.hashId & 0xff);
    if (c != 0) return c;
    c = a.bytes.length.compareTo(b.bytes.length);
    if (c != 0) return c;
    for (var i = 0; i < a.bytes.length; i++) {
      c = a.bytes[i].compareTo(b.bytes[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}

class _FieldNamesSegment {
  final _Bytes buf = _Bytes();
  final List<_FieldName> names = [];

  void add(_FieldName name) {
    name.offset = buf.length;
    if (name.bytes.length <= 255) {
      buf.u8(name.bytes.length);
    } else {
      buf.u16(name.bytes.length);
    }
    buf.bytes(name.bytes);
    names.add(name);
  }

  void process(int fieldIdOffset) {
    names.sort(_FieldName.compare);
    for (var i = 0; i < names.length; i++) {
      names[i].fieldId = fieldIdOffset + i + 1;
    }
  }
}

class _OsonEncoder {
  _OsonEncoder(this.maxFieldNameSize);

  final int maxFieldNameSize;
  final Map<String, _FieldName> _fieldNames = {};
  _FieldNamesSegment? _shortSeg;
  _FieldNamesSegment? _longSeg;
  int _numFieldNames = 0;
  int _fieldIdSize = 1;

  void _addFieldName(String name) {
    final bytes = utf8.encode(name);
    if (bytes.length > maxFieldNameSize) {
      throw dpyError(ERR_OSON_FIELD_NAME_LIMITATION,
          args: {'max_fname_size': maxFieldNameSize});
    }
    final fieldName = _FieldName(name, bytes);
    _fieldNames[name] = fieldName;
    if (bytes.length <= 255) {
      _shortSeg!.add(fieldName);
    } else {
      (_longSeg ??= _FieldNamesSegment()).add(fieldName);
    }
  }

  void _examine(Object? value) {
    if (value is List) {
      value.forEach(_examine);
    } else if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key as String;
        if (!_fieldNames.containsKey(key)) _addFieldName(key);
        _examine(entry.value);
      }
    }
  }

  int _determineFlags(Object? value) {
    var flags = TNS_JSON_FLAG_INLINE_LEAF;
    if (value is! List && value is! Map) return flags | TNS_JSON_FLAG_IS_SCALAR;
    _shortSeg = _FieldNamesSegment();
    _examine(value);
    _shortSeg!.process(0);
    _numFieldNames += _shortSeg!.names.length;
    if (_longSeg != null) {
      _longSeg!.process(_numFieldNames);
      _numFieldNames += _longSeg!.names.length;
    }
    flags |= TNS_JSON_FLAG_HASH_ID_UINT8 | TNS_JSON_FLAG_TINY_NODES_STAT;
    if (_numFieldNames > 65535) {
      flags |= TNS_JSON_FLAG_NUM_FNAMES_UINT32;
      _fieldIdSize = 4;
    } else if (_numFieldNames > 255) {
      flags |= TNS_JSON_FLAG_NUM_FNAMES_UINT16;
      _fieldIdSize = 2;
    }
    if (_shortSeg!.buf.length > 65535) flags |= TNS_JSON_FLAG_FNAMES_SEG_UINT32;
    return flags;
  }

  void _encodeContainer(_Bytes tree, int nodeType, int numChildren) {
    nodeType |= 0x20; // offsets are uint32
    if (numChildren > 65535) {
      nodeType |= 0x10;
    } else if (numChildren > 255) {
      nodeType |= 0x08;
    }
    tree.u8(nodeType);
    if (numChildren < 256) {
      tree.u8(numChildren);
    } else if (numChildren < 65536) {
      tree.u16(numChildren);
    } else {
      tree.u32(numChildren);
    }
  }

  void _encodeNode(_Bytes tree, Object? value) {
    if (value == null) {
      tree.u8(TNS_JSON_TYPE_NULL);
    } else if (value is bool) {
      tree.u8(value ? TNS_JSON_TYPE_TRUE : TNS_JSON_TYPE_FALSE);
    } else if (value is int || value is BigInt) {
      final b = value is int ? encodeInt(value) : encodeNumber('$value');
      tree.u8(TNS_JSON_TYPE_NUMBER_LENGTH_UINT8);
      tree.u8(b.length);
      tree.bytes(b);
    } else if (value is double) {
      final a = value.abs();
      if (value.isFinite && a < 1e126 && (a >= 1e-129 || a == 0)) {
        final b = encodeNumber(value.toString());
        tree.u8(TNS_JSON_TYPE_NUMBER_LENGTH_UINT8);
        tree.u8(b.length);
        tree.bytes(b);
      } else {
        tree.u8(TNS_JSON_TYPE_BINARY_DOUBLE);
        tree.bytes(encodeBinaryDouble(value));
      }
    } else if (value is String) {
      final b = utf8.encode(value);
      if (b.length < 256) {
        tree.u8(TNS_JSON_TYPE_STRING_LENGTH_UINT8);
        tree.u8(b.length);
      } else if (b.length < 65536) {
        tree.u8(TNS_JSON_TYPE_STRING_LENGTH_UINT16);
        tree.u16(b.length);
      } else {
        tree.u8(TNS_JSON_TYPE_STRING_LENGTH_UINT32);
        tree.u32(b.length);
      }
      tree.bytes(b);
    } else if (value is DateTime) {
      if (value.millisecond == 0 && value.microsecond == 0) {
        tree.u8(TNS_JSON_TYPE_TIMESTAMP7);
        tree.bytes(encodeDate(value, 7));
      } else {
        tree.u8(TNS_JSON_TYPE_TIMESTAMP);
        tree.bytes(encodeDate(value, 11));
      }
    } else if (value is Duration) {
      tree.u8(TNS_JSON_TYPE_INTERVAL_DS);
      tree.bytes(encodeIntervalDS(value));
    } else if (isVectorValue(value)) {
      final b = encodeVector(value);
      tree.u8(TNS_JSON_TYPE_EXTENDED);
      tree.u8(TNS_JSON_TYPE_VECTOR);
      tree.u32(b.length);
      tree.bytes(b);
    } else if (value is Uint8List) {
      if (value.length < 65536) {
        tree.u8(TNS_JSON_TYPE_BINARY_LENGTH_UINT16);
        tree.u16(value.length);
      } else {
        tree.u8(TNS_JSON_TYPE_BINARY_LENGTH_UINT32);
        tree.u32(value.length);
      }
      tree.bytes(value);
    } else if (value is List) {
      _encodeContainer(tree, TNS_JSON_TYPE_ARRAY, value.length);
      var offset = tree.reserve(value.length * 4);
      for (final element in value) {
        tree.setU32(offset, tree.length);
        offset += 4;
        _encodeNode(tree, element);
      }
    } else if (value is Map) {
      _encodeContainer(tree, TNS_JSON_TYPE_OBJECT, value.length);
      var fieldIdOffset = tree.reserve(value.length * (_fieldIdSize + 4));
      var valueOffset = fieldIdOffset + value.length * _fieldIdSize;
      for (final entry in value.entries) {
        final id = _fieldNames[entry.key as String]!.fieldId;
        final d = tree._data;
        switch (_fieldIdSize) {
          case 1:
            d[fieldIdOffset] = id;
          case 2:
            d[fieldIdOffset] = id >> 8;
            d[fieldIdOffset + 1] = id & 0xff;
          default:
            tree.setU32(fieldIdOffset, id);
        }
        tree.setU32(valueOffset, tree.length);
        fieldIdOffset += _fieldIdSize;
        valueOffset += 4;
        _encodeNode(tree, entry.value);
      }
    } else {
      throw dpyError(ERR_PYTHON_TYPE_NOT_SUPPORTED,
          args: {'typ': value.runtimeType});
    }
  }

  void _writeFieldNamesSegment(_Bytes out, _FieldNamesSegment seg) {
    for (final name in seg.names) {
      if (name.bytes.length <= 255) {
        out.u8(name.hashId & 0xff);
      } else {
        out.u16(name.hashId & 0xffff);
      }
    }
    for (final name in seg.names) {
      if (seg.buf.length < 65536) {
        out.u16(name.offset);
      } else {
        out.u32(name.offset);
      }
    }
    out.bytes(seg.buf.toBytes());
  }

  Uint8List encode(Object? value) {
    var flags = _determineFlags(value);
    final tree = _Bytes();
    _encodeNode(tree, value);
    if (tree.length > 65535) flags |= TNS_JSON_FLAG_TREE_SEG_UINT32;
    final out = _Bytes()
      ..u8(TNS_JSON_MAGIC_BYTE_1)
      ..u8(TNS_JSON_MAGIC_BYTE_2)
      ..u8(TNS_JSON_MAGIC_BYTE_3)
      ..u8(_longSeg != null
          ? TNS_JSON_VERSION_MAX_FNAME_65535
          : TNS_JSON_VERSION_MAX_FNAME_255)
      ..u16(flags);
    final shortSeg = _shortSeg;
    if (shortSeg != null) {
      switch (_fieldIdSize) {
        case 1:
          out.u8(shortSeg.names.length);
        case 2:
          out.u16(shortSeg.names.length);
        default:
          out.u32(shortSeg.names.length);
      }
      if (shortSeg.buf.length < 65536) {
        out.u16(shortSeg.buf.length);
      } else {
        out.u32(shortSeg.buf.length);
      }
      final longSeg = _longSeg;
      if (longSeg != null) {
        out.u16(longSeg.buf.length < 65536
            ? TNS_JSON_FLAG_SEC_FNAMES_SEG_UINT16
            : 0);
        out.u32(longSeg.names.length);
        out.u32(longSeg.buf.length);
      }
    }
    if (tree.length < 65536) {
      out.u16(tree.length);
    } else {
      out.u32(tree.length);
    }
    if (shortSeg != null) {
      out.u16(0); // number of tiny nodes
      _writeFieldNamesSegment(out, shortSeg);
      if (_longSeg != null) _writeFieldNamesSegment(out, _longSeg!);
    }
    out.bytes(tree.toBytes());
    return out.toBytes();
  }
}
