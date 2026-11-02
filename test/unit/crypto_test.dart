import 'dart:convert';
import 'dart:typed_data';

import 'package:oracledb_dart/src/crypto/aes.dart';
import 'package:oracledb_dart/src/crypto/hash.dart';
import 'package:oracledb_dart/src/utils.dart';
import 'package:test/test.dart';

// Reference values computed with Python's hashlib and the openssl CLI.
void main() {
  final data = Uint8List.fromList(List.generate(200, (i) => i));

  test('md5', () {
    expect(toHex(Md5.hash(data)).toLowerCase(),
        'fb7001d34b8e82c9b579be5005d5b0a5');
  });

  test('sha1', () {
    expect(toHex(Sha1.hash(data)).toLowerCase(),
        '54d11e99127d159799dbce10f51a75e697780478');
  });

  test('sha512', () {
    expect(
        toHex(Sha512.hash(data)).toLowerCase(),
        '986058e9895e2c2ab8f9e8cbdf801db12a44842a56a91d5a4e87b1fc98b29372'
        '2c4664142e42c3c551ff898646268cd92b84ed230b8c94bed7798d4f27cd7465');
    expect(
        toHex(Sha512.hash(const [])).toLowerCase(),
        'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce'
        '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e');
    expect(
        toHex(Sha512.hash(utf8.encode('a' * 112))).toLowerCase(),
        'c01d080efd492776a1c43bd23dd99d0a2e626d481e16782e75d54c2503b5dc32'
        'bd05f0f1ba33e568b88fd2d970929b719ecbb152f58f130a407c8830604b70ca');
  });

  test('sha512 incremental updates match a single update', () {
    final h = Sha512();
    for (var i = 0; i < data.length; i += 7) {
      h.update(data, i, i + 7 > data.length ? data.length : i + 7);
    }
    expect(h.digest(), Sha512.hash(data));
  });

  test('pbkdf2-sha512', () {
    expect(
        toHex(pbkdf2Sha512(utf8.encode('password'),
                utf8.encode('salt-value-1234'), 4096, 64))
            .toLowerCase(),
        '46af05199d9c59ae2e6283ed3cbc630d4121c8599d8d7190b822ee90d0efc59e'
        '4f4b35eabe0b6623d3fd5f1bf3caa004dd147b0800df8ac3853d30172daf0a5b');
    // key longer than the block size is hashed first
    expect(
        toHex(pbkdf2Sha512(utf8.encode('x' * 150), utf8.encode('salt'), 3, 32))
            .toLowerCase(),
        '41e752602c833a120518c6799112c2d3f8890303c2354d9313e27ed1f114e113');
  });

  group('aes-cbc', () {
    final plain = utf8.encode('The quick brown fox jumps over the lazy dog!!');
    const vectors = {
      16: 'f7021c01de43c8147cd2477a7eba55b3511a06c6faeaa028d2bda69a7a80c1d1'
          'ccd149153e56dd6879c02f0a27efae65',
      24: '1b552b0889c43585651a0457afa907f0afed136a15d30d3984cd6ad447591426'
          '3aac7c9dd501394bb9ecc1303e040363',
      32: 'bce46469e2f7ab6b7ea767bd3252529a843ba24e890e567ef600c4a6e1051ffc'
          'a4a193a0b12da9a76faa86744055f3c0',
    };
    vectors.forEach((keyLen, expected) {
      test('$keyLen byte key', () {
        final key = List.generate(keyLen, (i) => i);
        final encrypted = aesCbcEncrypt(key, plain);
        expect(toHex(encrypted).toLowerCase(), expected);
        final decrypted = aesCbcDecrypt(key, encrypted);
        // the padding is not removed by decryption
        expect(decrypted.sublist(0, plain.length), plain);
        expect(decrypted.sublist(plain.length), List.filled(3, 3));
      });
    });

    test('FIPS-197 AES-128 single block', () {
      final aes = Aes(fromHex('000102030405060708090a0b0c0d0e0f'));
      final block = fromHex('00112233445566778899aabbccddeeff');
      aes.encryptBlock(block, 0);
      expect(toHex(block).toLowerCase(), '69c4e0d86a7b0430d8cdb78070b4c55a');
      aes.decryptBlock(block, 0);
      expect(toHex(block).toLowerCase(), '00112233445566778899aabbccddeeff');
    });
  });
}
