@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<void> _ignore(OracleConnection conn, String sql) async {
  try {
    await conn.execute(sql);
  } on OracleDatabaseError {
    // object does not exist
  }
}

void main() {
  group('objects and collections', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    Future<void> dropAll() async {
      await dropTable(conn(), 'dart_obj_t');
      await _ignore(conn(), 'drop package dart_obj_pkg');
      for (final t in [
        'dart_obj_nt',
        'dart_obj_va',
        'dart_obj_person',
        'dart_obj_addr',
        'dart_obj_nums',
      ]) {
        await _ignore(conn(), 'drop type $t force');
      }
    }

    setUpAll(() async {
      await dropAll();
      await conn().execute('''
          create type dart_obj_addr as object (
            street varchar2(60),
            city   nvarchar2(30)
          )''');
      await conn().execute('''
          create type dart_obj_person as object (
            id        number(9),
            name      varchar2(40),
            salary    number(10, 2),
            born      date,
            updated   timestamp(6),
            ratio     binary_double,
            photo     raw(20),
            address   dart_obj_addr
          )''');
      await conn()
          .execute('create type dart_obj_va as varray(10) of varchar2(20)');
      await conn().execute('create type dart_obj_nt as table of dart_obj_addr');
      await conn().execute('create type dart_obj_nums as table of number');
      await conn().execute('''
          create table dart_obj_t (
            id      number,
            person  dart_obj_person,
            tags    dart_obj_va,
            addrs   dart_obj_nt
          ) nested table addrs store as dart_obj_t_addrs''');
      await conn().execute('''
          create or replace package dart_obj_pkg as
            type num_tab is table of number index by binary_integer;
            type rec_t is record (id number, name varchar2(30));
            function total(a num_tab) return number;
            procedure squares(n number, a out num_tab);
            function make_addr(s varchar2) return dart_obj_addr;
          end;''');
      await conn().execute('''
          create or replace package body dart_obj_pkg as
            function total(a num_tab) return number is
              t number := 0;
              i binary_integer := a.first;
            begin
              while i is not null loop
                t := t + a(i) * i;
                i := a.next(i);
              end loop;
              return t;
            end;
            procedure squares(n number, a out num_tab) is
            begin
              for i in 1..n loop
                a(i * 10) := i * i;
              end loop;
            end;
            function make_addr(s varchar2) return dart_obj_addr is
            begin
              return dart_obj_addr(s, 'Curitiba');
            end;
          end;''');
    });
    tearDownAll(dropAll);

    test('getType describes attributes', () async {
      final type = await conn().getType('DART_OBJ_PERSON');
      expect(type.name, 'DART_OBJ_PERSON');
      expect(type.isCollection, isFalse);
      expect(type.attributes.map((a) => a.name), [
        'ID', 'NAME', 'SALARY', 'BORN', 'UPDATED', 'RATIO', 'PHOTO', //
        'ADDRESS',
      ]);
      final address = type.attribute('ADDRESS')!;
      expect(address.dbType, DbType.object);
      expect(address.objectType!.name, 'DART_OBJ_ADDR');
      expect(type.attribute('NAME')!.maxSize, 40);
      expect(type.attribute('SALARY')!.scale, 2);

      final va = await conn().getType('dart_obj_va');
      expect(va.isCollection, isTrue);
      expect(va.maxNumElements, 10);
      expect(va.element!.dbType, DbType.varchar);
    });

    test('insert and fetch objects and collections', () async {
      final personType = await conn().getType('DART_OBJ_PERSON');
      final addrType = await conn().getType('DART_OBJ_ADDR');
      final vaType = await conn().getType('DART_OBJ_VA');
      final ntType = await conn().getType('DART_OBJ_NT');
      final born = DateTime.utc(1990, 5, 17);
      final updated = DateTime.utc(2024, 1, 2, 3, 4, 5, 678);
      final person = personType.newObject({
        'ID': 7,
        'NAME': 'Ana',
        'SALARY': 1234.56,
        'BORN': born,
        'UPDATED': updated,
        'RATIO': 0.25,
        'PHOTO': Uint8List.fromList([1, 2, 3]),
        'ADDRESS':
            addrType.newObject({'STREET': 'Rua XV', 'CITY': 'São Paulo'}),
      });
      final tags = vaType.newObject(['a', 'b', 'c' * 20]);
      final addrs = ntType.newObject([
        addrType.newObject({'STREET': 'One', 'CITY': 'X'}),
        addrType.newObject({'STREET': 'Two', 'CITY': null}),
      ]);
      await conn().execute('insert into dart_obj_t values (:1, :2, :3, :4)',
          [1, person, tags, addrs]);
      // a null object is bound with a variable of the object type
      final cursor = conn().cursor();
      await cursor.execute('insert into dart_obj_t values (:1, :2, :3, :4)', [
        2,
        cursor.variable(DbType.object, objectType: personType),
        cursor.variable(DbType.object, objectType: vaType),
        cursor.variable(DbType.object, objectType: ntType),
      ]);
      cursor.close();

      final rows = await conn()
          .query('select id, person, tags, addrs from dart_obj_t order by id');
      expect(rows, hasLength(2));
      final p = rows[0][1] as OracleDbObject;
      expect(p.type.name, 'DART_OBJ_PERSON');
      expect(p['ID'], 7);
      expect(p['NAME'], 'Ana');
      expect(p['SALARY'], 1234.56);
      expect(p['BORN'], born);
      expect(p['UPDATED'], updated);
      expect(p['RATIO'], 0.25);
      expect(p['PHOTO'], [1, 2, 3]);
      final a = p['ADDRESS'] as OracleDbObject;
      expect(a.asMap(), {'STREET': 'Rua XV', 'CITY': 'São Paulo'});
      expect((rows[0][2] as OracleDbObject).asList(), ['a', 'b', 'c' * 20]);
      final nt = rows[0][3] as OracleDbObject;
      expect(nt.length, 2);
      expect((nt[0] as OracleDbObject)['STREET'], 'One');
      expect(
          (nt[1] as OracleDbObject).asMap(), {'STREET': 'Two', 'CITY': null});
      expect(rows[1].sublist(1), [null, null, null]);

      final view = await conn()
          .queryOne('select t.person.address.city, cardinality(t.addrs) '
              'from dart_obj_t t where id = 1');
      expect(view, ['São Paulo', 2]);
    });

    test('objects returned by queries without getType', () async {
      // a fresh connection discovers the types from the query metadata
      final other = await connect();
      addTearDown(other.close);
      final row = await other.queryOne(
          "select dart_obj_addr('A', 'B'), dart_obj_nums(1, 2.5, null) "
          'from dual');
      expect((row![0] as OracleDbObject).asMap(), {'STREET': 'A', 'CITY': 'B'});
      expect((row[1] as OracleDbObject).asList(), [1, 2.5, null]);
    });

    test('collection methods', () async {
      final numsType = await conn().getType('DART_OBJ_NUMS');
      final nums = numsType.newObject([1, 2, 3]);
      nums.append(4);
      expect(nums.length, 4);
      expect(nums.firstIndex, 0);
      expect(nums.lastIndex, 3);
      expect(nums.nextIndex(1), 2);
      expect(nums.prevIndex(0), isNull);
      nums[0] = 10;
      nums.trim(1);
      expect(nums.asList(), [10, 2, 3]);
      expect(nums.exists(2), isTrue);
      expect(nums.exists(3), isFalse);
      expect(() => nums.getElement(5), throwsA(isA<OracleException>()));

      final vaType = await conn().getType('DART_OBJ_VA');
      final va = vaType.newObject(List.filled(10, 'x'));
      expect(() => va.append('y'), throwsA(isA<OracleException>()));

      final row = await conn()
          .queryOne('select sum(column_value) from table(:1)', [nums]);
      expect(row, [15]);
    });

    test('PL/SQL associative arrays and OUT objects', () async {
      final tabType = await conn().getType('DART_OBJ_PKG.NUM_TAB');
      expect(tabType.isCollection, isTrue);
      expect(tabType.isAssociativeArray, isTrue);
      final tab = tabType.newObject({1: 5, 3: 7, -2: 1});
      final cursor = conn().cursor();
      final total =
          await cursor.callFunc('dart_obj_pkg.total', DbType.number, [tab]);
      expect(total, 1 * 5 + 3 * 7 - 2 * 1);

      final out = cursor.variable(DbType.object, objectType: tabType);
      await cursor.callProc('dart_obj_pkg.squares', [3, out]);
      final squares = out.value as OracleDbObject;
      expect(squares.asMap(), {'10': 1, '20': 4, '30': 9});
      expect(squares.firstIndex, 10);
      expect(squares.nextIndex(10), 20);
      expect(squares.lastIndex, 30);

      final addrType = await conn().getType('DART_OBJ_ADDR');
      final addr = await cursor.callFunc(
          'dart_obj_pkg.make_addr', DbType.object, ['Rua A'], addrType);
      expect(addr, isA<OracleDbObject>());
      expect((addr as OracleDbObject).type, addrType);
      expect(addr['CITY'], 'Curitiba');
      expect(() => cursor.variable(DbType.object), throwsArgumentError);
      cursor.close();
    });

    test('PL/SQL record types', () async {
      final recType = await conn().getType('DART_OBJ_PKG.REC_T');
      expect(recType.attributes.map((a) => a.name), ['ID', 'NAME']);
      final rec = recType.newObject({'ID': 1, 'NAME': 'rec'});
      final cursor = conn().cursor();
      final out = cursor.variable(DbType.varchar, size: 100);
      await cursor.execute('''
          declare
            r dart_obj_pkg.rec_t := :rec;
          begin
            :out := r.id || '-' || r.name;
          end;''', {'rec': rec, 'out': out});
      expect(out.value, '1-rec');
      cursor.close();
    });

    test('XMLType values are fetched as strings', () async {
      final row =
          await conn().queryOne("select xmltype('<a><b>1</b></a>') from dual");
      expect(row![0], contains('<b>1</b>'));
    });

    test('unknown type names raise an error', () async {
      expect(() => conn().getType('DART_NO_SUCH_TYPE'),
          throwsA(isA<OracleException>()));
    });
  });
}
