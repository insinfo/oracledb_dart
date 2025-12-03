import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/paddings/padded_block_cipher.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:pointycastle/stream/pbkdf2.dart';
import 'package:pointycastle/stream/pskc_dk.dart';

/// Derive a key using PBKDF2 with HMAC-SHA512.
Uint8List pbkdf2Sha512({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) {
  final mac = HMac(SHA512Digest(), 128)..init(KeyParameter(password));
  final derivator = PBKDF2KeyDerivator(mac);
  derivator.init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(Uint8List(0));
}

/// Derive a key using PBKDF2 with HMAC-SHA1 (used in older verifiers).
Uint8List pbkdf2Sha1({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) {
  final mac = HMac(SHA1Digest(), 64)..init(KeyParameter(password));
  final derivator = PBKDF2KeyDerivator(mac);
  derivator.init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(Uint8List(0));
}

/// AES-CBC encryption with PKCS7 padding.
Uint8List aesCbcEncrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List plaintext,
}) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  cipher.init(true, PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
    ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
    null,
  ));
  return cipher.process(plaintext);
}

/// AES-CBC decryption with PKCS7 padding.
Uint8List aesCbcDecrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertext,
}) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  cipher.init(false, PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
    ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
    null,
  ));
  return cipher.process(ciphertext);
}

Uint8List concat(List<Uint8List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}
