import 'dart:typed_data';

import 'package:oracledb_dart/src/thin/oson.dart';
import 'package:oracledb_dart/src/thin/vector.dart';
import 'package:test/test.dart';

void main() {
  group('OSON', () {
    void roundTrip(Object? value) =>
        expect(decodeOson(encodeOson(value, maxFieldNameSize: 65535)), value,
            reason: '$value');

    test('scalars', () {
      for (final v in [
        null,
        true,
        false,
        0,
        42,
        -7,
        3.25,
        'text',
        '',
        'é' * 300,
        'x' * 70000,
        12345678901234567,
        DateTime.utc(2024, 1, 2, 3, 4, 5),
        DateTime.utc(2024, 1, 2, 3, 4, 5, 6),
        const Duration(hours: 5),
      ]) {
        roundTrip(v);
      }
      expect(decodeOson(encodeOson(double.infinity)), double.infinity);
    });

    test('containers', () {
      roundTrip({
        'name': 'Ada',
        'age': 36,
        'tags': ['a', 'b', null, 1.5],
        'nested': {
          'deep': {'x': true, 'y': []},
          'empty': {},
        },
      });
      roundTrip([
        for (var i = 0; i < 300; i++) {'k$i': i}
      ]);
      roundTrip({for (var i = 0; i < 70000; i++) 'field$i': i});
      // field names longer than 255 bytes require Oracle Database 23ai
      roundTrip({'f' * 300: 'long field name', 'short': 1});
      expect(() => encodeOson({'f' * 300: 1}), throwsA(anything));
    });

    test('binary values and vectors', () {
      final decoded = decodeOson(encodeOson({
        'bytes': Uint8List.fromList([1, 2, 3]),
        'vector': Float32List.fromList([1.5, -2.5]),
      })) as Map;
      expect(decoded['bytes'], Uint8List.fromList([1, 2, 3]));
      expect(decoded['vector'], Float32List.fromList([1.5, -2.5]));
    });
  });

  group('VECTOR', () {
    test('dense vectors', () {
      for (final v in [
        Float32List.fromList([1.5, -2.25, 0]),
        Float64List.fromList([1e300, -1e-300]),
        Int8List.fromList([-128, 0, 127]),
      ]) {
        expect(decodeVector(encodeVector(v)), v);
      }
      expect(
          decodeVector(
              encodeVector(BinaryVector(Uint8List.fromList([1, 255])))),
          Uint8List.fromList([1, 255]));
    });

    test('sparse vectors', () {
      final v = SparseVector(100, [1, 50, 99], Float64List.fromList([1, 2, 3]));
      expect(decodeVector(encodeVector(v)), v);
    });
  });
}
