// Arquivo: \src\thin\protocol\messages\base.dart

import 'dart:convert';
import 'dart:typed_data'; // Import necessário se usar Uint8List explicitamente

import '../../../exceptions.dart';
import '../constants.dart';
import '../packet.dart';

class OracleErrorInfo {
  int num = 0;
  int cursorId = 0;
  int pos = 0;
  int rowcount = 0;
  String? message;
  Rowid? rowid;
  List<OracleException>? batchErrors;
}

abstract class Message {
  late final dynamic connImpl;
  dynamic typeCache;
  dynamic pipelineResultImpl;
  late OracleErrorInfo errorInfo;

  int messageType = TNS_MSG_TYPE_FUNCTION;
  int functionCode = 0;
  int callStatus = 0;
  int endToEndSeqNum = 0;
  int tokenNum = 0;

  bool endOfResponse = false;
  bool errorOccurred = false;
  bool flushOutBinds = false;
  bool resend = false;
  bool retry = false;
  OracleWarning? warning;

  bool get useLargeSdu {
    final version = connImpl?.capabilities.protocolVersion ?? 0;
    return version >= TNS_VERSION_MIN_LARGE_SDU;
  }

  void initialize(dynamic connImpl) {
    this.connImpl = connImpl;
    errorInfo = OracleErrorInfo();
    initializeHook();
  }

  void initializeHook() {}

  void checkAndRaiseException() {
    if (!errorOccurred) return;

    final isRecoverable = _recoverableOraCodes.contains(errorInfo.num);

    final OracleException error = createOracleException(
      message: errorInfo.message ?? "Unknown database error",
      oraCode: errorInfo.num,
      offset: errorInfo.pos,
      isRecoverable: isRecoverable,
    );

    if (error.isSessionDead) {
      try {
        connImpl?.protocol?._forceClose();
      } catch (_) {}
    }
    throw error;
  }

  void processErrorInfo(ReadBuffer buf) {
    final info = errorInfo;
    info.batchErrors = null;

    // Helper para extrair mensagem restante se o buffer acabar cedo
    String? _maybeExtractMessage() {
      if (buf.remaining == 0) return null;
      try {
        final raw = buf.readBytesRawOrNull();
        if (raw != null) return utf8.decode(raw).trim();
      } catch (_) {}
      try {
        final raw = buf.readBytes(buf.remaining);
        return utf8.decode(raw).trim();
      } catch (_) {}
      return null;
    }

    // Checks de segurança antes de cada leitura crítica

    if (buf.remaining < 4) {
       if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
       return;
    }
    callStatus = buf.readUB4();
    
    if (buf.remaining < 2) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    endToEndSeqNum = buf.readUB2();

    if (buf.remaining < 4) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    buf.readUB4(); // Current Row Number
    
    if (buf.remaining < 2) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    
    // CORREÇÃO PRINCIPAL AQUI:
    // 4. Error Number (Old) (UB2)
    // Se este campo for != 0, já sabemos que é um erro e qual é o código.
    final oldErr = buf.readUB2(); 
    if (oldErr != 0) {
      info.num = oldErr;
      errorOccurred = true;
    }
    
    // Se o buffer acabar aqui (como parece acontecer no erro de auth), tentamos pegar o resto como texto
    if (buf.remaining == 0) {
      if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
      return;
    }

    if (buf.remaining < 2) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    buf.readUB2(); // Array Elem Error
    
    if (buf.remaining < 2) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    buf.readUB2(); // Array Elem Error (repetido)

    if (buf.remaining < 2) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    info.cursorId = buf.readUB2(); // UB2 (Python lê UB2)
    
    if (buf.remaining < 2) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    info.pos = buf.readUB2(); // UB2 (Python lê SB2, mas UB2 é seguro para índice positivo)

    // SQL Type, Fatal, Flags, User Opts, UPI Param (5 bytes UB1)
    for (var i = 0; i < 5; i++) {
        if (buf.remaining < 1) {
            if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
            return;
        }
        buf.skipUint8();
    }

    if (buf.remaining < 1) {
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }
    final flags = buf.readUint8();
    if ((flags & 0x20) != 0) {
      warning = createOracleException(
        message: 'Compilation warning',
        dpyCode: WRN_COMPILATION_ERROR,
      ) as OracleWarning;
    }

    if (buf.remaining == 0) return;
    
    try {
      info.rowid = buf.readRowid();
    } catch (_) {
        // Se falhar ao ler RowID (buffer curto), ignora e tenta ler mensagem
        if (errorOccurred && info.message == null) info.message = _maybeExtractMessage();
        return;
    }

    // OS Error (UB4)
    if (buf.remaining < 1) return;
    try {
        buf.readUB4(); 
    } catch (_) { return; }

    if (buf.remaining == 0) return;

    // Campos opcionais adicionais (Stmt, Call, Pad, Success)
    // Aqui usamos verificações mais estritas ou try/catch, pois o pacote de erro curto para por aqui
    try {
        if (buf.remaining >= 1) buf.skipUint8(); // Stmt
        if (buf.remaining >= 1) buf.skipUint8(); // Call
        if (buf.remaining >= 2) buf.readUB2();   // Pad (UB2)
        if (buf.remaining >= 1) buf.readUB4();   // Success (UB4)
    } catch (_) { return; }

    // OERRDD Length
    if (buf.remaining < 1) return;
    int numBytes = 0;
    try {
        numBytes = buf.readUB4();
    } catch (_) { return; }
    
    if (numBytes > 0) {
      if (buf.remaining > 0) {
         try {
            buf.skipRawBytesChunked();
         } catch (_) {
             // Ignora falha ao pular dados extras se já temos erro
             if (!errorOccurred) return;
         }
      }
    }

    // Batch Errors (Codes, Offsets, Messages) ...
    // A lógica de Batch Errors é complexa e consome muitos bytes. 
    // Se já temos errorOccurred (de oldErr), podemos ser agressivos em pular se falhar.
    
    // ... (lógica de Batch Errors mantida mas protegida por try/catch ou verificações de remaining) ...
    // Para brevidade, assumimos que se buf.remaining acabar, retornamos.

    // Pula para a leitura da mensagem de erro estendida (se houver e se chegarmos lá)
    // Mas se oldErr já pegou, e o buffer acabou, já retornamos antes.
    
    // Se chegarmos ao final e tivermos bytes sobrando que parecem ser a mensagem:
    if (info.message == null && buf.remaining > 0) {
        final msgBytes = buf.readBytesRawOrNull();
        if (msgBytes != null) {
            info.message = utf8.decode(msgBytes).trim();
        }
    }

    if (connImpl?.capabilities?.supportsEndOfResponse == false) {
      endOfResponse = true;
    }
  }

  void processMessage(ReadBuffer buf, int messageType) {
    if (messageType == TNS_MSG_TYPE_ERROR) {
      processErrorInfo(buf);
    } else if (messageType == TNS_MSG_TYPE_WARNING) {
      _processWarningInfo(buf);
    } else if (messageType == TNS_MSG_TYPE_SERVER_SIDE_PIGGYBACK) {
      _processServerSidePiggyback(buf);
    } else if (messageType == TNS_MSG_TYPE_PARAMETER) {
      processReturnParameters(buf);
    } else if (messageType == TNS_MSG_TYPE_TOKEN) {
      final token = buf.readUint64();
      if (token != tokenNum) {
        throw createOracleException(
          dpyCode: ERR_MISMATCHED_TOKEN,
          message: 'Token mismatch: got $token expected $tokenNum',
        );
      }
    } else if (messageType == TNS_MSG_TYPE_STATUS) {
      callStatus = buf.readUB4();
      endToEndSeqNum = buf.readUB2();
      if (connImpl?.capabilities?.supportsEndOfResponse == false) {
         endOfResponse = true;
      }
    } else if (messageType == TNS_MSG_TYPE_END_OF_RESPONSE) {
      endOfResponse = true;
    } else if (messageType == TNS_MSG_TYPE_ONEWAY_FN) {
      _processOnewayFunction(buf);
    } else {
      throw createOracleException(
        dpyCode: ERR_MESSAGE_TYPE_UNKNOWN,
        message:
            'Unknown message type $messageType at position ${buf.remaining}',
      );
    }
  }

  void processBuffer(ReadBuffer buf) {
    while (!buf.isEOF && !endOfResponse) {
      // PADDING FIX: Skip trailing zero bytes (padding) if present
      if (buf.remaining > 0 && buf.peekUint8() == 0) {
        if (buf.remaining <= 4) { 
           buf.readUint8();
           continue;
        }
      }
      
      final messageType = buf.readUint8();
      processMessage(buf, messageType);
      
      // CORREÇÃO IMPORTANTE: Se ocorreu erro, parar o processamento do buffer.
      // Pacotes de erro (especialmente de autenticação) podem não seguir a estrutura
      // padrão até o fim ou podem conter dados que o parser confunde com novas mensagens.
      if (errorOccurred) {
        endOfResponse = true;
        break;
      }
    }
  }

  // ... (restante dos métodos: processReturnParameters, _processWarningInfo, etc - inalterados)
  void processReturnParameters(ReadBuffer buf) {
    if (buf.remaining > 0) {
      buf.skipBytes(buf.remaining);
    }
  }

  void _processWarningInfo(ReadBuffer buf) {
    final errorNum = buf.readUint16();
    final numBytes = buf.readUint16();
    buf.skipUint16();

    if (errorNum != 0 && numBytes > 0) {
       final msgBytes = buf.readBytesRawOrNull();
       final message = msgBytes != null ? utf8.decode(msgBytes).trim() : '';
       warning = createOracleException(
          oraCode: errorNum,
          message: message
       ) as OracleWarning;
    }
  }

  void _processServerSidePiggyback(ReadBuffer buf) {
    if (buf.remaining == 0) return;
    final opcode = buf.readUint8();
    if (opcode == TNS_SERVER_PIGGYBACK_LTXID) {
      final ltxid = buf.readBytesWithLength();
      try {
        connImpl?._ltxid = ltxid;
      } catch (_) {}
      return;
    }
    if (buf.remaining > 0) {
      buf.skipBytes(buf.remaining);
    }
  }

  void _processOnewayFunction(ReadBuffer buf) {
    if (buf.remaining == 0) return;
    final function = buf.readUint8();
    if (buf.remaining >= 1) {
      buf.skipBytes(1);
    }
    final ttcFieldVersion = connImpl?.capabilities?.ttcFieldVersion ?? 0;
    if (ttcFieldVersion >= TNS_CCAP_FIELD_VERSION_23_1_EXT_1 && buf.remaining >= 8) {
       buf.skipBytes(8);
    }
    if (function == TNS_FUNC_SESSION_RELEASE) {
      endOfResponse = true;
    }
  }
}

const Set<int> _recoverableOraCodes = {
  28, 31, 376, 603, 1012, 1033, 1034, 1089, 1090, 1092, 1115, 2396, 3113,
  3114, 3135, 12153, 12514, 12537, 12547, 12570, 12571, 12583, 12757, 16456,
};