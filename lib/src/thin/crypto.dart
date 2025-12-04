import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart' as pbkdf2;
import 'package:pointycastle/key_derivators/api.dart' show Pbkdf2Parameters;
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

Uint8List pbkdf2Sha512({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) {
  if (iterations <= 0) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
  if (keyLength <= 0) {
    throw ArgumentError.value(keyLength, 'keyLength', 'must be positive');
  }
  final derivator = pbkdf2.PBKDF2KeyDerivator(
    HMac(SHA512Digest(), 128),
  )..init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(password);
}

Uint8List pbkdf2Sha1({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) {
  if (iterations <= 0) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
  if (keyLength <= 0) {
    throw ArgumentError.value(keyLength, 'keyLength', 'must be positive');
  }
  final derivator = pbkdf2.PBKDF2KeyDerivator(
    HMac(SHA1Digest(), 64),
  )..init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(password);
}

Uint8List aesCbcEncrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List plaintext,
  bool zeroPadding = false,
}) {
  final padding = zeroPadding ? _ZeroPadding() : PKCS7Padding();
  final cipher = PaddedBlockCipherImpl(padding, CBCBlockCipher(AESEngine()));
  cipher.init(
    true,
    PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, CipherParameters>(
      ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
      null,
    ),
  );
  return cipher.process(plaintext);
}

Uint8List aesCbcDecrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertext,
  bool zeroPadding = false,
}) {
  final padding = zeroPadding ? _ZeroPadding() : PKCS7Padding();
  final cipher = PaddedBlockCipherImpl(padding, CBCBlockCipher(AESEngine()));
  cipher.init(
    false,
    PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, CipherParameters>(
      ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
      null,
    ),
  );
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

Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final len = clean.length ~/ 2;
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Uint8List sha1Bytes(Uint8List data) => SHA1Digest().process(data);

Uint8List sha512Bytes(Uint8List data) => SHA512Digest().process(data);

Uint8List md5Bytes(Uint8List data) => MD5Digest().process(data);

Uint8List randomBytes(int length) {
  final rnd = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = rnd.nextInt(256);
  }
  return out;
}

class _ZeroPadding implements Padding {
  @override
  String get algorithmName => 'ZeroPadding';

  @override
  void init([CipherParameters? params]) {}

  @override
  int addPadding(Uint8List data, int offset) {
    final padCount = data.length - offset;
    for (var i = offset; i < data.length; i++) {
      data[i] = 0;
    }
    return padCount;
  }

  @override
  int padCount(Uint8List data) {
    var count = 0;
    for (var i = data.length - 1; i >= 0; i--) {
      if (data[i] == 0) {
        count++;
      } else {
        break;
      }
    }
    return count == 0 ? data.length : count;
  }

  @override
  Uint8List process(bool pad, Uint8List data) {
    if (pad) {
      final out = Uint8List.fromList(data);
      addPadding(out, data.length);
      return out;
    } else {
      final padCount = this.padCount(data);
      return Uint8List.fromList(data.sublist(0, data.length - padCount));
    }
  }
}
