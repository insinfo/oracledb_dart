// Pure Dart implementations of the message digests required by the Oracle
// authentication protocol (MD5, SHA-1, SHA-512) plus HMAC-SHA512 and PBKDF2.
//
// These rely on the 64-bit integer arithmetic of the Dart VM (native
// platforms only), which is what the driver targets since it uses dart:io.

import 'dart:typed_data';

const int _mask32 = 0xffffffff;

int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & _mask32;

/// Base class for block-oriented digests using 64 byte (MD5, SHA-1) or 128
/// byte (SHA-512) blocks.
abstract class _BlockDigest {
  _BlockDigest(this.blockSize) : _block = Uint8List(blockSize);

  final int blockSize;
  final Uint8List _block;
  int _blockLen = 0;
  int _totalLen = 0;

  void processBlock(Uint8List block, int offset);
  Uint8List finish(int totalLen, Uint8List block, int blockLen);

  void update(List<int> data, [int start = 0, int? end]) {
    end ??= data.length;
    _totalLen += end - start;
    if (_blockLen > 0) {
      while (start < end && _blockLen < blockSize) {
        _block[_blockLen++] = data[start++];
      }
      if (_blockLen < blockSize) return;
      processBlock(_block, 0);
      _blockLen = 0;
    }
    if (data is Uint8List) {
      while (end - start >= blockSize) {
        processBlock(data, start);
        start += blockSize;
      }
    } else {
      while (end - start >= blockSize) {
        _block.setRange(0, blockSize, data, start);
        processBlock(_block, 0);
        start += blockSize;
      }
    }
    while (start < end) {
      _block[_blockLen++] = data[start++];
    }
  }

  Uint8List digest() => finish(_totalLen, _block, _blockLen);
}

/// MD5 (RFC 1321). Used only for the 11g verifier combo key.
class Md5 extends _BlockDigest {
  Md5() : super(64);

  static const List<int> _s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, //
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, //
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static final List<int> _k = List<int>.generate(64, (i) {
    const table = [
      0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, //
      0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af,
      0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e,
      0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
      0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6,
      0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
      0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
      0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
      0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039,
      0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97,
      0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d,
      0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
      0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ];
    return table[i];
  });

  int _a = 0x67452301, _b = 0xefcdab89, _c = 0x98badcfe, _d = 0x10325476;
  final Uint32List _m = Uint32List(16);

  @override
  void processBlock(Uint8List block, int offset) {
    final m = _m;
    for (var i = 0; i < 16; i++) {
      final p = offset + i * 4;
      m[i] = block[p] |
          (block[p + 1] << 8) |
          (block[p + 2] << 16) |
          (block[p + 3] << 24);
    }
    var a = _a, b = _b, c = _c, d = _d;
    for (var i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) & 15;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) & 15;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) & 15;
      }
      f = (f + a + _k[i] + m[g]) & _mask32;
      a = d;
      d = c;
      c = b;
      b = (b + _rotl32(f, _s[i])) & _mask32;
    }
    _a = (_a + a) & _mask32;
    _b = (_b + b) & _mask32;
    _c = (_c + c) & _mask32;
    _d = (_d + d) & _mask32;
  }

  @override
  Uint8List finish(int totalLen, Uint8List block, int blockLen) {
    final padLen = blockLen < 56 ? 56 - blockLen : 120 - blockLen;
    final tail = Uint8List(padLen + 8);
    tail[0] = 0x80;
    final bits = totalLen * 8;
    for (var i = 0; i < 8; i++) {
      tail[padLen + i] = (bits >>> (8 * i)) & 0xff;
    }
    update(tail);
    final out = Uint8List(16);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, _a, Endian.little);
    bd.setUint32(4, _b, Endian.little);
    bd.setUint32(8, _c, Endian.little);
    bd.setUint32(12, _d, Endian.little);
    return out;
  }

  static Uint8List hash(List<int> data) => (Md5()..update(data)).digest();
}

/// SHA-1 (FIPS 180-4). Used for the 11g verifier.
class Sha1 extends _BlockDigest {
  Sha1() : super(64);

  final Uint32List _h = Uint32List.fromList(
      [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]);
  final Uint32List _w = Uint32List(80);

  @override
  void processBlock(Uint8List block, int offset) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final p = offset + i * 4;
      w[i] = (block[p] << 24) |
          (block[p + 1] << 16) |
          (block[p + 2] << 8) |
          block[p + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = _rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3], e = _h[4];
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      final t = (_rotl32(a, 5) + (f & _mask32) + e + k + w[i]) & _mask32;
      e = d;
      d = c;
      c = _rotl32(b, 30);
      b = a;
      a = t;
    }
    _h[0] += a;
    _h[1] += b;
    _h[2] += c;
    _h[3] += d;
    _h[4] += e;
  }

  @override
  Uint8List finish(int totalLen, Uint8List block, int blockLen) {
    final padLen = blockLen < 56 ? 56 - blockLen : 120 - blockLen;
    final tail = Uint8List(padLen + 8);
    tail[0] = 0x80;
    ByteData.sublistView(tail).setUint64(padLen, totalLen * 8);
    update(tail);
    final out = Uint8List(20);
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < 5; i++) {
      bd.setUint32(i * 4, _h[i]);
    }
    return out;
  }

  static Uint8List hash(List<int> data) => (Sha1()..update(data)).digest();
}

/// SHA-256 (FIPS 180-4). Used to sign OCI IAM tokens.
class Sha256 extends _BlockDigest {
  Sha256() : super(64);

  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint32List _h = Uint32List.fromList(const [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, //
    0x1f83d9ab, 0x5be0cd19,
  ]);
  final Uint32List _w = Uint32List(64);

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & _mask32;

  @override
  void processBlock(Uint8List block, int offset) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final p = offset + i * 4;
      w[i] = (block[p] << 24) |
          (block[p + 1] << 16) |
          (block[p + 2] << 8) |
          block[p + 3];
    }
    for (var i = 16; i < 64; i++) {
      final x = w[i - 15], y = w[i - 2];
      final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >>> 3);
      final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >>> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g & _mask32);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & _mask32;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & _mask32;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _mask32;
    }
    _h[0] += a;
    _h[1] += b;
    _h[2] += c;
    _h[3] += d;
    _h[4] += e;
    _h[5] += f;
    _h[6] += g;
    _h[7] += h;
  }

  @override
  Uint8List finish(int totalLen, Uint8List block, int blockLen) {
    final padLen = blockLen < 56 ? 56 - blockLen : 120 - blockLen;
    final tail = Uint8List(padLen + 8);
    tail[0] = 0x80;
    ByteData.sublistView(tail).setUint64(padLen, totalLen * 8);
    update(tail);
    final out = Uint8List(32);
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      bd.setUint32(i * 4, _h[i]);
    }
    return out;
  }

  static Uint8List hash(List<int> data) => (Sha256()..update(data)).digest();
}

/// SHA-512 (FIPS 180-4). Used for the 12c verifier and PBKDF2.
class Sha512 extends _BlockDigest {
  Sha512() : super(128) {
    _h.setAll(0, _iv);
  }

  Sha512._fromState(List<int> state, int totalLen) : super(128) {
    _h.setAll(0, state);
    _totalLen = totalLen;
  }

  static const List<int> _iv = [
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, //
    0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f,
    0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
  ];

  static const List<int> _k = [
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, //
    0xe9b5dba58189dbbc, 0x3956c25bf348b538, 0x59f111f1b605d019,
    0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242,
    0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
    0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3,
    0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65, 0x2de92c6f592b0275,
    0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f,
    0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
    0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc,
    0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6,
    0x92722c851482353b, 0xa2bfe8a14cf10364, 0xa81a664bbc423001,
    0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
    0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99,
    0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb,
    0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc,
    0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915,
    0xc67178f2e372532b, 0xca273eceea26619c, 0xd186b8c721c0c207,
    0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba,
    0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
    0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a,
    0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
  ];

  final Int64List _h = Int64List(8);
  final Int64List _w = Int64List(80);

  @override
  void processBlock(Uint8List block, int offset) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final p = offset + i * 8;
      w[i] = (block[p] << 56) |
          (block[p + 1] << 48) |
          (block[p + 2] << 40) |
          (block[p + 3] << 32) |
          (block[p + 4] << 24) |
          (block[p + 5] << 16) |
          (block[p + 6] << 8) |
          block[p + 7];
    }
    _sha512Compress(_h, w);
  }

  @override
  Uint8List finish(int totalLen, Uint8List block, int blockLen) {
    final padLen = blockLen < 112 ? 112 - blockLen : 240 - blockLen;
    final tail = Uint8List(padLen + 16);
    tail[0] = 0x80;
    ByteData.sublistView(tail).setUint64(padLen + 8, totalLen * 8);
    update(tail);
    final out = Uint8List(64);
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      bd.setInt64(i * 8, _h[i]);
    }
    return out;
  }

  Sha512 _copy() => Sha512._fromState(_h, _totalLen);

  static Uint8List hash(List<int> data) => (Sha512()..update(data)).digest();
}

/// HMAC-SHA512 with the inner and outer pad states precomputed so that
/// repeated MACs with the same key (as required by PBKDF2) are cheap.
class HmacSha512 {
  HmacSha512(List<int> key) {
    var k = key;
    if (k.length > 128) k = Sha512.hash(k);
    final ipad = Uint8List(128), opad = Uint8List(128);
    for (var i = 0; i < 128; i++) {
      final b = i < k.length ? k[i] : 0;
      ipad[i] = b ^ 0x36;
      opad[i] = b ^ 0x5c;
    }
    _inner = Sha512()..update(ipad);
    _outer = Sha512()..update(opad);
  }

  late final Sha512 _inner;
  late final Sha512 _outer;

  Uint8List mac(List<int> data) {
    final inner = _inner._copy()..update(data);
    return (_outer._copy()..update(inner.digest())).digest();
  }
}

/// SHA-512 round constants stored unboxed.
final Int64List _k512 = Int64List.fromList(Sha512._k);

@pragma('vm:prefer-inline')
int _rotr64(int x, int n) => (x >>> n) | (x << (64 - n));

/// SHA-512 compression of the 16 message words in [w] (which must have room
/// for 80 words) into [state].
void _sha512Compress(Int64List state, Int64List w) {
  final k = _k512;
  for (var i = 16; i < 80; i++) {
    final x = w[i - 15], y = w[i - 2];
    final s0 = _rotr64(x, 1) ^ _rotr64(x, 8) ^ (x >>> 7);
    final s1 = _rotr64(y, 19) ^ _rotr64(y, 61) ^ (y >>> 6);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var i = 0; i < 80; i++) {
    final s1 = _rotr64(e, 14) ^ _rotr64(e, 18) ^ _rotr64(e, 41);
    final ch = (e & f) ^ (~e & g);
    final t1 = h + s1 + ch + k[i] + w[i];
    final s0 = _rotr64(a, 28) ^ _rotr64(a, 34) ^ _rotr64(a, 39);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + s0 + maj;
  }
  state[0] += a;
  state[1] += b;
  state[2] += c;
  state[3] += d;
  state[4] += e;
  state[5] += f;
  state[6] += g;
  state[7] += h;
}

Int64List _padState(List<int> key, int pad) {
  final block = Uint8List(128);
  for (var i = 0; i < 128; i++) {
    block[i] = (i < key.length ? key[i] : 0) ^ pad;
  }
  final h = Sha512()..update(block);
  return Int64List.fromList(h._h);
}

/// PBKDF2 with HMAC-SHA512 (RFC 8018), as used by the 12c verifier.
///
/// The iterations operate directly on 64-bit words: since every message
/// after the first one is a 64 byte digest, each HMAC is exactly two
/// compressions of a single padded block starting from the precomputed
/// inner and outer pad states, with no allocations.
Uint8List pbkdf2Sha512(
    List<int> password, List<int> salt, int iterations, int keyLength) {
  final key = password.length > 128 ? Sha512.hash(password) : password;
  final innerState = _padState(key, 0x36);
  final outerState = _padState(key, 0x5c);
  final hmac = HmacSha512(password);
  final out = Uint8List(keyLength);
  final saltBlock = Uint8List(salt.length + 4)..setAll(0, salt);
  final w = Int64List(80);
  final state = Int64List(8);
  final u = Int64List(8);
  final t = Int64List(8);
  // the padding for a single block holding a 64 byte message that follows
  // the 128 byte pad block (total length 192 bytes = 1536 bits)
  const padWord = 0x8000000000000000;
  const lengthBits = 1536;
  var pos = 0;
  for (var blockNum = 1; pos < keyLength; blockNum++) {
    ByteData.sublistView(saltBlock).setUint32(salt.length, blockNum);
    final first = ByteData.sublistView(hmac.mac(saltBlock));
    for (var i = 0; i < 8; i++) {
      u[i] = t[i] = first.getInt64(i * 8);
    }
    for (var iter = 1; iter < iterations; iter++) {
      // inner hash
      state.setAll(0, innerState);
      for (var i = 0; i < 8; i++) {
        w[i] = u[i];
      }
      w[8] = padWord;
      for (var i = 9; i < 15; i++) {
        w[i] = 0;
      }
      w[15] = lengthBits;
      _sha512Compress(state, w);
      // outer hash
      for (var i = 0; i < 8; i++) {
        w[i] = state[i];
      }
      w[8] = padWord;
      for (var i = 9; i < 15; i++) {
        w[i] = 0;
      }
      w[15] = lengthBits;
      state.setAll(0, outerState);
      _sha512Compress(state, w);
      for (var i = 0; i < 8; i++) {
        u[i] = state[i];
        t[i] ^= state[i];
      }
    }
    final block = Uint8List(64);
    final bd = ByteData.sublistView(block);
    for (var i = 0; i < 8; i++) {
      bd.setInt64(i * 8, t[i]);
    }
    final n = keyLength - pos < 64 ? keyLength - pos : 64;
    out.setRange(pos, pos + n, block);
    pos += n;
  }
  return out;
}
