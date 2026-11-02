import 'dart:convert';
import 'dart:typed_data';

import 'exceptions.dart';
import 'lob.dart';
import 'thin/buffer.dart';
import 'thin/codecs.dart';
import 'thin/connection_impl.dart';
import 'thin/cursor_impl.dart';
import 'thin/constants.dart';
import 'thin/messages/lob_op.dart';
import 'thin/types.dart';
import 'thin/variable.dart';

final Uint8List _extentOid =
    Uint8List.fromList(const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]);

/// An attribute of an object type.
class OracleDbObjectAttr {
  OracleDbObjectAttr(this.name, this.dbType,
      {this.objectType, this.precision = 0, this.scale = 0, this.maxSize = 0});

  final String name;
  DbType dbType;

  /// The type of the attribute when it is an object or collection.
  OracleDbObjectType? objectType;
  int precision;
  int scale;
  int maxSize;

  bool get _numberAsDouble =>
      dbType.oraTypeNum == ORA_TYPE_NUM_NUMBER &&
      !(scale == 0 || (scale == -127 && precision == 0));

  @override
  String toString() => 'OracleDbObjectAttr($name, ${dbType.name})';
}

/// An object type or collection type defined in the database. Types are
/// obtained with [OracleConnection.getType] or from the metadata of queries
/// returning objects.
class OracleDbObjectType {
  OracleDbObjectType._(this._conn,
      {this.oid, this.schema, this.packageName, this.name});

  final ThinConnImpl _conn;
  Uint8List? oid;
  String? schema;
  String? packageName;
  String? name;
  int version = 0;
  bool isXmlType = false;
  bool isRowType = false;

  /// Whether the type is a collection (VARRAY, nested table or PL/SQL
  /// associative array).
  bool isCollection = false;
  int collectionType = 0;
  int collectionFlags = 0;
  int maxNumElements = 0;

  /// The type of the elements of a collection.
  OracleDbObjectAttr? element;

  List<OracleDbObjectAttr> attributes = [];
  final Map<String, OracleDbObjectAttr> _attrsByName = {};

  /// The fully qualified name of the type.
  String get fullName =>
      [schema, packageName, name].whereType<String>().join('.');

  /// Whether the collection is a PL/SQL associative array (index-by table).
  bool get isAssociativeArray => collectionType == TNS_OBJ_PLSQL_INDEX_TABLE;

  OracleDbObjectAttr? attribute(String name) => _attrsByName[name];

  /// Creates a new object of this type. For object types, [value] may be a
  /// map of attribute values; for collections, a list of elements (or, for
  /// associative arrays, a map of indexes to elements).
  OracleDbObject newObject([Object? value]) {
    final obj = OracleDbObject._(this)
      ..toid = Uint8List.fromList([
        0x00, 0x22, TNS_OBJ_NON_NULL_OID, TNS_OBJ_HAS_EXTENT_OID, //
        ...oid!, ..._extentOid,
      ])
      ..flags = TNS_OBJ_TOP_LEVEL
      ..imageFlags = TNS_OBJ_IS_VERSION_81
      ..imageVersion = TNS_OBJ_IMAGE_VERSION;
    if (isCollection) {
      obj.imageFlags |= TNS_OBJ_IS_COLLECTION;
      if (isAssociativeArray) {
        obj._assoc = {};
      } else {
        obj._elements = [];
      }
      if (value is List) {
        for (final v in value) {
          obj.append(v);
        }
      } else if (value is Map) {
        value.forEach((k, v) => obj[k as int] = v);
      }
    } else {
      obj.imageFlags |= TNS_OBJ_NO_PREFIX_SEG;
      obj._attrs = {for (final a in attributes) a.name: null};
      if (value is Map) {
        value.forEach((k, v) => obj[k as String] = v);
      }
    }
    return obj;
  }

  void _setAttributes(List<OracleDbObjectAttr> attrs) {
    attributes = attrs;
    _attrsByName
      ..clear()
      ..addEntries(attrs.map((a) => MapEntry(a.name, a)));
  }

  @override
  String toString() => 'OracleDbObjectType($fullName)';
}

/// An instance of an object type or collection type.
class OracleDbObject {
  OracleDbObject._(this.type);

  final OracleDbObjectType type;
  Uint8List? toid;
  Uint8List? oid;
  int flags = 0;
  int imageFlags = 0;
  int imageVersion = 0;

  /// The pickled image received from the database (unpacked on first use).
  Uint8List? _packed;
  Map<String, Object?>? _attrs;
  List<Object?>? _elements;
  Map<int, Object?>? _assoc;

  static OracleDbObject fromPacked(OracleDbObjectType type, Uint8List? toid,
          Uint8List? oid, Uint8List packed) =>
      OracleDbObject._(type)
        ..toid = toid
        ..oid = oid
        ..flags = TNS_OBJ_TOP_LEVEL
        .._packed = packed;

  void _ensureUnpacked() {
    final packed = _packed;
    if (packed == null) return;
    final buf = _PickleReader(packed);
    final (flags, version) = buf.readHeader();
    imageFlags = flags;
    imageVersion = version;
    _unpackFrom(buf);
    _packed = null;
  }

  void _unpackFrom(_PickleReader buf) {
    final t = type;
    if (t.isCollection) {
      buf.skip(1); // collection flags
      final n = buf.readLength();
      if (t.isAssociativeArray) {
        final assoc = _assoc = {};
        for (var i = 0; i < n; i++) {
          final index = buf.readInt32();
          assoc[index] = _unpackValue(buf, t.element!);
        }
      } else {
        final elements = _elements = [];
        for (var i = 0; i < n; i++) {
          elements.add(_unpackValue(buf, t.element!));
        }
      }
    } else {
      _attrs = {
        for (final attr in t.attributes) attr.name: _unpackValue(buf, attr)
      };
    }
  }

  Object? _unpackValue(_PickleReader buf, OracleDbObjectAttr meta) {
    final typeNum = meta.dbType.oraTypeNum;
    if (typeNum == ORA_TYPE_NUM_CLOB ||
        typeNum == ORA_TYPE_NUM_BLOB ||
        typeNum == ORA_TYPE_NUM_BFILE) {
      final locator = buf.readBytes();
      if (locator == null) return null;
      return OracleLob.fromLocator(type._conn, meta.dbType,
          LobLocator(typeNum, meta.dbType.csfrm, locator));
    }
    if (typeNum == ORA_TYPE_NUM_OBJECT) {
      final objType = meta.objectType;
      final isCollection =
          (objType?.isCollection ?? false) || type.isCollection;
      if (buf.isAtomicNull(isCollection)) return null;
      if (objType == null || meta.dbType == DbType.xmltype) {
        return readXmlType(buf.readBytes()!);
      }
      final obj = OracleDbObject._(objType);
      if (isCollection) {
        obj._packed = buf.readBytes();
      } else {
        obj._unpackFrom(buf);
      }
      return obj;
    }
    final n = buf.readLengthOrNull();
    if (n == null) return null;
    final d = buf.data, o = buf.pos;
    buf.pos += n;
    switch (typeNum) {
      case ORA_TYPE_NUM_VARCHAR:
      case ORA_TYPE_NUM_CHAR:
      case ORA_TYPE_NUM_LONG:
        return meta.dbType.csfrm == CS_FORM_NCHAR
            ? decodeUtf16(d, o, n)
            : utf8.decode(Uint8List.sublistView(d, o, o + n),
                allowMalformed: true);
      case ORA_TYPE_NUM_RAW:
      case ORA_TYPE_NUM_LONG_RAW:
        return Uint8List.fromList(Uint8List.sublistView(d, o, o + n));
      case ORA_TYPE_NUM_NUMBER:
        return decodeNumber(d, o, n, meta._numberAsDouble);
      case ORA_TYPE_NUM_BINARY_INTEGER:
        var v = 0;
        for (var i = 0; i < n; i++) {
          v = (v << 8) | d[o + i];
        }
        return v >= 0x80000000 ? v - 0x100000000 : v;
      case ORA_TYPE_NUM_BINARY_DOUBLE:
        return decodeBinaryDouble(d, o);
      case ORA_TYPE_NUM_BINARY_FLOAT:
        return decodeBinaryFloat(d, o);
      case ORA_TYPE_NUM_BOOLEAN:
        return d[o + n - 1] == 1;
      case ORA_TYPE_NUM_DATE:
      case ORA_TYPE_NUM_TIMESTAMP:
      case ORA_TYPE_NUM_TIMESTAMP_TZ:
      case ORA_TYPE_NUM_TIMESTAMP_LTZ:
        return decodeDate(d, o, n);
      case ORA_TYPE_NUM_INTERVAL_DS:
        return decodeIntervalDS(d, o);
      case ORA_TYPE_NUM_INTERVAL_YM:
        return decodeIntervalYM(d, o);
    }
    throw dpyError(ERR_DB_TYPE_NOT_SUPPORTED, args: {'name': meta.dbType.name});
  }

  /// Returns the image to send to the database.
  Uint8List packedData() {
    final packed = _packed;
    if (packed != null) return packed;
    final buf = _PickleWriter();
    buf
      ..u8(imageFlags)
      ..u8(imageVersion)
      ..u8(TNS_LONG_LENGTH_INDICATOR)
      ..u32(0); // size (updated below)
    if (type.isCollection) {
      buf
        ..u8(1) // length of prefix segment
        ..u8(1); // prefix segment contents
    }
    _packInto(buf);
    buf.setU32(3, buf.length);
    return buf.toBytes();
  }

  void _packInto(_PickleWriter buf) {
    final t = type;
    if (t.isCollection) {
      buf.u8(t.collectionFlags);
      if (t.isAssociativeArray) {
        final keys = _assoc!.keys.toList()..sort();
        buf.writeLength(keys.length);
        for (final k in keys) {
          buf.u32(k & 0xffffffff);
          _packValue(buf, t.element!, _assoc![k]);
        }
      } else {
        buf.writeLength(_elements!.length);
        for (final v in _elements!) {
          _packValue(buf, t.element!, v);
        }
      }
    } else {
      for (final attr in t.attributes) {
        _packValue(buf, attr, _attrs![attr.name]);
      }
    }
  }

  void _packValue(_PickleWriter buf, OracleDbObjectAttr meta, Object? value) {
    final typeNum = meta.dbType.oraTypeNum;
    if (value == null) {
      final objType = meta.objectType;
      buf.u8(objType != null && !objType.isCollection
          ? TNS_OBJ_ATOMIC_NULL
          : TNS_NULL_LENGTH_INDICATOR);
      return;
    }
    switch (typeNum) {
      case ORA_TYPE_NUM_CHAR:
      case ORA_TYPE_NUM_VARCHAR:
        final s = value.toString();
        buf.writeBytes(meta.dbType.csfrm == CS_FORM_NCHAR
            ? encodeUtf16(s)
            : utf8.encode(s));
      case ORA_TYPE_NUM_NUMBER:
        buf.writeBytes(value is int
            ? encodeInt(value)
            : value is bool
                ? encodeInt(value ? 1 : 0)
                : encodeNumber(value.toString()));
      case ORA_TYPE_NUM_BINARY_INTEGER:
        buf
          ..u8(4)
          ..u32((value as int) & 0xffffffff);
      case ORA_TYPE_NUM_RAW:
        buf.writeBytes(value as List<int>);
      case ORA_TYPE_NUM_BINARY_DOUBLE:
        buf.writeBytes(encodeBinaryDouble((value as num).toDouble()));
      case ORA_TYPE_NUM_BINARY_FLOAT:
        buf.writeBytes(encodeBinaryFloat((value as num).toDouble()));
      case ORA_TYPE_NUM_BOOLEAN:
        buf
          ..u8(4)
          ..u32((value as bool) ? 1 : 0);
      case ORA_TYPE_NUM_DATE:
      case ORA_TYPE_NUM_TIMESTAMP:
      case ORA_TYPE_NUM_TIMESTAMP_TZ:
      case ORA_TYPE_NUM_TIMESTAMP_LTZ:
        var length = meta.dbType.bufferSizeFactor;
        final dt = value as DateTime;
        if (length == 11 && dt.millisecond == 0 && dt.microsecond == 0) {
          length = 7;
        }
        buf.writeBytes(Uint8List.sublistView(
            encodeDate(dt, meta.dbType.bufferSizeFactor), 0, length));
      case ORA_TYPE_NUM_INTERVAL_DS:
        buf.writeBytes(encodeIntervalDS(value as Duration));
      case ORA_TYPE_NUM_INTERVAL_YM:
        buf.writeBytes(encodeIntervalYM(value as IntervalYM));
      case ORA_TYPE_NUM_CLOB:
      case ORA_TYPE_NUM_BLOB:
        buf.writeBytes((value as OracleLob).locator.locator);
      case ORA_TYPE_NUM_OBJECT:
        final obj = value as OracleDbObject;
        if (type.isCollection || obj.type.isCollection) {
          buf.writeBytes(obj.packedData());
        } else {
          obj._ensureUnpacked();
          obj._packInto(buf);
        }
      default:
        throw dpyError(ERR_DB_TYPE_NOT_SUPPORTED,
            args: {'name': meta.dbType.name});
    }
  }

  OracleDbObjectAttr _attr(String name) {
    final attr = type.attribute(name) ?? type.attribute(name.toUpperCase());
    if (attr == null) {
      throw ArgumentError('type ${type.fullName} has no attribute $name');
    }
    return attr;
  }

  /// Gets an attribute (by name) of an object, or an element (by index) of
  /// a collection.
  Object? operator [](Object key) {
    _ensureUnpacked();
    if (key is String) return _attrs![_attr(key).name];
    return getElement(key as int);
  }

  /// Sets an attribute (by name) of an object, or an element (by index) of
  /// a collection.
  void operator []=(Object key, Object? value) {
    _ensureUnpacked();
    if (key is String) {
      _attrs![_attr(key).name] = value;
    } else {
      setElement(key as int, value);
    }
  }

  /// The values of the attributes of an object.
  Map<String, Object?> asMap() {
    _ensureUnpacked();
    if (type.isCollection) {
      return {
        for (final e in (_assoc ?? _elements!.asMap()).entries)
          '${e.key}': e.value
      };
    }
    return Map.of(_attrs!);
  }

  /// The elements of a collection, in index order.
  List<Object?> asList() {
    _ensureUnpacked();
    if (_elements != null) return List.of(_elements!);
    final keys = _assoc!.keys.toList()..sort();
    return [for (final k in keys) _assoc![k]];
  }

  /// The number of elements of a collection.
  int get length {
    _ensureUnpacked();
    return _elements?.length ?? _assoc!.length;
  }

  void append(Object? value) {
    _ensureUnpacked();
    final elements = _elements;
    if (elements != null) {
      final max = type.maxNumElements;
      if (max > 0 && elements.length >= max) {
        throw dpyError(ERR_INVALID_COLL_INDEX_SET, args: {
          'index': elements.length,
          'min_index': 0,
          'max_index': max - 1,
        });
      }
      elements.add(value);
    } else {
      final keys = _assoc!.keys;
      final next = keys.isEmpty ? 0 : keys.reduce((a, b) => a > b ? a : b) + 1;
      _assoc![next] = value;
    }
  }

  void extend(Iterable<Object?> values) => values.forEach(append);

  Object? getElement(int index) {
    _ensureUnpacked();
    final elements = _elements;
    if (elements != null) {
      if (index >= 0 && index < elements.length) return elements[index];
    } else if (_assoc!.containsKey(index)) {
      return _assoc![index];
    }
    throw dpyError(ERR_INVALID_COLL_INDEX_GET, args: {'index': index});
  }

  void setElement(int index, Object? value) {
    _ensureUnpacked();
    final elements = _elements;
    if (elements != null) {
      if (index < 0 || index >= elements.length) {
        throw dpyError(ERR_INVALID_COLL_INDEX_SET, args: {
          'index': index,
          'min_index': 0,
          'max_index': elements.isEmpty ? 0 : elements.length - 1,
        });
      }
      elements[index] = value;
    } else {
      _assoc![index] = value;
    }
  }

  bool exists(int index) {
    _ensureUnpacked();
    final elements = _elements;
    if (elements != null) return index >= 0 && index < elements.length;
    return _assoc!.containsKey(index);
  }

  void delete(int index) {
    _ensureUnpacked();
    if (_elements != null) {
      _elements!.removeAt(index);
    } else {
      _assoc!.remove(index);
    }
  }

  List<int> get _sortedIndexes {
    _ensureUnpacked();
    if (_elements != null) {
      return [for (var i = 0; i < _elements!.length; i++) i];
    }
    return _assoc!.keys.toList()..sort();
  }

  int? get firstIndex {
    final keys = _sortedIndexes;
    return keys.isEmpty ? null : keys.first;
  }

  int? get lastIndex {
    final keys = _sortedIndexes;
    return keys.isEmpty ? null : keys.last;
  }

  int? nextIndex(int index) {
    for (final k in _sortedIndexes) {
      if (k > index) return k;
    }
    return null;
  }

  int? prevIndex(int index) {
    for (final k in _sortedIndexes.reversed) {
      if (k < index) return k;
    }
    return null;
  }

  /// Removes [count] elements from the end of a collection.
  void trim(int count) {
    _ensureUnpacked();
    final elements = _elements!;
    elements.removeRange(elements.length - count, elements.length);
  }

  OracleDbObject copy() {
    _ensureUnpacked();
    final c = OracleDbObject._(type)
      ..toid = toid
      ..oid = oid
      ..flags = flags
      ..imageFlags = imageFlags
      ..imageVersion = imageVersion;
    c._attrs = _attrs == null ? null : Map.of(_attrs!);
    c._elements = _elements == null ? null : List.of(_elements!);
    c._assoc = _assoc == null ? null : Map.of(_assoc!);
    return c;
  }

  @override
  String toString() {
    _ensureUnpacked();
    return 'OracleDbObject(${type.fullName}, '
        '${type.isCollection ? asList() : _attrs})';
  }
}

/// Reads the value of an XMLType (pickled image) as a string.
Object readXmlType(Uint8List image) {
  final buf = _PickleReader(image);
  buf.readHeader();
  buf.skip(1); // XML version
  final xmlFlag = buf.readUint32();
  if (xmlFlag & TNS_XML_TYPE_FLAG_SKIP_NEXT_4 != 0) buf.skip(4);
  final rest = Uint8List.sublistView(image, buf.pos);
  if (xmlFlag & TNS_XML_TYPE_STRING != 0) {
    return utf8.decode(rest, allowMalformed: true);
  }
  throw dpyError(ERR_UNEXPECTED_XML_TYPE, args: {'flag': xmlFlag});
}

class _PickleReader {
  _PickleReader(this.data);

  final Uint8List data;
  int pos = 0;

  int u8() => data[pos++];
  void skip(int n) => pos += n;

  int readUint32() {
    final v = (data[pos] << 24) |
        (data[pos + 1] << 16) |
        (data[pos + 2] << 8) |
        data[pos + 3];
    pos += 4;
    return v;
  }

  int readInt32() {
    final v = readUint32();
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  int readLength() {
    final n = u8();
    return n == TNS_LONG_LENGTH_INDICATOR ? readUint32() : n;
  }

  /// Reads a length, returning null for a null value.
  int? readLengthOrNull() {
    final n = u8();
    if (n == 0 || n == TNS_NULL_LENGTH_INDICATOR) return null;
    return n == TNS_LONG_LENGTH_INDICATOR ? readUint32() : n;
  }

  Uint8List? readBytes() {
    final n = readLengthOrNull();
    if (n == null) return null;
    final v = Uint8List.fromList(Uint8List.sublistView(data, pos, pos + n));
    pos += n;
    return v;
  }

  bool isAtomicNull(bool isCollection) {
    final v = data[pos];
    if (v == TNS_OBJ_ATOMIC_NULL ||
        (isCollection && v == TNS_NULL_LENGTH_INDICATOR)) {
      pos++;
      return true;
    }
    return false;
  }

  (int, int) readHeader() {
    final flags = u8();
    final version = u8();
    // skip the length of the image
    if (u8() == TNS_LONG_LENGTH_INDICATOR) skip(4);
    if (flags & TNS_OBJ_IS_DEGENERATE != 0) {
      throw dpyError(ERR_FEATURE_NOT_SUPPORTED, args: {
        'feature': 'DbObject stored in a LOB',
        'driver_type': 'thick',
      });
    }
    if (flags & TNS_OBJ_NO_PREFIX_SEG == 0) skip(readLength());
    return (flags, version);
  }
}

class _PickleWriter {
  final BytesBuilder _b = BytesBuilder();
  Uint8List? _bytes;

  int get length => _b.length;

  void u8(int v) => _b.addByte(v & 0xff);

  void u32(int v) => _b.add([
        (v >>> 24) & 0xff,
        (v >>> 16) & 0xff,
        (v >>> 8) & 0xff,
        v & 0xff,
      ]);

  void writeLength(int n) {
    if (n <= TNS_OBJ_MAX_SHORT_LENGTH) {
      u8(n);
    } else {
      u8(TNS_LONG_LENGTH_INDICATOR);
      u32(n);
    }
  }

  void writeBytes(List<int> b) {
    writeLength(b.length);
    _b.add(b);
  }

  void setU32(int pos, int v) {
    _bytes = _b.takeBytes();
    _bytes![pos] = (v >>> 24) & 0xff;
    _bytes![pos + 1] = (v >>> 16) & 0xff;
    _bytes![pos + 2] = (v >>> 8) & 0xff;
    _bytes![pos + 3] = v & 0xff;
  }

  Uint8List toBytes() => _bytes ?? _b.takeBytes();
}

/// Big endian reader used for the TDS (type descriptor segment).
class _TdsReader {
  _TdsReader(this.data);

  final Uint8List data;
  int pos = 0;

  int u8() => data[pos++];
  int s8() {
    final v = u8();
    return v >= 128 ? v - 256 : v;
  }

  int u16() {
    final v = (data[pos] << 8) | data[pos + 1];
    pos += 2;
    return v;
  }

  int u32() {
    final v = (data[pos] << 24) |
        (data[pos + 1] << 16) |
        (data[pos + 2] << 8) |
        data[pos + 3];
    pos += 4;
    return v;
  }

  void skip(int n) => pos += n;
}

const String _sqlGetMetadataForName = '''
        declare
            t_Instantiable              varchar2(3);
            t_SuperTypeOwner            varchar2(128);
            t_SuperTypeName             varchar2(128);
            t_SubTypeRefCursor          sys_refcursor;
            t_Pos                       pls_integer;
        begin
            :ret_val := dbms_pickler.get_type_shape(:full_name, :oid,
                :version, :tds, t_Instantiable, t_SuperTypeOwner,
                t_SuperTypeName, :attrs_rc, t_SubTypeRefCursor);
            :package_name := null;
            if substr(:full_name, length(:full_name) - 7) = '%ROWTYPE' then
                t_Pos := instr(:full_name, '.');
                :schema := substr(:full_name, 1, t_Pos - 1);
                :name := substr(:full_name, t_Pos + 1);
            else
                begin
                    select owner, type_name
                    into :schema, :name
                    from all_types
                    where type_oid = :oid;
                exception
                when no_data_found then
                    begin
                        select owner, package_name, type_name
                        into :schema, :package_name, :name
                        from all_plsql_types
                        where type_oid = :oid;
                    exception
                    when no_data_found then
                        null;
                    end;
                end;
            end if;
        end;''';

const String _sqlGetColumns = '''
        select
            column_name,
            data_type,
            data_type_owner,
            case
                when data_type in
                        ('CHAR', 'NCHAR', 'VARCHAR2', 'NVARCHAR2', 'RAW')
                    then data_length
                else 0
            end,
            case
                when data_precision is null and data_scale is null
                    then 0
                when data_precision is null
                    then 38
                else data_precision
            end,
            case
                when data_precision is null and data_scale is null
                        and data_type = 'NUMBER'
                    then -127
                when data_scale is null
                    then 0
                else data_scale
            end
        from all_tab_cols
        where owner = :owner
          and table_name = substr(:name, 1, length(:name) - 8)
          and hidden_column != 'YES'
        order by column_id''';

/// Cache of the object types used by a connection.
class DbObjectTypeCache {
  DbObjectTypeCache(this._conn);

  final ThinConnImpl _conn;
  final Map<String, OracleDbObjectType> _byOid = {};
  final Map<String, OracleDbObjectType> _byName = {};
  final List<OracleDbObjectType> _partial = [];

  bool get hasPartialTypes => _partial.isNotEmpty;

  Future<List<List<Object?>>> _query(
      String sql, Map<String, Object?> binds) async {
    final cursor = ThinCursorImpl(_conn);
    try {
      cursor.prepare(sql);
      cursor.bind(binds);
      await cursor.execute();
      return await cursor.fetchAll();
    } finally {
      cursor.close();
    }
  }

  Future<
      (
        int,
        Uint8List?,
        int,
        Uint8List?,
        String?,
        String?,
        String?,
        List<List<Object?>>
      )> _typeShape(String fullName) async {
    final cursor = ThinCursorImpl(_conn);
    final attrsCursor = ThinCursorImpl(_conn);
    try {
      BindVar out(DbType type, [int size = 0]) =>
          BindVar.forType(type, size: size);
      final retVal = out(DbType.binaryInteger);
      final oid = out(DbType.raw, 16);
      final version = out(DbType.binaryInteger);
      final tds = out(DbType.raw, 2000);
      final schema = out(DbType.varchar, 128);
      final packageName = out(DbType.varchar, 128);
      final name = out(DbType.varchar, 128);
      final attrs = out(DbType.cursor)..values[0] = attrsCursor;
      cursor.prepare(_sqlGetMetadataForName);
      cursor.bind({
        'ret_val': retVal,
        'full_name': fullName,
        'oid': oid,
        'version': version,
        'tds': tds,
        'attrs_rc': attrs,
        'package_name': packageName,
        'schema': schema,
        'name': name,
      });
      await cursor.execute();
      final ret = (retVal.values[0] as num?)?.toInt() ?? 0;
      var rows = const <List<Object?>>[];
      if (ret == 0) {
        final rc = attrs.values[0] as ThinCursorImpl;
        rows = await rc.fetchAll();
        rc.close();
      }
      return (
        ret,
        oid.values[0] as Uint8List?,
        (version.values[0] as num?)?.toInt() ?? 0,
        tds.values[0] as Uint8List?,
        schema.values[0] as String?,
        packageName.values[0] as String?,
        name.values[0] as String?,
        rows,
      );
    } finally {
      cursor.close();
    }
  }

  static String _oidKey(Uint8List oid) =>
      oid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Returns the type for the metadata of a column or attribute, creating a
  /// partial type (populated later) if it is not known yet.
  OracleDbObjectType typeForInfo(
      Uint8List? oid, String? schema, String? packageName, String? name) {
    final fullName = [schema, packageName, name].whereType<String>().join('.');
    var type = oid != null ? _byOid[_oidKey(oid)] : _byName[fullName];
    if (type == null) {
      type = OracleDbObjectType._(_conn,
          oid: oid, schema: schema, packageName: packageName, name: name)
        ..isXmlType = schema == 'SYS' && name == 'XMLTYPE';
      if (oid != null) _byOid[_oidKey(oid)] = type;
      _byName[fullName] = type;
      _partial.add(type);
    }
    return type;
  }

  String _quotedName(OracleDbObjectType t) {
    var name = t.name!;
    var suffix = '';
    if (name.endsWith('%ROWTYPE')) {
      name = name.substring(0, name.length - 8);
      suffix = '%ROWTYPE';
    }
    if (t.packageName == null) return '"${t.schema}"."$name"$suffix';
    return '"${t.schema}"."${t.packageName}"."$name"$suffix';
  }

  /// Returns the type with the given name, looking it up in the database if
  /// it is not cached.
  Future<OracleDbObjectType> getType(String name) async {
    // unquoted identifiers are case insensitive
    if (!name.contains('"')) name = name.toUpperCase();
    final cached = _byName[name];
    if (cached != null && cached.attributes.isNotEmpty) return cached;
    final type = OracleDbObjectType._(_conn);
    await _lookup(name, type);
    _byOid[_oidKey(type.oid!)] = type;
    _byName[name] = type;
    _byName[type.fullName] = type;
    await populatePartialTypes();
    return type;
  }

  /// Populates the types discovered while processing query metadata.
  Future<void> populatePartialTypes() async {
    while (_partial.isNotEmpty) {
      final type = _partial.removeLast();
      await _lookup(_quotedName(type), type);
    }
  }

  Future<void> _lookup(String name, OracleDbObjectType type) async {
    final (ret, oid, version, tds, schema, packageName, typeName, attrRows) =
        await _typeShape(name);
    if (ret != 0) {
      throw dpyError(ERR_INVALID_OBJECT_TYPE_NAME, args: {'name': name});
    }
    type.version = version;
    if (type.oid == null) {
      type.oid = oid;
      if (oid != null) _byOid[_oidKey(oid)] = type;
    }
    if (type.schema == null) {
      type
        ..schema = schema
        ..packageName = packageName
        ..name = typeName;
      if (typeName == null) {
        throw dpyError(ERR_INVALID_OBJECT_TYPE_NAME, args: {'name': name});
      }
      type.isXmlType = schema == 'SYS' && typeName == 'XMLTYPE';
    }
    final attrs = <OracleDbObjectAttr>[];
    if (name.endsWith('%ROWTYPE')) {
      type.isRowType = true;
      final rows = await _query(
          _sqlGetColumns, {'owner': type.schema, 'name': type.name});
      for (final r in rows) {
        var dataType = r[1] as String;
        final owner = r[2] as String?;
        if (owner == null) {
          final start = dataType.indexOf('(');
          final end = dataType.indexOf(')');
          if (start > 0 && end > start) {
            dataType =
                dataType.substring(0, start) + dataType.substring(end + 1);
          }
        }
        attrs.add(_createAttr(r[0] as String, dataType, owner, null, null,
            precision: (r[4] as num).toInt(),
            scale: (r[5] as num).toInt(),
            maxSize: (r[3] as num).toInt()));
      }
      type._setAttributes(attrs);
      return;
    }
    for (final r in attrRows) {
      // version, name, number, type name, type owner, type package,
      // type oid, instantiable, super type owner, super type name
      final attrName = r[1] as String?;
      if (attrName == null) continue;
      attrs.add(_createAttr(attrName, r[3] as String, r[4] as String?,
          r[5] as String?, r[6] as Uint8List?));
    }
    type._setAttributes(attrs);
    if (tds != null) await _parseTds(type, tds);
  }

  OracleDbObjectAttr _createAttr(String name, String typeName,
      String? typeOwner, String? typePackage, Uint8List? oid,
      {int precision = 0, int scale = 0, int maxSize = 0}) {
    if (typeOwner != null) {
      final attrType = typeForInfo(oid, typeOwner, typePackage, typeName);
      if (attrType.isXmlType) return OracleDbObjectAttr(name, DbType.xmltype);
      return OracleDbObjectAttr(name, DbType.object, objectType: attrType);
    }
    switch (typeName) {
      case 'INTEGER':
      case 'SMALLINT':
        return OracleDbObjectAttr(name, DbType.number, precision: 38);
      case 'REAL':
        return OracleDbObjectAttr(name, DbType.number,
            precision: 63, scale: -127);
      case 'DOUBLE PRECISION':
      case 'FLOAT':
        return OracleDbObjectAttr(name, DbType.number,
            precision: precision != 0 ? precision : 126, scale: -127);
    }
    final dbType = DbType.fromOraName(typeName);
    final attr = OracleDbObjectAttr(name, dbType, maxSize: maxSize);
    if (dbType.oraTypeNum == ORA_TYPE_NUM_NUMBER) {
      attr
        ..precision = precision
        ..scale = scale;
    }
    return attr;
  }

  Future<void> _parseTds(OracleDbObjectType type, Uint8List tds) async {
    final buf = _TdsReader(tds);
    buf.skip(4); // end offset
    buf.skip(2); // version op code and version
    buf.skip(2); // unknown
    final numAttrs = buf.u16();
    buf.skip(1); // TDS attributes?
    buf.skip(1); // start ADT op code
    buf.skip(2); // ADT number (always zero)
    buf.skip(4); // offset to index table
    if (numAttrs == 1) {
      final pos = buf.pos;
      if (buf.u8() == TNS_OBJ_TDS_TYPE_COLL) {
        type.isCollection = true;
      } else {
        buf.pos = pos;
      }
    }
    if (type.isCollection) {
      final pos = buf.u32();
      type.maxNumElements = buf.u32();
      type.collectionType = buf.u8();
      if (type.collectionType == TNS_OBJ_PLSQL_INDEX_TABLE) {
        type.collectionFlags = TNS_OBJ_HAS_INDEXES;
      }
      buf.pos = pos;
      final element = type.element = _parseTdsAttr(buf, 'ELEMENT')!;
      if (element.dbType == DbType.clob) {
        final rows = await _query(
            type.packageName != null
                ? 'select elem_type_name from all_plsql_coll_types '
                    'where owner = :owner and package_name = :package_name '
                    'and type_name = :name'
                : 'select elem_type_name from all_coll_types '
                    'where owner = :owner and type_name = :name',
            {
              'owner': type.schema,
              if (type.packageName != null) 'package_name': type.packageName,
              'name': type.name,
            });
        if (rows.isNotEmpty && rows.first[0] == 'NCLOB') {
          element.dbType = DbType.nclob;
        }
      } else if (element.dbType == DbType.object) {
        final withPackage = type.packageName != null;
        final rows = await _query(
            withPackage
                ? 'select elem_type_owner, elem_type_package, elem_type_name '
                    'from all_plsql_coll_types where owner = :owner '
                    'and package_name = :package_name and type_name = :name'
                : 'select elem_type_owner, elem_type_name from all_coll_types '
                    'where owner = :owner and type_name = :name',
            {
              'owner': type.schema,
              if (withPackage) 'package_name': type.packageName,
              'name': type.name,
            });
        final r = rows.first;
        element.objectType = withPackage
            ? typeForInfo(
                null, r[0] as String?, r[1] as String?, r[2] as String?)
            : typeForInfo(null, r[0] as String?, null, r[1] as String?);
      }
    } else {
      for (final attr in type.attributes) {
        final meta = _parseTdsAttr(buf, attr.name);
        if (meta == null) break;
        if (meta.precision != 0 || meta.scale != 0) {
          attr
            ..precision = meta.precision
            ..scale = meta.scale;
        }
        attr.maxSize = meta.maxSize;
      }
    }
  }

  OracleDbObjectAttr? _parseTdsAttr(_TdsReader buf, String name) {
    int attrType;
    while (true) {
      attrType = buf.u8();
      if (attrType == TNS_OBJ_TDS_TYPE_EMBED_ADT_INFO) {
        buf.skip(1); // flags
      } else if (attrType != TNS_OBJ_TDS_TYPE_SUBTYPE_MARKER) {
        break;
      }
    }
    var precision = 0, scale = 0, maxSize = 0, csfrm = 0;
    int oraTypeNum;
    switch (attrType) {
      case TNS_OBJ_TDS_TYPE_NUMBER:
        oraTypeNum = ORA_TYPE_NUM_NUMBER;
        precision = buf.s8();
        scale = buf.s8();
      case TNS_OBJ_TDS_TYPE_FLOAT:
        oraTypeNum = ORA_TYPE_NUM_NUMBER;
        buf.skip(1); // precision
      case TNS_OBJ_TDS_TYPE_VARCHAR:
      case TNS_OBJ_TDS_TYPE_CHAR:
        maxSize = buf.u16();
        csfrm = buf.u8() & 0x7f;
        buf.skip(2); // character set
        oraTypeNum = attrType == TNS_OBJ_TDS_TYPE_VARCHAR
            ? ORA_TYPE_NUM_VARCHAR
            : ORA_TYPE_NUM_CHAR;
      case TNS_OBJ_TDS_TYPE_RAW:
        oraTypeNum = ORA_TYPE_NUM_RAW;
        maxSize = buf.u16();
      case TNS_OBJ_TDS_TYPE_BINARY_FLOAT:
        oraTypeNum = ORA_TYPE_NUM_BINARY_FLOAT;
      case TNS_OBJ_TDS_TYPE_BINARY_DOUBLE:
        oraTypeNum = ORA_TYPE_NUM_BINARY_DOUBLE;
      case TNS_OBJ_TDS_TYPE_DATE:
        oraTypeNum = ORA_TYPE_NUM_DATE;
      case TNS_OBJ_TDS_TYPE_TIMESTAMP:
        buf.skip(1);
        oraTypeNum = ORA_TYPE_NUM_TIMESTAMP;
      case TNS_OBJ_TDS_TYPE_TIMESTAMP_LTZ:
        buf.skip(1);
        oraTypeNum = ORA_TYPE_NUM_TIMESTAMP_LTZ;
      case TNS_OBJ_TDS_TYPE_TIMESTAMP_TZ:
        buf.skip(1);
        oraTypeNum = ORA_TYPE_NUM_TIMESTAMP_TZ;
      case TNS_OBJ_TDS_TYPE_BOOLEAN:
        oraTypeNum = ORA_TYPE_NUM_BOOLEAN;
      case TNS_OBJ_TDS_TYPE_CLOB:
        oraTypeNum = ORA_TYPE_NUM_CLOB;
        csfrm = CS_FORM_IMPLICIT;
      case TNS_OBJ_TDS_TYPE_BLOB:
        oraTypeNum = ORA_TYPE_NUM_BLOB;
      case TNS_OBJ_TDS_TYPE_OBJ:
        oraTypeNum = ORA_TYPE_NUM_OBJECT;
        buf.skip(5); // offset and code
      case TNS_OBJ_TDS_TYPE_START_EMBED_ADT:
        oraTypeNum = ORA_TYPE_NUM_OBJECT;
        while (_parseTdsAttr(buf, name) != null) {}
      case TNS_OBJ_TDS_TYPE_END_EMBED_ADT:
        return null;
      default:
        throw dpyError(ERR_TDS_TYPE_NOT_SUPPORTED, args: {'num': attrType});
    }
    return OracleDbObjectAttr(
        name, DbType.fromOraTypeAndCsfrm(oraTypeNum, csfrm),
        precision: precision, scale: scale, maxSize: maxSize);
  }
}
