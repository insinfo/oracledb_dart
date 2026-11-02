import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:oracledb_dart/src/crypto/hash.dart';
import 'package:oracledb_dart/src/crypto/rsa.dart';
import 'package:oracledb_dart/src/utils.dart';
import 'package:test/test.dart';

// The key and the expected signature (base64) were generated with openssl:
//   openssl dgst -sha256 -sign rsa_pkcs8.pem message | base64
void main() {
  const message = 'date: Mon, 02 Nov 2026 03:00:00 GMT\n'
      '(request-target): FREEPDB1\n'
      'host: 127.0.0.1:1521';
  final expected = File('test/fixtures/rsa_signature.txt').readAsStringSync();

  test('sha256', () {
    expect(
        toHex(Sha256.hash(Uint8List.fromList(List.generate(200, (i) => i))))
            .toLowerCase(),
        '1901da1c9f699b48f6b2636e65cbf73abf99d0441ef67f5c540a42f7051dec6f');
    expect(toHex(Sha256.hash(utf8.encode('a' * 55))).toLowerCase(),
        '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318');
    expect(toHex(Sha256.hash(const [])).toLowerCase(),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  for (final name in ['rsa_pkcs8.pem', 'rsa_pkcs1.pem']) {
    test('RSA PKCS#1 v1.5 SHA-256 signature ($name)', () {
      final key =
          RsaPrivateKey.fromPem(File('test/fixtures/$name').readAsStringSync());
      expect(key.lengthInBytes, 256);
      expect(base64.encode(key.signSha256(utf8.encode(message))), expected);
    });
  }
}
