import 'dart:math';
import 'dart:typed_data';

import 'package:oracledb_dart/src/thin/codecs.dart';
import 'package:oracledb_dart/src/thin/statement.dart';
import 'package:oracledb_dart/src/utils.dart';
import 'package:test/test.dart';

Object _decode(Uint8List b, {bool asDouble = false}) =>
    decodeNumber(b, 0, b.length, asDouble);

void main() {
  group('NUMBER', () {
    test('known encodings', () {
      expect(toHex(encodeNumber('0')), '80');
      expect(toHex(encodeNumber('100')), 'C202');
      expect(toHex(encodeNumber('-5')), '3E6066');
      expect(toHex(encodeNumber('0.5')), 'C033');
      expect(toHex(encodeNumber('1234.5')), 'C20D2333');
      expect(toHex(encodeInt(100)), 'C202');
      expect(toHex(encodeInt(-5)), '3E6066');
    });

    test('encodeInt matches encodeNumber', () {
      final random = Random(42);
      final values = <int>[
        0,
        1,
        -1,
        9,
        10,
        99,
        100,
        101,
        1000000,
        -1000000,
        123456789012345678,
        -123456789012345678,
        9223372036854775807,
        -9223372036854775808,
        for (var i = 0; i < 2000; i++)
          (random.nextInt(1 << 32) * random.nextInt(1 << 31)) *
              (random.nextBool() ? 1 : -1),
      ];
      for (final v in values) {
        expect(encodeInt(v), encodeNumber('$v'), reason: '$v');
      }
    });

    test('integers round trip', () {
      final random = Random(7);
      for (var i = 0; i < 2000; i++) {
        final v = random.nextInt(1 << 32) * random.nextInt(1 << 20) - (1 << 40);
        expect(_decode(encodeInt(v)), v);
      }
      expect(_decode(encodeInt(9223372036854775807)), 9223372036854775807);
      expect(_decode(encodeNumber('123456789012345678901234567890')),
          BigInt.parse('123456789012345678901234567890'));
    });

    test('decimals round trip', () {
      final random = Random(9);
      for (var i = 0; i < 2000; i++) {
        final v =
            (random.nextDouble() - 0.5) * pow(10, random.nextInt(30) - 15);
        final decoded = _decode(encodeNumber(v.toString())) as num;
        expect(decoded.toDouble(), v, reason: '$v');
      }
      for (final s in [
        '0.1',
        '-0.001',
        '3.14159265358979',
        '1e-100',
        '12345.678'
      ]) {
        expect(_decode(encodeNumber(s)), double.parse(s), reason: s);
      }
      // integral values are returned as integers (BigInt when too large)
      expect(
          _decode(encodeNumber('-1.5e125')), BigInt.parse('-15${'0' * 124}'));
    });

    test('exact string decoding', () {
      for (final s in [
        '0',
        '1',
        '-1',
        '0.001',
        '-12.5',
        '1000000',
        '123456789012345678901234567890.123456789'
      ]) {
        final b = encodeNumber(s);
        expect(decodeNumberAsString(b, 0, b.length), s);
      }
    });

    test('integers can be returned as doubles', () {
      expect(_decode(encodeInt(42), asDouble: true), 42.0);
    });
  });

  test('BINARY_DOUBLE and BINARY_FLOAT', () {
    for (final v in [0.0, -0.0, 1.5, -1.5, 1e300, -1e-300, double.infinity]) {
      expect(decodeBinaryDouble(encodeBinaryDouble(v), 0), v);
    }
    expect(decodeBinaryFloat(encodeBinaryFloat(3.5), 0), 3.5);
    expect(decodeBinaryFloat(encodeBinaryFloat(-2.25), 0), -2.25);
  });

  test('dates', () {
    final dt = DateTime.utc(2024, 2, 29, 23, 59, 58, 123, 456);
    final ts = encodeDate(dt, 11);
    expect(decodeDate(ts, 0, 11), dt);
    final d = encodeDate(dt, 7);
    expect(decodeDate(d, 0, 7), DateTime.utc(2024, 2, 29, 23, 59, 58));
    expect(decodeDate(encodeDate(DateTime.utc(1, 1, 1), 7), 0, 7),
        DateTime.utc(1, 1, 1));
  });

  test('intervals', () {
    for (final v in [
      const Duration(days: 5, hours: 3, minutes: 2, seconds: 1),
      const Duration(microseconds: 123456),
      -const Duration(days: 2, hours: 1),
    ]) {
      expect(decodeIntervalDS(encodeIntervalDS(v), 0), v);
    }
    expect(decodeIntervalYM(encodeIntervalYM(const IntervalYM(3, 7)), 0),
        const IntervalYM(3, 7));
    expect(decodeIntervalYM(encodeIntervalYM(const IntervalYM(-3, -7)), 0),
        const IntervalYM(-3, -7));
  });

  group('statement parser', () {
    List<String> binds(String sql) =>
        [for (final b in Statement.prepare(sql).bindInfoList) b.name];

    test('statement types', () {
      expect(Statement.prepare('select * from dual').isQuery, isTrue);
      expect(
          Statement.prepare('  WITH x as (select 1 from dual) select * '
                  'from x')
              .isQuery,
          isTrue);
      expect(Statement.prepare('insert into t values (1)').isDml, isTrue);
      expect(Statement.prepare('begin null; end;').isPlsql, isTrue);
      expect(Statement.prepare('create table t (x number)').isDdl, isTrue);
    });

    test('bind names', () {
      expect(binds('select :a, :B, :"MixedCase", :1 from dual'),
          ['A', 'B', 'MixedCase', '1']);
      expect(binds("select ':not_bind' || :x -- :comment\nfrom dual"), ['X']);
      expect(binds('select /* :c */ :y from dual'), ['Y']);
      expect(binds("select q'[:no]' , :z from dual"), ['Z']);
      expect(binds('select :a, :a from dual'), ['A', 'A']);
      expect(binds('begin :a := :a + 1; end;'), ['A']);
      expect(binds("select json_object('k' : 1) from dual"), isEmpty);
    });

    test('DML returning', () {
      final stmt = Statement.prepare(
          'insert into t (x) values (:x) returning id into :id');
      expect(stmt.isReturning, isTrue);
      expect(
          [for (final b in stmt.bindInfoList) b.isReturnBind], [false, true]);
    });
  });
}
