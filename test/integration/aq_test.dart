@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:oracledb_dart/oracledb_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _queues = {
  'DART_RAW_Q': 'RAW',
  'DART_JSON_Q': 'JSON',
  'DART_OBJ_Q': 'DART_AQ_MSG',
  'DART_MULTI_Q': 'RAW',
};

Future<void> _dropQueues(OracleConnection conn) async {
  for (final name in _queues.keys) {
    await conn.execute('''
        begin
          begin
            dbms_aqadm.stop_queue('$name');
          exception when others then null;
          end;
          begin
            dbms_aqadm.drop_queue('$name');
          exception when others then null;
          end;
          begin
            dbms_aqadm.drop_queue_table('${name}_TAB', force => true);
          exception when others then null;
          end;
        end;''');
  }
  try {
    await conn.execute('drop type dart_aq_msg force');
  } on OracleDatabaseError {
    // type does not exist
  }
}

void main() {
  group('advanced queuing', skip: OracleTestConfig.skipReason, () {
    final conn = sharedConnection();

    setUpAll(() async {
      await _dropQueues(conn());
      await conn().execute('''
          create type dart_aq_msg as object (
            id   number,
            text varchar2(100)
          )''');
      for (final entry in _queues.entries) {
        final multiple = entry.key == 'DART_MULTI_Q' ? 'true' : 'false';
        await conn().execute('''
            begin
              dbms_aqadm.create_queue_table('${entry.key}_TAB', '${entry.value}',
                  multiple_consumers => $multiple);
              dbms_aqadm.create_queue('${entry.key}', '${entry.key}_TAB');
              dbms_aqadm.start_queue('${entry.key}');
            end;''');
      }
    });
    tearDownAll(() => _dropQueues(conn()));

    OracleQueue rawQueue() {
      final queue = conn().queue('DART_RAW_Q');
      queue.deqOptions.wait = AqDeqOptions.noWait;
      return queue;
    }

    test('enqueue and dequeue RAW messages', () async {
      final queue = rawQueue();
      final message = OracleMessage(payload: 'hello', correlation: 'c1');
      await queue.enqOne(message);
      expect(message.msgId, hasLength(16));
      await queue.enqOne(OracleMessage(payload: Uint8List.fromList([1, 2])));
      await conn().commit();

      final first = await queue.deqOne();
      expect(utf8.decode(first!.payload as Uint8List), 'hello');
      expect(first.correlation, 'c1');
      expect(first.msgId, message.msgId);
      expect(first.enqTime, isNotNull);
      expect(first.state, AqMessageState.ready);
      final second = await queue.deqOne();
      expect(second!.payload, [1, 2]);
      expect(await queue.deqOne(), isNull);
      await conn().commit();
    });

    test('enqueue and dequeue many messages', () async {
      final queue = rawQueue();
      final messages = [
        for (var i = 0; i < 5; i++) OracleMessage(payload: 'message $i')
      ];
      await queue.enqMany(messages);
      expect(messages.map((m) => m.msgId), everyElement(hasLength(16)));
      await conn().commit();

      final got = await queue.deqMany(3);
      expect(got.map((m) => utf8.decode(m.payload as Uint8List)),
          ['message 0', 'message 1', 'message 2']);
      final rest = await queue.deqMany(10);
      expect(rest, hasLength(2));
      expect(await queue.deqMany(10), isEmpty);
      await conn().commit();
    });

    test('dequeue options: correlation, browse and message id', () async {
      final queue = rawQueue();
      await queue.enqMany([
        OracleMessage(payload: 'a', correlation: 'red'),
        OracleMessage(payload: 'b', correlation: 'blue'),
        OracleMessage(payload: 'c', correlation: 'red'),
      ]);
      await conn().commit();

      queue.deqOptions
        ..mode = AqDeqMode.browse
        ..correlation = 'blue';
      final browsed = await queue.deqOne();
      expect(utf8.decode(browsed!.payload as Uint8List), 'b');

      queue.deqOptions
        ..mode = AqDeqMode.remove
        ..correlation = null
        ..msgId = browsed.msgId;
      expect((await queue.deqOne())!.msgId, browsed.msgId);

      queue.deqOptions.msgId = null;
      final reds = await queue.deqMany(10);
      expect(reds.map((m) => m.correlation), ['red', 'red']);
      await conn().commit();
    });

    test('immediate visibility and rollback', () async {
      final queue = rawQueue();
      await queue.enqOne(OracleMessage(payload: 'kept'));
      await conn().commit();
      await queue.deqOne();
      await conn().rollback();
      // the dequeue was rolled back, so the message is still there
      queue.deqOptions.visibility = AqVisibility.immediate;
      final again = await queue.deqOne();
      expect(utf8.decode(again!.payload as Uint8List), 'kept');
      expect(again.numAttempts, 1);
    });

    test('JSON payloads', () async {
      final queue = conn().queue('DART_JSON_Q', json: true);
      queue.deqOptions.wait = AqDeqOptions.noWait;
      await queue.enqOne(OracleMessage(payload: {
        'id': 1,
        'tags': ['x', 'y'],
        'ok': true,
      }));
      await queue.enqMany([
        OracleMessage(payload: [1, 2, 3]),
        OracleMessage(payload: {
          'nested': {'a': 1.5}
        }),
      ]);
      await conn().commit();
      final first = await queue.deqOne();
      expect(first!.payload, {
        'id': 1,
        'tags': ['x', 'y'],
        'ok': true,
      });
      final rest = await queue.deqMany(5);
      expect(rest.map((m) => m.payload), [
        [1, 2, 3],
        {
          'nested': {'a': 1.5}
        },
      ]);
      await conn().commit();
      expect(() => queue.enqOne(OracleMessage(payload: 'text')),
          throwsA(isA<OracleException>()));
    });

    test('object payloads', () async {
      final type = await conn().getType('DART_AQ_MSG');
      final queue = conn().queue('DART_OBJ_Q', payloadType: type);
      queue.deqOptions.wait = AqDeqOptions.noWait;
      await queue.enqOne(
          OracleMessage(payload: type.newObject({'ID': 1, 'TEXT': 'one'})));
      await queue.enqMany([
        for (var i = 2; i <= 3; i++)
          OracleMessage(payload: type.newObject({'ID': i, 'TEXT': 'n$i'}))
      ]);
      await conn().commit();

      queue.deqOptions.condition = 'tab.user_data.id = 3';
      final third = await queue.deqOne();
      expect(
          (third!.payload as OracleDbObject).asMap(), {'ID': 3, 'TEXT': 'n3'});
      queue.deqOptions.condition = null;
      final rest = await queue.deqMany(5);
      expect(rest.map((m) => (m.payload as OracleDbObject)['ID']), [1, 2]);
      await conn().commit();
    });

    test('multi-consumer queues and recipients', () async {
      final queue = conn().queue('DART_MULTI_Q');
      queue.deqOptions.wait = AqDeqOptions.noWait;
      await queue
          .enqOne(OracleMessage(payload: 'for ana', recipients: ['ANA']));
      await queue.enqMany([
        OracleMessage(payload: 'for both', recipients: ['ANA', 'BIA']),
      ]);
      await conn().commit();
      queue.deqOptions
        ..consumerName = 'BIA'
        ..navigation = AqDeqNavigation.firstMessage;
      final bia = await queue.deqMany(10);
      expect(bia.map((m) => utf8.decode(m.payload as Uint8List)), ['for both']);
      queue.deqOptions.consumerName = 'ANA';
      final ana = await queue.deqMany(10);
      expect(ana, hasLength(2));
      await conn().commit();
    });

    test('messages without a valid payload are rejected', () async {
      final queue = rawQueue();
      expect(
          () => queue.enqOne(OracleMessage()), throwsA(isA<OracleException>()));
      expect(() => queue.enqOne(OracleMessage(payload: 12)),
          throwsA(isA<OracleException>()));
    });
  });
}
