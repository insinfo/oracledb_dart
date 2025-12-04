import 'dart:convert';
import 'dart:typed_data';

import '../lib/src/thin/crypto.dart';

void main() {
  final password = utf8.encode('dart');
  final verifierData =
      Uint8List.fromList(hexToBytes('FC7FA8D9C4A198F9A02D34EFDCEEB400'));
  final salt = Uint8List.fromList(
      verifierData + utf8.encode('AUTH_PBKDF2_SPEEDY_KEY'));
  final passwordKey = pbkdf2Sha512(
    password: Uint8List.fromList(password),
    salt: salt,
    iterations: 4096,
    keyLength: 64,
  );
  final hInput = Uint8List.fromList(passwordKey + verifierData);
  final passwordHash = sha512Bytes(hInput).sublist(0, 32);
  print('passwordKey=${bytesToHex(passwordKey)}');
  print('passwordHash=${bytesToHex(passwordHash)}');

  final encodedServerKey =
      hexToBytes('D32579B9EE01CAE0515576E3337FDB0977430216ECFF75C0497E0CBA7CEB5D37');
  final sessionKeyPartA = aesCbcDecrypt(
    key: passwordHash,
    iv: Uint8List(16),
    ciphertext: encodedServerKey,
    zeroPadding: false,
    removePadding: false,
  );
  print('sessionKeyPartA=${bytesToHex(sessionKeyPartA)}');
}
