@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('scrollable cursors', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();
    const sql = 'select level from dual connect by level <= 1000';

    test('scrolls to absolute, relative, first and last positions', () async {
      final cursor = conn().cursor()
        ..scrollable = true
        ..arraySize = 20;
      await cursor.execute(sql);
      expect(await cursor.fetchOne(), [1]);
      await cursor.scroll(500, ScrollMode.absolute);
      expect(await cursor.fetchOne(), [500]);
      // relative scrolls are relative to the current row (500)
      await cursor.scroll(-100);
      expect(await cursor.fetchOne(), [400]);
      await cursor.scroll(5);
      expect(await cursor.fetchOne(), [405]);
      await cursor.scroll(0, ScrollMode.last);
      expect(await cursor.fetchOne(), [1000]);
      expect(await cursor.fetchOne(), isNull);
      await cursor.scroll(0, ScrollMode.first);
      expect(await cursor.fetchMany(3), [
        [1],
        [2],
        [3]
      ]);
      // scrolling within the rows already fetched needs no round trip
      await cursor.scroll(2, ScrollMode.absolute);
      expect(await cursor.fetchOne(), [2]);
      await expectLater(cursor.scroll(2000, ScrollMode.absolute),
          throwsA(isA<OracleException>()));
      await expectLater(cursor.scroll(-5000), throwsA(isA<OracleException>()));
      cursor.close();
    });

    test('scrollable cursors fetch all rows in order', () async {
      final cursor = conn().cursor()
        ..scrollable = true
        ..arraySize = 77;
      await cursor.execute(sql);
      final rows = await cursor.fetchAll();
      expect(rows.length, 1000);
      expect(rows.last, [1000]);
      cursor.close();
    });

    test('scroll requires a scrollable cursor', () async {
      final cursor = conn().cursor();
      await cursor.execute(sql);
      await expectLater(cursor.scroll(1), throwsA(isA<OracleException>()));
      cursor.close();
    });
  });
}
