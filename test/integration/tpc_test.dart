@Tags(['integration'])
library;

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('two-phase commit', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();
    var counter = 0;
    Xid newXid() => Xid(3900,
        'dart-${DateTime.now().microsecondsSinceEpoch}-${counter++}', 'b1');

    setUpAll(() async {
      await dropTable(conn(), 'dart_tpc_t');
      await conn().execute('create table dart_tpc_t (id number)');
    });
    tearDownAll(() => dropTable(conn(), 'dart_tpc_t'));

    Future<int> countRows(int id) async {
      final other = await connect();
      final row = await other
          .queryOne('select count(*) from dart_tpc_t where id = :1', [id]);
      await other.close();
      return row![0] as int;
    }

    test('prepare and commit while attached to the transaction', () async {
      final xid = newXid();
      await conn().tpcBegin(xid);
      await conn().execute('insert into dart_tpc_t values (1)');
      expect(await conn().tpcPrepare(), isTrue);
      await conn().tpcCommit();
      expect(await countRows(1), 1);
    });

    test('prepare and commit a detached transaction by xid', () async {
      final xid = newXid();
      await conn().tpcBegin(xid);
      await conn().execute('insert into dart_tpc_t values (5)');
      await conn().tpcEnd();
      expect(await conn().tpcPrepare(xid), isTrue);
      await conn().tpcCommit(xid);
      expect(await countRows(5), 1);
    });

    test('one phase commit', () async {
      final xid = newXid();
      await conn().tpcBegin(xid);
      await conn().execute('insert into dart_tpc_t values (2)');
      await conn().tpcEnd();
      await conn().tpcCommit(xid, true);
      expect(await countRows(2), 1);
    });

    test('rollback after prepare', () async {
      final xid = newXid();
      await conn().tpcBegin(xid);
      await conn().execute('insert into dart_tpc_t values (3)');
      await conn().tpcEnd();
      expect(await conn().tpcPrepare(xid), isTrue);
      await conn().tpcRollback(xid);
      expect(await countRows(3), 0);
    });

    test('read only transactions require no commit', () async {
      final xid = newXid();
      await conn().tpcBegin(xid);
      await conn().query('select count(*) from dart_tpc_t');
      expect(await conn().tpcPrepare(), isFalse);
    });

    test('pending transactions can be recovered', () async {
      final xid = newXid();
      final other = await connect();
      await other.tpcBegin(xid);
      await other.execute('insert into dart_tpc_t values (4)');
      await other.tpcEnd();
      expect(await other.tpcPrepare(xid), isTrue);
      await other.close();
      List<Xid> pending;
      try {
        pending = await conn().tpcRecover();
      } on OracleDatabaseError catch (e) {
        if (e.code != 942) rethrow;
        // no access to DBA_PENDING_TRANSACTIONS: commit using the xid
        await conn().tpcCommit(xid);
        expect(await countRows(4), 1);
        return;
      }
      expect(pending, contains(xid));
      await conn().tpcCommit(xid);
      expect(await countRows(4), 1);
    });
  });
}
