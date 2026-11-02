// General purpose helpers shared by the driver.

import 'dart:math';
import 'dart:typed_data';

final Random _random = Random.secure();

/// Returns [n] cryptographically secure random bytes.
Uint8List randomBytes(int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

const String _hexDigits = '0123456789ABCDEF';

/// Encodes the bytes as an upper case hexadecimal string.
String toHex(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out
      ..writeCharCode(_hexDigits.codeUnitAt(b >> 4))
      ..writeCharCode(_hexDigits.codeUnitAt(b & 0xf));
  }
  return out.toString();
}

/// Decodes a hexadecimal string (upper or lower case) to bytes.
Uint8List fromHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}
