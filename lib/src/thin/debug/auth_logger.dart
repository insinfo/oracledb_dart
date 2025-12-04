import 'dart:io';
import 'dart:typed_data';

/// Utilitário simples para registrar pacotes AUTH em hex para depuração.
class AuthPacketLogger {
  static final bool _enabled =
      (Platform.environment['DART_AUTH_TRACE'] == '1') ||
          Platform.environment.containsKey('DART_AUTH_TRACE_FILE');
  static final String _logPath =
      Platform.environment['DART_AUTH_TRACE_FILE'] ?? 'auth_dart_packets.log';
  static IOSink? _sink;

  static bool get enabled => _enabled;

  static void logSend(String phase, Uint8List bytes) {
    _log('SEND', phase, bytes);
  }

  static void logReceive(String phase, Uint8List bytes) {
    _log('RECV', phase, bytes);
  }

  static void _log(String direction, String phase, Uint8List data) {
    if (!enabled) return;
    try {
      final sink = _sink ??= File(_logPath).openWrite(mode: FileMode.append);
      final timestamp = DateTime.now().toIso8601String();
      sink.writeln('[$timestamp] $direction $phase len=${data.length}');
      sink.writeln(_formatHex(data));
      sink.writeln('');
      sink.flush();
    } catch (_) {
      // Se o sink foi “bound” a outro stream ou corrompido, recria e tenta de novo.
      _sink = null;
      try {
        final sink = _sink ??= File(_logPath).openWrite(mode: FileMode.append);
        final timestamp = DateTime.now().toIso8601String();
        sink.writeln('[$timestamp] $direction $phase len=${data.length}');
        sink.writeln(_formatHex(data));
        sink.writeln('');
        sink.flush();
      } catch (_) {
        // Última tentativa falhou; não bloquear a aplicação.
      }
    }
  }

  static String _formatHex(Uint8List data) {
    final buffer = StringBuffer();
    for (var i = 0; i < data.length; i += 16) {
      final end = (i + 16).clamp(0, data.length);
      final chunk = data.sublist(i, end);
      final hex = chunk
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .padRight(16 * 3 - 1);
      final ascii = chunk
          .map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.')
          .join();
      buffer.writeln('${i.toRadixString(16).padLeft(4, '0')}: $hex  $ascii');
    }
    return buffer.toString().trimRight();
  }
}
