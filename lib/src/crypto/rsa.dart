// RSA PKCS#1 v1.5 signatures with SHA-256, used to sign the request headers
// sent with OCI IAM database tokens.

import 'dart:convert';
import 'dart:typed_data';

import 'hash.dart';

/// DER prefix of the DigestInfo structure for SHA-256.
const List<int> _sha256DigestInfo = [
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
  0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// An RSA private key.
class RsaPrivateKey {
  RsaPrivateKey(this.n, this.d, this.p, this.q, this.dp, this.dq, this.qinv);

  /// Parses an unencrypted private key in PEM format (PKCS#1 `RSA PRIVATE
  /// KEY` or PKCS#8 `PRIVATE KEY`). A key without the PEM armour (just the
  /// base64 data) is also accepted.
  factory RsaPrivateKey.fromPem(String pem) {
    final body = pem
        .split('\n')
        .where((line) => !line.startsWith('-----'))
        .join()
        .replaceAll(RegExp(r'\s'), '');
    var der = _DerReader(base64.decode(body));
    var seq = der.readSequence();
    final version = seq.readInteger();
    if (seq.peekTag() == 0x30) {
      // PKCS#8: version, algorithm identifier, private key (PKCS#1)
      seq.readSequence();
      der = _DerReader(seq.readOctetString());
      seq = der.readSequence();
      seq.readInteger();
    } else if (version != BigInt.zero) {
      throw const FormatException('unsupported RSA private key version');
    }
    final n = seq.readInteger();
    seq.readInteger(); // public exponent
    final d = seq.readInteger();
    final p = seq.readInteger();
    final q = seq.readInteger();
    final dp = seq.readInteger();
    final dq = seq.readInteger();
    final qinv = seq.readInteger();
    return RsaPrivateKey(n, d, p, q, dp, dq, qinv);
  }

  final BigInt n, d, p, q, dp, dq, qinv;

  int get lengthInBytes => (n.bitLength + 7) >> 3;

  /// Signs [message] with RSASSA-PKCS1-v1_5 using SHA-256.
  Uint8List signSha256(List<int> message) {
    final k = lengthInBytes;
    final digest = Sha256.hash(message);
    final t = [..._sha256DigestInfo, ...digest];
    if (k < t.length + 11) throw StateError('RSA key too short');
    final em = Uint8List(k);
    em[1] = 0x01;
    for (var i = 2; i < k - t.length - 1; i++) {
      em[i] = 0xff;
    }
    em.setRange(k - t.length, k, t);
    final m = _toBigInt(em);
    // Chinese remainder theorem
    final m1 = m.modPow(dp, p);
    final m2 = m.modPow(dq, q);
    final h = (qinv * (m1 - m2)) % p;
    final s = m2 + h * q;
    return _toBytes(s, k);
  }

  static BigInt _toBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _toBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    final mask = BigInt.from(0xff);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & mask).toInt();
      v >>= 8;
    }
    return out;
  }
}

/// Minimal DER reader for the structures of RSA private keys.
class _DerReader {
  _DerReader(this._data, [this._pos = 0, int? end])
      : _end = end ?? _data.length;

  final Uint8List _data;
  int _pos;
  final int _end;

  int peekTag() => _data[_pos];

  int _readLength() {
    var length = _data[_pos++];
    if (length & 0x80 != 0) {
      final numBytes = length & 0x7f;
      length = 0;
      for (var i = 0; i < numBytes; i++) {
        length = (length << 8) | _data[_pos++];
      }
    }
    return length;
  }

  (int, int) _readHeader(int expectedTag) {
    if (_pos >= _end || _data[_pos] != expectedTag) {
      throw FormatException('unexpected DER tag at offset $_pos');
    }
    _pos++;
    final length = _readLength();
    final start = _pos;
    _pos += length;
    return (start, length);
  }

  _DerReader readSequence() {
    final (start, length) = _readHeader(0x30);
    return _DerReader(_data, start, start + length);
  }

  BigInt readInteger() {
    final (start, length) = _readHeader(0x02);
    return RsaPrivateKey._toBigInt(
        Uint8List.sublistView(_data, start, start + length));
  }

  Uint8List readOctetString() {
    final (start, length) = _readHeader(0x04);
    return Uint8List.sublistView(_data, start, start + length);
  }
}
