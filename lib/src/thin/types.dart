import '../exceptions.dart';
import 'constants.dart';

/// An Oracle Database data type.
class DbType {
  const DbType._(this.num, this.name, this.oraName, this.oraTypeNum,
      {this.csfrm = 0, this.defaultSize = 0, this.bufferSizeFactor = 0});

  final int num;
  final String name;
  final String oraName;
  final int oraTypeNum;
  final int csfrm;
  final int defaultSize;
  final int bufferSizeFactor;

  static const bfile = DbType._(
      DB_TYPE_NUM_BFILE, 'DB_TYPE_BFILE', 'BFILE', ORA_TYPE_NUM_BFILE,
      bufferSizeFactor: 4000);
  static const binaryDouble = DbType._(DB_TYPE_NUM_BINARY_DOUBLE,
      'DB_TYPE_BINARY_DOUBLE', 'BINARY_DOUBLE', ORA_TYPE_NUM_BINARY_DOUBLE,
      bufferSizeFactor: ORA_TYPE_SIZE_BINARY_DOUBLE);
  static const binaryFloat = DbType._(DB_TYPE_NUM_BINARY_FLOAT,
      'DB_TYPE_BINARY_FLOAT', 'BINARY_FLOAT', ORA_TYPE_NUM_BINARY_FLOAT,
      bufferSizeFactor: ORA_TYPE_SIZE_BINARY_FLOAT);
  static const binaryInteger = DbType._(DB_TYPE_NUM_BINARY_INTEGER,
      'DB_TYPE_BINARY_INTEGER', 'BINARY_INTEGER', ORA_TYPE_NUM_BINARY_INTEGER,
      bufferSizeFactor: ORA_TYPE_SIZE_NUMBER);
  static const blob = DbType._(
      DB_TYPE_NUM_BLOB, 'DB_TYPE_BLOB', 'BLOB', ORA_TYPE_NUM_BLOB,
      bufferSizeFactor: 112);
  static const boolean = DbType._(
      DB_TYPE_NUM_BOOLEAN, 'DB_TYPE_BOOLEAN', 'BOOLEAN', ORA_TYPE_NUM_BOOLEAN,
      bufferSizeFactor: ORA_TYPE_SIZE_BOOLEAN);
  static const char = DbType._(
      DB_TYPE_NUM_CHAR, 'DB_TYPE_CHAR', 'CHAR', ORA_TYPE_NUM_CHAR,
      csfrm: CS_FORM_IMPLICIT, defaultSize: 2000, bufferSizeFactor: 4);
  static const clob = DbType._(
      DB_TYPE_NUM_CLOB, 'DB_TYPE_CLOB', 'CLOB', ORA_TYPE_NUM_CLOB,
      csfrm: CS_FORM_IMPLICIT, bufferSizeFactor: 112);
  static const cursor = DbType._(
      DB_TYPE_NUM_CURSOR, 'DB_TYPE_CURSOR', 'CURSOR', ORA_TYPE_NUM_CURSOR,
      bufferSizeFactor: 4);
  static const date = DbType._(
      DB_TYPE_NUM_DATE, 'DB_TYPE_DATE', 'DATE', ORA_TYPE_NUM_DATE,
      bufferSizeFactor: ORA_TYPE_SIZE_DATE);
  static const intervalDS = DbType._(DB_TYPE_NUM_INTERVAL_DS,
      'DB_TYPE_INTERVAL_DS', 'INTERVAL DAY TO SECOND', ORA_TYPE_NUM_INTERVAL_DS,
      bufferSizeFactor: ORA_TYPE_SIZE_INTERVAL_DS);
  static const intervalYM = DbType._(DB_TYPE_NUM_INTERVAL_YM,
      'DB_TYPE_INTERVAL_YM', 'INTERVAL YEAR TO MONTH', ORA_TYPE_NUM_INTERVAL_YM,
      bufferSizeFactor: ORA_TYPE_SIZE_INTERVAL_YM);
  static const json =
      DbType._(DB_TYPE_NUM_JSON, 'DB_TYPE_JSON', 'JSON', ORA_TYPE_NUM_JSON);
  static const long = DbType._(
      DB_TYPE_NUM_LONG_VARCHAR, 'DB_TYPE_LONG', 'LONG', ORA_TYPE_NUM_LONG,
      csfrm: CS_FORM_IMPLICIT, bufferSizeFactor: 2147483647);
  static const longNVarchar = DbType._(DB_TYPE_NUM_LONG_NVARCHAR,
      'DB_TYPE_LONG_NVARCHAR', 'LONG NVARCHAR', ORA_TYPE_NUM_LONG,
      csfrm: CS_FORM_NCHAR, bufferSizeFactor: 2147483647);
  static const longRaw = DbType._(DB_TYPE_NUM_LONG_RAW, 'DB_TYPE_LONG_RAW',
      'LONG RAW', ORA_TYPE_NUM_LONG_RAW,
      bufferSizeFactor: 2147483647);
  static const nchar = DbType._(
      DB_TYPE_NUM_NCHAR, 'DB_TYPE_NCHAR', 'NCHAR', ORA_TYPE_NUM_CHAR,
      csfrm: CS_FORM_NCHAR, defaultSize: 2000, bufferSizeFactor: 4);
  static const nclob = DbType._(
      DB_TYPE_NUM_NCLOB, 'DB_TYPE_NCLOB', 'NCLOB', ORA_TYPE_NUM_CLOB,
      csfrm: CS_FORM_NCHAR, bufferSizeFactor: 112);
  static const number = DbType._(
      DB_TYPE_NUM_NUMBER, 'DB_TYPE_NUMBER', 'NUMBER', ORA_TYPE_NUM_NUMBER,
      bufferSizeFactor: ORA_TYPE_SIZE_NUMBER);
  static const nvarchar = DbType._(DB_TYPE_NUM_NVARCHAR, 'DB_TYPE_NVARCHAR',
      'NVARCHAR2', ORA_TYPE_NUM_VARCHAR,
      csfrm: CS_FORM_NCHAR, defaultSize: 4000, bufferSizeFactor: 4);
  static const object = DbType._(
      DB_TYPE_NUM_OBJECT, 'DB_TYPE_OBJECT', 'OBJECT', ORA_TYPE_NUM_OBJECT);
  static const raw = DbType._(
      DB_TYPE_NUM_RAW, 'DB_TYPE_RAW', 'RAW', ORA_TYPE_NUM_RAW,
      defaultSize: 4000, bufferSizeFactor: 1);
  static const rowid = DbType._(
      DB_TYPE_NUM_ROWID, 'DB_TYPE_ROWID', 'ROWID', ORA_TYPE_NUM_ROWID,
      bufferSizeFactor: ORA_TYPE_SIZE_ROWID);
  static const timestamp = DbType._(DB_TYPE_NUM_TIMESTAMP, 'DB_TYPE_TIMESTAMP',
      'TIMESTAMP', ORA_TYPE_NUM_TIMESTAMP,
      bufferSizeFactor: ORA_TYPE_SIZE_TIMESTAMP);
  static const timestampLTZ = DbType._(
      DB_TYPE_NUM_TIMESTAMP_LTZ,
      'DB_TYPE_TIMESTAMP_LTZ',
      'TIMESTAMP WITH LOCAL TIME ZONE',
      ORA_TYPE_NUM_TIMESTAMP_LTZ,
      bufferSizeFactor: ORA_TYPE_SIZE_TIMESTAMP);
  static const timestampTZ = DbType._(
      DB_TYPE_NUM_TIMESTAMP_TZ,
      'DB_TYPE_TIMESTAMP_TZ',
      'TIMESTAMP WITH TIME ZONE',
      ORA_TYPE_NUM_TIMESTAMP_TZ,
      bufferSizeFactor: ORA_TYPE_SIZE_TIMESTAMP_TZ);
  static const unknown =
      DbType._(DB_TYPE_NUM_UNKNOWN, 'DB_TYPE_UNKNOWN', 'UNKNOWN', 0);
  static const urowid = DbType._(
      DB_TYPE_NUM_UROWID, 'DB_TYPE_UROWID', 'UROWID', ORA_TYPE_NUM_UROWID);
  static const varchar = DbType._(
      DB_TYPE_NUM_VARCHAR, 'DB_TYPE_VARCHAR', 'VARCHAR2', ORA_TYPE_NUM_VARCHAR,
      csfrm: CS_FORM_IMPLICIT, defaultSize: 4000, bufferSizeFactor: 4);
  static const vector = DbType._(
      DB_TYPE_NUM_VECTOR, 'DB_TYPE_VECTOR', 'VECTOR', ORA_TYPE_NUM_VECTOR);
  static const xmltype = DbType._(
      DB_TYPE_NUM_XMLTYPE, 'DB_TYPE_XMLTYPE', 'XMLTYPE', ORA_TYPE_NUM_OBJECT,
      csfrm: CS_FORM_IMPLICIT, bufferSizeFactor: 2147483647);

  static const List<DbType> all = [
    bfile, binaryDouble, binaryFloat, binaryInteger, blob, boolean, char, //
    clob, cursor, date, intervalDS, intervalYM, json, long, longNVarchar,
    longRaw, nchar, nclob, number, nvarchar, object, raw, rowid, timestamp,
    timestampLTZ, timestampTZ, urowid, varchar, vector, xmltype,
  ];

  static final Map<int, DbType> _byOraTypeAndCsfrm = () {
    final map = <int, DbType>{};
    for (final t in all) {
      if (t == xmltype) continue;
      map.putIfAbsent(t.csfrm * 256 + t.oraTypeNum, () => t);
      // LONG metadata doesn't always contain the character set form
      if (t.oraTypeNum == ORA_TYPE_NUM_LONG && t.csfrm == CS_FORM_IMPLICIT) {
        map[t.oraTypeNum] = t;
      }
    }
    return map;
  }();

  static DbType fromOraTypeAndCsfrm(int oraTypeNum, int csfrm) {
    final t = _byOraTypeAndCsfrm[csfrm * 256 + oraTypeNum];
    if (t != null) return t;
    throw dpyError(ERR_ORACLE_TYPE_NOT_SUPPORTED, args: {'num': oraTypeNum});
  }

  /// Returns the type for the given metadata, retrying with a zero character
  /// set form as some types are sent with an invalid one.
  static DbType fromMetadata(int oraTypeNum, int csfrm) =>
      _byOraTypeAndCsfrm[csfrm * 256 + oraTypeNum] ??
      fromOraTypeAndCsfrm(oraTypeNum, 0);

  bool get isLob =>
      oraTypeNum == ORA_TYPE_NUM_CLOB ||
      oraTypeNum == ORA_TYPE_NUM_BLOB ||
      oraTypeNum == ORA_TYPE_NUM_BFILE;

  @override
  String toString() => '<DbType $name>';
}

/// Metadata describing a column of a query (or a bind variable).
class ColumnMetadata {
  ColumnMetadata({
    required this.name,
    required this.dbType,
    this.precision = 0,
    this.scale = 0,
    this.maxSize = 0,
    this.bufferSize = 0,
    this.nullable = true,
    this.isJson = false,
    this.isOson = false,
    this.domainSchema,
    this.domainName,
    this.annotations,
    this.vectorDimensions = 0,
    this.vectorFormat = 0,
    this.vectorFlags = 0,
  });

  /// The name of the column.
  final String name;

  /// The type of the column as reported by the database.
  DbType dbType;
  final int precision;
  final int scale;
  int maxSize;
  int bufferSize;
  final bool nullable;
  final bool isJson;
  final bool isOson;
  final String? domainSchema;
  final String? domainName;
  final Map<String, String>? annotations;
  final int vectorDimensions;
  final int vectorFormat;
  final int vectorFlags;

  /// The display size of the column (for strings, the maximum number of
  /// characters; for numbers, an estimate based on the precision).
  int? get displaySize {
    switch (dbType.oraTypeNum) {
      case ORA_TYPE_NUM_CHAR:
      case ORA_TYPE_NUM_VARCHAR:
      case ORA_TYPE_NUM_RAW:
        return maxSize;
      case ORA_TYPE_NUM_NUMBER:
      case ORA_TYPE_NUM_BINARY_INTEGER:
        if (precision == 0) return 127;
        var size = precision;
        if (scale > 0) size++;
        if (scale > 0 && precision == scale) size++;
        return size + 1;
      case ORA_TYPE_NUM_DATE:
        return 23;
    }
    return null;
  }

  ColumnMetadata copyWith({DbType? dbType}) => ColumnMetadata(
        name: name,
        dbType: dbType ?? this.dbType,
        precision: precision,
        scale: scale,
        maxSize: maxSize,
        bufferSize: bufferSize,
        nullable: nullable,
        isJson: isJson,
        isOson: isOson,
        domainSchema: domainSchema,
        domainName: domainName,
        annotations: annotations,
        vectorDimensions: vectorDimensions,
        vectorFormat: vectorFormat,
        vectorFlags: vectorFlags,
      );

  @override
  String toString() =>
      'ColumnMetadata($name, ${dbType.name}, precision: $precision, '
      'scale: $scale, maxSize: $maxSize, nullable: $nullable)';
}
