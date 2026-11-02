// Encoding and decoding of the VECTOR type of Oracle Database 23ai.

import 'dart:typed_data';

import '../exceptions.dart';
import 'codecs.dart';
import 'constants.dart';

/// A binary vector (each byte holds 8 dimensions). Fetched binary vectors
/// are returned as [Uint8List]; this wrapper is used to bind them, since a
/// plain [Uint8List] is bound as RAW.
class BinaryVector {
  const BinaryVector(this.bytes);

  final Uint8List bytes;

  int get numDimensions => bytes.length * 8;

  @override
  bool operator ==(Object other) =>
      other is BinaryVector &&
      other.bytes.length == bytes.length &&
      _listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}

/// A sparse vector: only the values of the dimensions listed in [indices]
/// are stored; the values are a [Float32List], [Float64List] or
/// [Int8List].
class SparseVector {
  SparseVector(this.numDimensions, List<int> indices, this.values)
      : indices = Uint32List.fromList(indices) {
    if (this.indices.length != (values as List).length) {
      throw ArgumentError('indices and values must have the same length');
    }
  }

  final int numDimensions;
  final Uint32List indices;
  final TypedData values;

  @override
  bool operator ==(Object other) =>
      other is SparseVector &&
      other.numDimensions == numDimensions &&
      _listEquals(other.indices, indices) &&
      _listEquals(other.values as List, values as List);

  @override
  int get hashCode => Object.hash(
      numDimensions, Object.hashAll(indices), Object.hashAll(values as List));

  @override
  String toString() =>
      'SparseVector($numDimensions, $indices, ${values as List})';
}

bool _listEquals(List a, List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Returns true if [value] is bound as a VECTOR.
bool isVectorValue(Object? value) =>
    value is Float32List ||
    value is Float64List ||
    value is Int8List ||
    value is BinaryVector ||
    value is SparseVector;

int _formatOf(TypedData values) {
  if (values is Float64List) return VECTOR_FORMAT_FLOAT64;
  if (values is Float32List) return VECTOR_FORMAT_FLOAT32;
  if (values is Int8List) return VECTOR_FORMAT_INT8;
  if (values is Uint8List) return VECTOR_FORMAT_BINARY;
  throw dpyError(ERR_PYTHON_TYPE_NOT_SUPPORTED,
      args: {'typ': values.runtimeType});
}

/// Encodes a vector value to the VECTOR image format.
Uint8List encodeVector(Object value) {
  var flags = TNS_VECTOR_FLAG_NORM_RESERVED;
  int format, numElements, version;
  TypedData values;
  SparseVector? sparse;
  if (value is SparseVector) {
    sparse = value;
    values = value.values;
    format = _formatOf(values);
    numElements = value.numDimensions;
    version = TNS_VECTOR_VERSION_WITH_SPARSE;
    flags |= TNS_VECTOR_FLAG_SPARSE | TNS_VECTOR_FLAG_NORM;
  } else if (value is BinaryVector) {
    values = value.bytes;
    format = VECTOR_FORMAT_BINARY;
    numElements = value.bytes.length * 8;
    version = TNS_VECTOR_VERSION_WITH_BINARY;
  } else {
    values = value as TypedData;
    format = _formatOf(values);
    numElements = (values as List).length;
    version = TNS_VECTOR_VERSION_BASE;
    flags |= TNS_VECTOR_FLAG_NORM;
  }
  final out = BytesBuilder(copy: false);
  final header = ByteData(17)
    ..setUint8(0, TNS_VECTOR_MAGIC_BYTE)
    ..setUint8(1, version)
    ..setUint16(2, flags)
    ..setUint8(4, format)
    ..setUint32(5, numElements);
  // the remaining 8 bytes are reserved for the norm
  out.add(header.buffer.asUint8List());
  if (sparse != null) {
    final idx = ByteData(2 + 4 * sparse.indices.length)
      ..setUint16(0, sparse.indices.length);
    for (var i = 0; i < sparse.indices.length; i++) {
      idx.setUint32(2 + 4 * i, sparse.indices[i]);
    }
    out.add(idx.buffer.asUint8List());
  }
  if (format == VECTOR_FORMAT_FLOAT32) {
    for (final v in values as Float32List) {
      out.add(encodeBinaryFloat(v));
    }
  } else if (format == VECTOR_FORMAT_FLOAT64) {
    for (final v in values as Float64List) {
      out.add(encodeBinaryDouble(v));
    }
  } else {
    out.add(
        values.buffer.asUint8List(values.offsetInBytes, values.lengthInBytes));
  }
  return out.takeBytes();
}

/// Decodes a VECTOR image: dense vectors are returned as [Float32List],
/// [Float64List], [Int8List] or (binary) [Uint8List]; sparse vectors as
/// [SparseVector].
Object decodeVector(Uint8List data) {
  final bd = ByteData.sublistView(data);
  if (data[0] != TNS_VECTOR_MAGIC_BYTE) {
    throw dpyError(ERR_UNEXPECTED_DATA, args: {'data': 'VECTOR header'});
  }
  final version = data[1];
  if (version > TNS_VECTOR_VERSION_WITH_SPARSE) {
    throw dpyError(ERR_VECTOR_VERSION_NOT_SUPPORTED,
        args: {'version': version});
  }
  final flags = bd.getUint16(2);
  final format = data[4];
  var numElements = bd.getUint32(5);
  var pos = 9;
  if (flags & (TNS_VECTOR_FLAG_NORM_RESERVED | TNS_VECTOR_FLAG_NORM) != 0) {
    pos += 8;
  }
  if (flags & TNS_VECTOR_FLAG_SPARSE != 0) {
    final numSparse = bd.getUint16(pos);
    pos += 2;
    final indices = Uint32List(numSparse);
    for (var i = 0; i < numSparse; i++) {
      indices[i] = bd.getUint32(pos);
      pos += 4;
    }
    final (values, _) = _decodeValues(data, pos, numSparse, format);
    return SparseVector(numElements, indices, values);
  }
  if (format == VECTOR_FORMAT_BINARY) numElements ~/= 8;
  return _decodeValues(data, pos, numElements, format).$1;
}

(TypedData, int) _decodeValues(
    Uint8List data, int pos, int numElements, int format) {
  switch (format) {
    case VECTOR_FORMAT_FLOAT32:
      final out = Float32List(numElements);
      for (var i = 0; i < numElements; i++) {
        out[i] = decodeBinaryFloat(data, pos);
        pos += 4;
      }
      return (out, pos);
    case VECTOR_FORMAT_FLOAT64:
      final out = Float64List(numElements);
      for (var i = 0; i < numElements; i++) {
        out[i] = decodeBinaryDouble(data, pos);
        pos += 8;
      }
      return (out, pos);
    case VECTOR_FORMAT_INT8:
      final out =
          Int8List.fromList(Int8List.sublistView(data, pos, pos + numElements));
      return (out, pos + numElements);
    case VECTOR_FORMAT_BINARY:
      return (
        Uint8List.fromList(data.sublist(pos, pos + numElements)),
        pos + numElements
      );
  }
  throw dpyError(ERR_VECTOR_FORMAT_NOT_SUPPORTED,
      args: {'vector_format': format});
}
