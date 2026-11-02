// Conversions between the Oracle wire formats and Dart values.

import 'dart:typed_data';

import '../exceptions.dart';
import 'constants.dart';

/// Value of an INTERVAL YEAR TO MONTH column.
class IntervalYM {
  const IntervalYM(this.years, this.months);

  final int years;
  final int months;

  @override
  bool operator ==(Object other) =>
      other is IntervalYM && other.years == years && other.months == months;

  @override
  int get hashCode => Object.hash(years, months);

  @override
  String toString() => 'IntervalYM($years, $months)';
}

const List<double> _pow10 = [
  1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, //
  1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
];

const int _maxExactDoubleInt = 9007199254740992; // 2^53

/// Decodes an Oracle NUMBER. Integers are returned as [int] (or [BigInt] if
/// they do not fit in 64 bits) unless [asDouble] is set; other values are
/// returned as [double].
Object decodeNumber(Uint8List d, int offset, int length, bool asDouble) {
  var exponent = d[offset];
  final positive = exponent & 0x80 != 0;
  if (!positive) exponent = (~exponent) & 0xff;
  exponent -= 193;

  if (length == 1) {
    if (positive) return asDouble ? 0.0 : 0;
    return -1e126;
  }

  var numDigits = length - 1;
  if (!positive && d[offset + length - 1] == 102) numDigits--;

  // exponent is the power of 100 of the first mantissa digit
  final lastPower = exponent - (numDigits - 1);
  if (lastPower >= 0 && exponent < 9) {
    // integer that fits in 64 bits (at most 18 decimal digits)
    var value = 0;
    for (var i = 1; i <= numDigits; i++) {
      final b = d[offset + i];
      value = value * 100 + (positive ? b - 1 : 101 - b);
    }
    for (var i = 0; i < lastPower; i++) {
      value *= 100;
    }
    if (!positive) value = -value;
    return asDouble ? value.toDouble() : value;
  }

  if (lastPower < 0 && numDigits <= 8) {
    // fraction: compute the mantissa exactly and scale by a power of ten;
    // when both are exactly representable the division rounds correctly
    var mantissa = 0;
    for (var i = 1; i <= numDigits; i++) {
      final b = d[offset + i];
      mantissa = mantissa * 100 + (positive ? b - 1 : 101 - b);
    }
    final scale = -2 * lastPower;
    if (mantissa <= _maxExactDoubleInt && scale <= 22) {
      final v = mantissa / _pow10[scale];
      return positive ? v : -v;
    }
  }

  final text = decodeNumberAsString(d, offset, length);
  if (lastPower >= 0 && !asDouble) {
    final big = BigInt.parse(text);
    return big.isValidInt ? big.toInt() : big;
  }
  return double.parse(text);
}

/// Decodes an Oracle NUMBER to its exact decimal string representation.
String decodeNumberAsString(Uint8List d, int offset, int length) {
  var exponent = d[offset];
  final positive = exponent & 0x80 != 0;
  if (!positive) exponent = (~exponent) & 0xff;
  exponent -= 193;
  var decimalPointIndex = exponent * 2 + 2;
  if (length == 1) return positive ? '0' : '-1e126';

  var numBytes = length;
  if (!positive && d[offset + numBytes - 1] == 102) numBytes--;
  final digits = <int>[];
  for (var i = 1; i < numBytes; i++) {
    var b = d[offset + i];
    b = positive ? b - 1 : 101 - b;
    var digit = b ~/ 10;
    if (digit == 0 && digits.isEmpty) {
      decimalPointIndex--;
    } else if (digit == 10) {
      digits.add(1);
      digits.add(0);
      decimalPointIndex++;
    } else {
      digits.add(digit);
    }
    digit = b % 10;
    if (digit != 0 || i < numBytes - 1) digits.add(digit);
  }
  final out = StringBuffer();
  if (!positive) out.write('-');
  if (decimalPointIndex <= 0) {
    out.write('0.');
    for (var i = decimalPointIndex; i < 0; i++) {
      out.write('0');
    }
  }
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i == decimalPointIndex) out.write('.');
    out.writeCharCode(48 + digits[i]);
  }
  for (var i = digits.length; i < decimalPointIndex; i++) {
    out.write('0');
  }
  return out.toString();
}

/// Encodes the textual representation of a number to an Oracle NUMBER.
Uint8List encodeNumber(String value) {
  final n = value.length;
  if (n == 0) throw dpyError(ERR_NUMBER_STRING_OF_ZERO_LENGTH);
  if (n > 172) throw dpyError(ERR_NUMBER_STRING_TOO_LONG);
  final digits = Uint8List(176);
  var numDigits = 0;
  var pos = 0;
  var isNegative = false;
  if (value.codeUnitAt(0) == 45) {
    isNegative = true;
    pos++;
  }
  while (pos < n) {
    final c = value.codeUnitAt(pos);
    if (c == 46 || c == 101 || c == 69) break;
    if (c < 48 || c > 57) throw dpyError(ERR_INVALID_NUMBER);
    pos++;
    final digit = c - 48;
    if (digit == 0 && numDigits == 0) continue;
    digits[numDigits++] = digit;
  }
  var decimalPointIndex = numDigits;
  if (pos < n && value.codeUnitAt(pos) == 46) {
    pos++;
    while (pos < n) {
      final c = value.codeUnitAt(pos);
      if (c == 101 || c == 69) break;
      if (c < 48 || c > 57) throw dpyError(ERR_INVALID_NUMBER);
      pos++;
      final digit = c - 48;
      if (digit == 0 && numDigits == 0) {
        decimalPointIndex--;
        continue;
      }
      digits[numDigits++] = digit;
    }
  }
  if (pos < n &&
      (value.codeUnitAt(pos) == 101 || value.codeUnitAt(pos) == 69)) {
    pos++;
    var expNegative = false;
    if (pos < n) {
      final c = value.codeUnitAt(pos);
      if (c == 45) {
        expNegative = true;
        pos++;
      } else if (c == 43) {
        pos++;
      }
    }
    final expStart = pos;
    while (pos < n) {
      final c = value.codeUnitAt(pos);
      if (c < 48 || c > 57) throw dpyError(ERR_NUMBER_WITH_INVALID_EXPONENT);
      pos++;
    }
    if (expStart == pos) throw dpyError(ERR_NUMBER_WITH_EMPTY_EXPONENT);
    var exp = int.parse(value.substring(expStart, pos));
    if (expNegative) exp = -exp;
    decimalPointIndex += exp;
  }
  if (pos < n) throw dpyError(ERR_CONTENT_INVALID_AFTER_NUMBER);
  while (numDigits > 0 && digits[numDigits - 1] == 0) {
    numDigits--;
  }
  if (numDigits > 40 || decimalPointIndex > 126 || decimalPointIndex < -129) {
    throw dpyError(ERR_ORACLE_NUMBER_NO_REPR);
  }
  if (numDigits == 0) return Uint8List.fromList(const [128]);

  var prependZero = false;
  if (decimalPointIndex % 2 != 0) {
    prependZero = true;
    digits[numDigits++] = 0;
    decimalPointIndex++;
  }
  if (numDigits % 2 == 1) digits[numDigits++] = 0;
  final numPairs = numDigits ~/ 2;
  final appendSentinel = isNegative && numDigits < 40;
  final out = Uint8List(numPairs + 1 + (appendSentinel ? 1 : 0));
  var exponentOnWire = (decimalPointIndex ~/ 2 + 192) & 0xff;
  if (isNegative) exponentOnWire = (~exponentOnWire) & 0xff;
  out[0] = exponentOnWire;
  var digitsPos = 0;
  for (var pair = 0; pair < numPairs; pair++) {
    int digit;
    if (pair == 0 && prependZero) {
      digit = digits[digitsPos++];
    } else {
      digit = digits[digitsPos] * 10 + digits[digitsPos + 1];
      digitsPos += 2;
    }
    out[pair + 1] = isNegative ? 101 - digit : digit + 1;
  }
  if (appendSentinel) out[numPairs + 1] = 102;
  return out;
}

/// Encodes an integer directly as an Oracle NUMBER (fast path for binds).
Uint8List encodeInt(int value) {
  if (value == 0) return Uint8List.fromList(const [128]);
  // the minimum 64-bit value cannot be negated
  if (value == -9223372036854775808) return encodeNumber(value.toString());
  final negative = value < 0;
  var v = negative ? -value : value;
  // collect base-100 digits, least significant first
  final pairs = Uint8List(10);
  var numPairs = 0;
  while (v > 0) {
    pairs[numPairs++] = v % 100;
    v ~/= 100;
  }
  var exponent = numPairs - 1;
  // strip trailing zero pairs
  var start = 0;
  while (pairs[start] == 0) {
    start++;
  }
  final mantissaLen = numPairs - start;
  final appendSentinel = negative && mantissaLen * 2 < 40;
  final out = Uint8List(1 + mantissaLen + (appendSentinel ? 1 : 0));
  var exponentOnWire = (exponent + 193) & 0xff;
  if (negative) exponentOnWire = (~exponentOnWire) & 0xff;
  out[0] = exponentOnWire;
  for (var i = 0; i < mantissaLen; i++) {
    final digit = pairs[numPairs - 1 - i];
    out[i + 1] = negative ? 101 - digit : digit + 1;
  }
  if (appendSentinel) out[out.length - 1] = 102;
  return out;
}

double decodeBinaryDouble(Uint8List d, int o) {
  final b = Uint8List(8);
  if (d[o] & 0x80 != 0) {
    b[0] = d[o] & 0x7f;
    for (var i = 1; i < 8; i++) {
      b[i] = d[o + i];
    }
  } else {
    for (var i = 0; i < 8; i++) {
      b[i] = (~d[o + i]) & 0xff;
    }
  }
  return ByteData.sublistView(b).getFloat64(0);
}

double decodeBinaryFloat(Uint8List d, int o) {
  final b = Uint8List(4);
  if (d[o] & 0x80 != 0) {
    b[0] = d[o] & 0x7f;
    for (var i = 1; i < 4; i++) {
      b[i] = d[o + i];
    }
  } else {
    for (var i = 0; i < 4; i++) {
      b[i] = (~d[o + i]) & 0xff;
    }
  }
  return ByteData.sublistView(b).getFloat32(0);
}

Uint8List encodeBinaryDouble(double value) {
  final b = Uint8List(8);
  ByteData.sublistView(b).setFloat64(0, value);
  if (b[0] & 0x80 == 0) {
    b[0] |= 0x80;
  } else {
    for (var i = 0; i < 8; i++) {
      b[i] = (~b[i]) & 0xff;
    }
  }
  return b;
}

Uint8List encodeBinaryFloat(double value) {
  final b = Uint8List(4);
  ByteData.sublistView(b).setFloat32(0, value);
  if (b[0] & 0x80 == 0) {
    b[0] |= 0x80;
  } else {
    for (var i = 0; i < 4; i++) {
      b[i] = (~b[i]) & 0xff;
    }
  }
  return b;
}

/// Decodes DATE, TIMESTAMP, TIMESTAMP WITH (LOCAL) TIME ZONE values.
///
/// DATE and TIMESTAMP values carry no time zone, so they are returned as UTC
/// [DateTime] objects holding the wall-clock value (which avoids any
/// shifting due to local daylight saving rules). TIMESTAMP WITH TIME ZONE
/// values are sent in UTC and are returned as the exact UTC instant.
DateTime decodeDate(Uint8List d, int o, int length) {
  final year = (d[o] - 100) * 100 + d[o + 1] - 100;
  var micros = 0;
  if (length >= 11) {
    final ns =
        (d[o + 7] << 24) | (d[o + 8] << 16) | (d[o + 9] << 8) | d[o + 10];
    micros = ns ~/ 1000;
  }
  // for TIMESTAMP WITH TIME ZONE the bytes hold the UTC value and the time
  // zone (offset or region) follows; the UTC instant is returned
  return DateTime.utc(year, d[o + 2], d[o + 3], d[o + 4] - 1, d[o + 5] - 1,
      d[o + 6] - 1, 0, micros);
}

/// Encodes a [DateTime] using its (wall-clock) fields. [length] is 7 for
/// DATE, 11 for TIMESTAMP and 13 for TIMESTAMP WITH TIME ZONE.
Uint8List encodeDate(DateTime value, int length) {
  final out = Uint8List(length);
  if (length == 13) value = value.toUtc();
  final year = value.year;
  out[0] = year ~/ 100 + 100;
  out[1] = year % 100 + 100;
  out[2] = value.month;
  out[3] = value.day;
  out[4] = value.hour + 1;
  out[5] = value.minute + 1;
  out[6] = value.second + 1;
  if (length >= 11) {
    final ns = (value.millisecond * 1000 + value.microsecond) * 1000;
    out[7] = (ns >>> 24) & 0xff;
    out[8] = (ns >>> 16) & 0xff;
    out[9] = (ns >>> 8) & 0xff;
    out[10] = ns & 0xff;
  }
  if (length == 13) {
    out[11] = TZ_HOUR_OFFSET;
    out[12] = TZ_MINUTE_OFFSET;
  }
  return out;
}

int _uint32(Uint8List d, int o) =>
    (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

Duration decodeIntervalDS(Uint8List d, int o) {
  final days = _uint32(d, o) - TNS_DURATION_MID;
  final hours = d[o + 4] - TNS_DURATION_OFFSET;
  final minutes = d[o + 5] - TNS_DURATION_OFFSET;
  final seconds = d[o + 6] - TNS_DURATION_OFFSET;
  final fseconds = _uint32(d, o + 7) - TNS_DURATION_MID;
  return Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      microseconds: fseconds ~/ 1000);
}

Uint8List encodeIntervalDS(Duration value) {
  final out = Uint8List(11);
  final totalMicros = value.inMicroseconds;
  // mirror Python's timedelta normalisation (days may be negative while the
  // remaining fields are always positive)
  // Dart's % is always non-negative, so this is floor division
  final rem = totalMicros % Duration.microsecondsPerDay;
  final days = (totalMicros - rem) ~/ Duration.microsecondsPerDay;
  final seconds = rem ~/ Duration.microsecondsPerSecond;
  final micros = rem % Duration.microsecondsPerSecond;
  final d = (days + TNS_DURATION_MID) & 0xffffffff;
  out[0] = d >>> 24;
  out[1] = (d >>> 16) & 0xff;
  out[2] = (d >>> 8) & 0xff;
  out[3] = d & 0xff;
  out[4] = seconds ~/ 3600 + TNS_DURATION_OFFSET;
  out[5] = (seconds % 3600) ~/ 60 + TNS_DURATION_OFFSET;
  out[6] = seconds % 60 + TNS_DURATION_OFFSET;
  final f = (micros * 1000 + TNS_DURATION_MID) & 0xffffffff;
  out[7] = f >>> 24;
  out[8] = (f >>> 16) & 0xff;
  out[9] = (f >>> 8) & 0xff;
  out[10] = f & 0xff;
  return out;
}

IntervalYM decodeIntervalYM(Uint8List d, int o) => IntervalYM(
    _uint32(d, o) - TNS_DURATION_MID, d[o + 4] - TNS_DURATION_OFFSET);

Uint8List encodeIntervalYM(IntervalYM value) {
  final out = Uint8List(5);
  final y = (value.years + TNS_DURATION_MID) & 0xffffffff;
  out[0] = y >>> 24;
  out[1] = (y >>> 16) & 0xff;
  out[2] = (y >>> 8) & 0xff;
  out[3] = y & 0xff;
  out[4] = value.months + TNS_DURATION_OFFSET;
  return out;
}

const String _base64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

void _convertBase64(StringBuffer out, int value, int size) {
  final chars = List<int>.filled(size, 0);
  for (var i = 0; i < size; i++) {
    chars[size - i - 1] = _base64Alphabet.codeUnitAt(value & 0x3f);
    value >>= 6;
  }
  out.write(String.fromCharCodes(chars));
}

/// Encodes the components of a physical rowid as its string representation.
String? encodeRowid(int rba, int partitionId, int blockNum, int slotNum) {
  if (rba == 0 && partitionId == 0 && blockNum == 0 && slotNum == 0) {
    return null;
  }
  final out = StringBuffer();
  _convertBase64(out, rba, 6);
  _convertBase64(out, partitionId, 3);
  _convertBase64(out, blockNum, 6);
  _convertBase64(out, slotNum, 3);
  return out.toString();
}

/// Decodes a universal rowid (physical or logical) from its raw bytes.
String decodeUrowid(Uint8List d, int o, int length) {
  if (d[o] == 1) {
    return encodeRowid(_uint32(d, o + 1), (d[o + 5] << 8) | d[o + 6],
            _uint32(d, o + 7), (d[o + 11] << 8) | d[o + 12]) ??
        '';
  }
  // logical rowid: base64 encoding of the remaining bytes prefixed with '*'
  final out = StringBuffer('*');
  var inputLen = length - 1;
  var i = o + 1;
  while (inputLen > 0) {
    var p = d[i] >> 2;
    out.writeCharCode(_base64Alphabet.codeUnitAt(p));
    p = (d[i] & 0x3) << 4;
    if (inputLen == 1) {
      out.writeCharCode(_base64Alphabet.codeUnitAt(p));
      break;
    }
    i++;
    p |= (d[i] & 0xf0) >> 4;
    out.writeCharCode(_base64Alphabet.codeUnitAt(p));
    p = (d[i] & 0xf) << 2;
    if (inputLen == 2) {
      out.writeCharCode(_base64Alphabet.codeUnitAt(p));
      break;
    }
    i++;
    p |= (d[i] & 0xc0) >> 6;
    out.writeCharCode(_base64Alphabet.codeUnitAt(p));
    out.writeCharCode(_base64Alphabet.codeUnitAt(d[i] & 0x3f));
    i++;
    inputLen -= 3;
  }
  return out.toString();
}
