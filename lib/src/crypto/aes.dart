// Pure Dart AES (FIPS-197) block cipher with 128, 192 and 256 bit keys and
// the CBC mode helpers used by the Oracle authentication protocol.

import 'dart:typed_data';

final Uint8List _sbox = _buildSbox();
final Uint8List _invSbox = _buildInvSbox();
final List<Uint32List> _te = _buildTables(false);
final List<Uint32List> _td = _buildTables(true);

int _xtime(int b) => ((b << 1) ^ ((b & 0x80) != 0 ? 0x1b : 0)) & 0xff;

int _mul(int a, int b) {
  var r = 0;
  while (b != 0) {
    if ((b & 1) != 0) r ^= a;
    a = _xtime(a);
    b >>= 1;
  }
  return r;
}

Uint8List _buildSbox() {
  final sbox = Uint8List(256);
  // generate using the multiplicative inverse in GF(2^8) and the affine
  // transform
  var p = 1, q = 1;
  do {
    p = p ^ ((p << 1) & 0xff) ^ ((p & 0x80) != 0 ? 0x1b : 0);
    q ^= q << 1;
    q ^= q << 2;
    q ^= q << 4;
    q &= 0xff;
    if ((q & 0x80) != 0) q ^= 0x09;
    final x = q ^
        ((q << 1 | q >> 7) & 0xff) ^
        ((q << 2 | q >> 6) & 0xff) ^
        ((q << 3 | q >> 5) & 0xff) ^
        ((q << 4 | q >> 4) & 0xff);
    sbox[p] = (x ^ 0x63) & 0xff;
  } while (p != 1);
  sbox[0] = 0x63;
  return sbox;
}

Uint8List _buildInvSbox() {
  final inv = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    inv[_sbox[i]] = i;
  }
  return inv;
}

List<Uint32List> _buildTables(bool inverse) {
  final t0 = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    int w;
    if (!inverse) {
      final s = _sbox[i];
      w = (_mul(s, 2) << 24) | (s << 16) | (s << 8) | _mul(s, 3);
    } else {
      final s = _invSbox[i];
      w = (_mul(s, 14) << 24) |
          (_mul(s, 9) << 16) |
          (_mul(s, 13) << 8) |
          _mul(s, 11);
    }
    t0[i] = w;
  }
  final tables = <Uint32List>[t0];
  for (var r = 1; r < 4; r++) {
    final prev = tables[r - 1];
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      final v = prev[i];
      t[i] = (v >>> 8) | (v << 24);
    }
    tables.add(t);
  }
  return tables;
}

/// AES block cipher with an expanded key schedule.
class Aes {
  Aes(List<int> key) {
    final nk = key.length ~/ 4;
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError('invalid AES key length: ${key.length}');
    }
    _rounds = nk + 6;
    final total = 4 * (_rounds + 1);
    final ek = Uint32List(total);
    for (var i = 0; i < nk; i++) {
      ek[i] = (key[4 * i] << 24) |
          (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) |
          key[4 * i + 3];
    }
    var rcon = 1;
    for (var i = nk; i < total; i++) {
      var t = ek[i - 1];
      if (i % nk == 0) {
        t = ((t << 8) | (t >>> 24)) & 0xffffffff;
        t = _subWord(t) ^ (rcon << 24);
        rcon = _xtime(rcon);
      } else if (nk > 6 && i % nk == 4) {
        t = _subWord(t);
      }
      ek[i] = ek[i - nk] ^ t;
    }
    _encKey = ek;

    // the decryption key schedule is the encryption schedule in reverse
    // round order with InvMixColumns applied to the inner round keys
    final dk = Uint32List(total);
    for (var r = 0; r <= _rounds; r++) {
      for (var c = 0; c < 4; c++) {
        var w = ek[4 * (_rounds - r) + c];
        if (r > 0 && r < _rounds) {
          w = _td[0][_sbox[w >>> 24]] ^
              _td[1][_sbox[(w >>> 16) & 0xff]] ^
              _td[2][_sbox[(w >>> 8) & 0xff]] ^
              _td[3][_sbox[w & 0xff]];
        }
        dk[4 * r + c] = w;
      }
    }
    _decKey = dk;
  }

  late final int _rounds;
  late final Uint32List _encKey;
  late final Uint32List _decKey;

  static int _subWord(int w) =>
      (_sbox[w >>> 24] << 24) |
      (_sbox[(w >>> 16) & 0xff] << 16) |
      (_sbox[(w >>> 8) & 0xff] << 8) |
      _sbox[w & 0xff];

  static int _load(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static void _store(Uint8List b, int o, int w) {
    b[o] = w >>> 24;
    b[o + 1] = (w >>> 16) & 0xff;
    b[o + 2] = (w >>> 8) & 0xff;
    b[o + 3] = w & 0xff;
  }

  /// Encrypts one 16 byte block in place.
  void encryptBlock(Uint8List b, int o) {
    final k = _encKey, t0 = _te[0], t1 = _te[1], t2 = _te[2], t3 = _te[3];
    var s0 = _load(b, o) ^ k[0];
    var s1 = _load(b, o + 4) ^ k[1];
    var s2 = _load(b, o + 8) ^ k[2];
    var s3 = _load(b, o + 12) ^ k[3];
    var ki = 4;
    for (var r = 1; r < _rounds; r++) {
      final n0 = t0[s0 >>> 24] ^
          t1[(s1 >>> 16) & 0xff] ^
          t2[(s2 >>> 8) & 0xff] ^
          t3[s3 & 0xff] ^
          k[ki];
      final n1 = t0[s1 >>> 24] ^
          t1[(s2 >>> 16) & 0xff] ^
          t2[(s3 >>> 8) & 0xff] ^
          t3[s0 & 0xff] ^
          k[ki + 1];
      final n2 = t0[s2 >>> 24] ^
          t1[(s3 >>> 16) & 0xff] ^
          t2[(s0 >>> 8) & 0xff] ^
          t3[s1 & 0xff] ^
          k[ki + 2];
      final n3 = t0[s3 >>> 24] ^
          t1[(s0 >>> 16) & 0xff] ^
          t2[(s1 >>> 8) & 0xff] ^
          t3[s2 & 0xff] ^
          k[ki + 3];
      s0 = n0;
      s1 = n1;
      s2 = n2;
      s3 = n3;
      ki += 4;
    }
    final sb = _sbox;
    _store(
        b,
        o,
        ((sb[s0 >>> 24] << 24) |
                (sb[(s1 >>> 16) & 0xff] << 16) |
                (sb[(s2 >>> 8) & 0xff] << 8) |
                sb[s3 & 0xff]) ^
            k[ki]);
    _store(
        b,
        o + 4,
        ((sb[s1 >>> 24] << 24) |
                (sb[(s2 >>> 16) & 0xff] << 16) |
                (sb[(s3 >>> 8) & 0xff] << 8) |
                sb[s0 & 0xff]) ^
            k[ki + 1]);
    _store(
        b,
        o + 8,
        ((sb[s2 >>> 24] << 24) |
                (sb[(s3 >>> 16) & 0xff] << 16) |
                (sb[(s0 >>> 8) & 0xff] << 8) |
                sb[s1 & 0xff]) ^
            k[ki + 2]);
    _store(
        b,
        o + 12,
        ((sb[s3 >>> 24] << 24) |
                (sb[(s0 >>> 16) & 0xff] << 16) |
                (sb[(s1 >>> 8) & 0xff] << 8) |
                sb[s2 & 0xff]) ^
            k[ki + 3]);
  }

  /// Decrypts one 16 byte block in place.
  void decryptBlock(Uint8List b, int o) {
    final k = _decKey, t0 = _td[0], t1 = _td[1], t2 = _td[2], t3 = _td[3];
    var s0 = _load(b, o) ^ k[0];
    var s1 = _load(b, o + 4) ^ k[1];
    var s2 = _load(b, o + 8) ^ k[2];
    var s3 = _load(b, o + 12) ^ k[3];
    var ki = 4;
    for (var r = 1; r < _rounds; r++) {
      final n0 = t0[s0 >>> 24] ^
          t1[(s3 >>> 16) & 0xff] ^
          t2[(s2 >>> 8) & 0xff] ^
          t3[s1 & 0xff] ^
          k[ki];
      final n1 = t0[s1 >>> 24] ^
          t1[(s0 >>> 16) & 0xff] ^
          t2[(s3 >>> 8) & 0xff] ^
          t3[s2 & 0xff] ^
          k[ki + 1];
      final n2 = t0[s2 >>> 24] ^
          t1[(s1 >>> 16) & 0xff] ^
          t2[(s0 >>> 8) & 0xff] ^
          t3[s3 & 0xff] ^
          k[ki + 2];
      final n3 = t0[s3 >>> 24] ^
          t1[(s2 >>> 16) & 0xff] ^
          t2[(s1 >>> 8) & 0xff] ^
          t3[s0 & 0xff] ^
          k[ki + 3];
      s0 = n0;
      s1 = n1;
      s2 = n2;
      s3 = n3;
      ki += 4;
    }
    final ib = _invSbox;
    _store(
        b,
        o,
        ((ib[s0 >>> 24] << 24) |
                (ib[(s3 >>> 16) & 0xff] << 16) |
                (ib[(s2 >>> 8) & 0xff] << 8) |
                ib[s1 & 0xff]) ^
            k[ki]);
    _store(
        b,
        o + 4,
        ((ib[s1 >>> 24] << 24) |
                (ib[(s0 >>> 16) & 0xff] << 16) |
                (ib[(s3 >>> 8) & 0xff] << 8) |
                ib[s2 & 0xff]) ^
            k[ki + 1]);
    _store(
        b,
        o + 8,
        ((ib[s2 >>> 24] << 24) |
                (ib[(s1 >>> 16) & 0xff] << 16) |
                (ib[(s0 >>> 8) & 0xff] << 8) |
                ib[s3 & 0xff]) ^
            k[ki + 2]);
    _store(
        b,
        o + 12,
        ((ib[s3 >>> 24] << 24) |
                (ib[(s2 >>> 16) & 0xff] << 16) |
                (ib[(s1 >>> 8) & 0xff] << 8) |
                ib[s0 & 0xff]) ^
            k[ki + 3]);
  }
}

/// Encrypts using AES-CBC with a zero IV. The plain text is padded with
/// PKCS#7 style padding (always at least one byte), or with zeros if [zeros]
/// is set, matching the behaviour of python-oracledb's `encrypt_cbc()`.
Uint8List aesCbcEncrypt(List<int> key, List<int> plainText,
    {bool zeros = false}) {
  final n = 16 - plainText.length % 16;
  final data = Uint8List(plainText.length + n)..setAll(0, plainText);
  if (!zeros) {
    for (var i = plainText.length; i < data.length; i++) {
      data[i] = n;
    }
  }
  final aes = Aes(key);
  for (var o = 0; o < data.length; o += 16) {
    if (o > 0) {
      for (var i = 0; i < 16; i++) {
        data[o + i] ^= data[o - 16 + i];
      }
    }
    aes.encryptBlock(data, o);
  }
  return data;
}

/// Decrypts using AES-CBC with a zero IV. No padding is removed, matching the
/// behaviour of python-oracledb's `decrypt_cbc()`.
Uint8List aesCbcDecrypt(List<int> key, List<int> cipherText) {
  if (cipherText.length % 16 != 0) {
    throw ArgumentError('cipher text is not a multiple of the block size');
  }
  final aes = Aes(key);
  final src = Uint8List.fromList(cipherText);
  final out = Uint8List.fromList(cipherText);
  for (var o = 0; o < out.length; o += 16) {
    aes.decryptBlock(out, o);
    if (o > 0) {
      for (var i = 0; i < 16; i++) {
        out[o + i] ^= src[o - 16 + i];
      }
    }
  }
  return out;
}
