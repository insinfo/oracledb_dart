import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:oracledb_dart/src/thin/protocol/constants.dart';
import 'package:oracledb_dart/src/thin/protocol/packet.dart';

/// implementado este teste unitario em python para avaliar o comportamento do python
/// python -m pytest python-oracledb/tests/test_buffer_unit.py

void main() {
  group('WriteBuffer', () {
    test('writeUint8 roundtrip', () {
      final buffer = WriteBuffer()..writeUint8(0xFF);
      final reader = ReadBuffer(buffer.toBytes());
      expect(reader.readUint8(), equals(0xFF));
    });

    test('writeUint16be byte order', () {
      final buffer = WriteBuffer()..writeUint16(0x1234);
      final bytes = buffer.toBytes();
      // Verifica Big Endian: 0x12 (18) primeiro, 0x34 (52) depois
      expect(bytes, equals([0x12, 0x34]));
    });
  });

  group('ReadBuffer string handling', () {
    test('utf8 length-prefixed round trip (chunked encoding)', () {
      final payload = WriteBuffer();
      final textBytes = utf8.encode('Cafe\u00E9 mundo');
      
      payload
        ..writeUB4(textBytes.length)
        ..writeBytesWithLength(textBytes);

      final reader = ReadBuffer(payload.toBytes());
      expect(reader.readStringWithLength(), equals('Cafe\u00E9 mundo'));
    });

    test('bytes with length round trip (chunked encoding)', () {
      final payload = WriteBuffer();
      final data = List<int>.generate(40, (i) => i);
      
      payload
        ..writeUB4(data.length)
        ..writeBytesWithLength(data);
        
      final reader = ReadBuffer(payload.toBytes());
      expect(reader.readBytesWithLength(), equals(Uint8List.fromList(data)));
    });
  });
  
  // Teste específico para o método interno que ainda suporta chunking (usado em LOBs/Caps)
  group('Internal Chunked Reader', () {
    test('readBytesRawOrNull handles chunks', () {
      final payload = WriteBuffer();
      final chunk1 = [1, 2, 3];
      final chunk2 = [4, 5];
      
      payload
        // Simulando estrutura chunked manualmente:
        ..writeUint8(TNS_LONG_LENGTH_INDICATOR) // Marcador 0xFE
        ..writeUB4(chunk1.length)               // Tamanho Chunk 1
        ..writeBytes(chunk1)                    // Dados 1
        ..writeUB4(chunk2.length)               // Tamanho Chunk 2
        ..writeBytes(chunk2)                    // Dados 2
        ..writeUB4(0);                          // Fim dos chunks

      final reader = ReadBuffer(payload.toBytes());
      
      // Usamos o método interno ou específico que manteve a lógica de chunking
      // Se você expôs o readBytesRawOrNull na correção anterior:
      final result = reader.readBytesRawOrNull(); 
      
      expect(result, equals([1, 2, 3, 4, 5]));
    });
  });
}