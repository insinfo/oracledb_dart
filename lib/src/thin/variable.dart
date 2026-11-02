import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import '../lob.dart';
import 'codecs.dart';
import 'types.dart';
import 'vector.dart';

/// Internal variable used for bind and fetch values.
class BindVar {
  BindVar(this.metadata, {this.numElements = 1, this.isArray = false})
      : values = List<Object?>.filled(numElements, null, growable: true);

  /// Creates a variable for the given type, finalizing the sizes as
  /// python-oracledb does.
  factory BindVar.forType(DbType type,
      {int size = 0, int numElements = 1, bool isArray = false}) {
    final metadata = ColumnMetadata(name: '', dbType: type, maxSize: size);
    finalizeMetadata(metadata);
    return BindVar(metadata, numElements: numElements, isArray: isArray);
  }

  ColumnMetadata metadata;

  /// Metadata returned by the database for fetch variables.
  ColumnMetadata? fetchMetadata;
  int numElements;
  bool isArray;
  int numElementsInArray = 0;
  List<Object?> values;
  bool hasReturnedData = false;

  /// Set for NUMBER columns with a scale, which are always returned as
  /// doubles (mirrors the Python driver returning floats).
  bool numberAsDouble = false;

  /// Return NUMBER values as their decimal string representation.
  bool numberAsString = false;

  /// Values are JSON documents stored as text or OSON in a column that is
  /// not of the JSON type (IS JSON check constraint) and are decoded.
  bool jsonDecode = false;

  /// Values are bound as temporary LOBs (long strings or bytes bound to
  /// PL/SQL) and must be read back after the call.
  bool readLobsBack = false;

  void ensureSize(int n) {
    if (values.length < n) {
      values.addAll(List<Object?>.filled(n - values.length, null));
    }
    if (numElements < n) numElements = n;
  }
}

/// Sets the buffer size and maximum size of the metadata based on its type.
void finalizeMetadata(ColumnMetadata m) {
  final t = m.dbType;
  if (t.defaultSize == 0) {
    m.maxSize = 0;
    m.bufferSize = t.bufferSizeFactor;
  } else {
    if (m.maxSize == 0) m.maxSize = t.defaultSize;
    m.bufferSize = m.maxSize * t.bufferSizeFactor;
  }
}

/// Determines the database type and size required to bind [value].
ColumnMetadata metadataFromValue(
    Object? value, bool supportsBool, bool isPlsql) {
  DbType type;
  var maxSize = 0;
  if (value == null) {
    type = DbType.varchar;
    maxSize = 1;
  } else if (value is bool) {
    type = supportsBool || isPlsql ? DbType.boolean : DbType.binaryInteger;
  } else if (value is String) {
    type = DbType.varchar;
    maxSize = _utf8Length(value);
  } else if (isVectorValue(value)) {
    type = DbType.vector;
  } else if (value is Uint8List) {
    type = DbType.raw;
    maxSize = value.length;
  } else if (value is Map || value is List) {
    type = DbType.json;
  } else if (value is double) {
    // values that cannot be represented as an Oracle NUMBER are bound as
    // BINARY_DOUBLE instead
    final a = value.abs();
    type = value.isFinite && a < 1e126 && (a >= 1e-129 || a == 0)
        ? DbType.number
        : DbType.binaryDouble;
  } else if (value is int || value is BigInt) {
    type = DbType.number;
  } else if (value is DateTime) {
    type = value.millisecond != 0 || value.microsecond != 0
        ? DbType.timestamp
        : DbType.date;
  } else if (value is Duration) {
    type = DbType.intervalDS;
  } else if (value is IntervalYM) {
    type = DbType.intervalYM;
  } else if (value is OracleLob) {
    type = value.type;
  } else {
    throw dpyError(ERR_PYTHON_VALUE_NOT_SUPPORTED,
        args: {'type_name': value.runtimeType});
  }
  final m = ColumnMetadata(name: '', dbType: type, maxSize: maxSize);
  return m;
}

int _utf8Length(String s) {
  var n = s.length;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x80) {
      // non-ASCII content: compute the exact encoded length
      return utf8.encode(s).length;
    }
  }
  return n;
}

/// Merges the metadata required for another value bound in the same
/// position (used by executeMany).
void mergeMetadata(ColumnMetadata target, ColumnMetadata other, Object? value) {
  if (value == null) return;
  if (target.dbType != other.dbType) {
    // nulls are bound as VARCHAR; adopt the type of the first non-null value
    if (target.dbType == DbType.varchar &&
        target.maxSize <= 1 &&
        target.bufferSize == 0) {
      target.dbType = other.dbType;
      target.maxSize = other.maxSize;
      return;
    }
    if (target.dbType == DbType.json || other.dbType == DbType.json) {
      // scalar values are valid JSON documents as well
      target.dbType = DbType.json;
      target.maxSize = 0;
      return;
    }
    if ((target.dbType == DbType.date && other.dbType == DbType.timestamp) ||
        (target.dbType == DbType.timestamp && other.dbType == DbType.date)) {
      target.dbType = DbType.timestamp;
      return;
    }
    throw dpyError(ERR_MIXED_ELEMENT_TYPES, args: {'element': value});
  }
  if (other.maxSize > target.maxSize) target.maxSize = other.maxSize;
}
