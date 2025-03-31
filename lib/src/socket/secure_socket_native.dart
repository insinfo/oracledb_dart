// ignore_for_file: camel_case_types, non_constant_identifier_names
// ignore_for_file: constant_identifier_names, public_member_api_docs
// ignore_for_file: unused_field, lines_longer_than_80_chars

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
// Binding gerado pelo ffigen para OpenSSL 3
import 'package:oracledb_dart/src/openssl/openssl_ffi.dart';
import 'package:oracledb_dart/src/openssl/openssl_ssl_extension.dart';
import 'socket_native.dart';

class SecureSocketNative extends SocketNative {
  late final OpenSsl _openSsl;
  late final ffi.Pointer<ssl_ctx_st> _ctx; // typedef SSL_CTX = ssl_ctx_st
  late final ffi.Pointer<ssl_st> _ssl; // typedef SSL = ssl_st
  bool _sslInitialized = false;
  final bool _isServer;

  /// Construtor para modo cliente.
  SecureSocketNative(int family, int type, int protocol)
      : _isServer = false,
        super(family, type, protocol) {
    _initOpenSsl();
    _initializeSSL();
    _createSSLObject();
  }

  /// Construtor para modo servidor. É necessário informar o caminho do certificado e da chave privada (PEM).
  SecureSocketNative.server(
      int family, int type, int protocol, String certFile, String keyFile)
      : _isServer = true,
        super(family, type, protocol) {
    _initOpenSsl();
    _initializeSSL(certFile: certFile, keyFile: keyFile);
    _createSSLObject();
  }

  /// Inicializa o binding do OpenSSL.
  void _initOpenSsl() {
    final dynamicLibrary = Platform.isWindows
        ? ffi.DynamicLibrary.open('libssl-3-x64.dll')
        : Platform.isMacOS
            ? ffi.DynamicLibrary.open('libssl.dylib')
            : ffi.DynamicLibrary.open('libssl.so');
    _openSsl = OpenSsl(dynamicLibrary);
  }

  /// Inicializa o contexto SSL utilizando TLS.
  /// Se estiver no modo servidor, carrega o certificado e a chave privada.
  void _initializeSSL({String? certFile, String? keyFile}) {
    ffi.Pointer<SSL_METHOD> method;
    if (_isServer) {
      method = _openSsl.TLS_server_method();
    } else {
      method = _openSsl.TLS_client_method();
    }
    _ctx = _openSsl.SSL_CTX_new(method);
    if (_ctx == ffi.nullptr) {
      throw SocketException('Falha ao criar o contexto SSL');
    }
    if (_isServer) {
      if (certFile == null || keyFile == null) {
        throw SocketException(
            'Certificado e chave são necessários para o modo servidor');
      }
      final certFilePtr = certFile.toNativeUtf8();
      final keyFilePtr = keyFile.toNativeUtf8();
      int certResult = _openSsl.SSL_CTX_use_certificate_file(
          _ctx, certFilePtr.cast(), 1); // 1 = SSL_FILETYPE_PEM
      int keyResult =
          _openSsl.SSL_CTX_use_PrivateKey_file(_ctx, keyFilePtr.cast(), 1);
      calloc.free(certFilePtr);
      calloc.free(keyFilePtr);
      if (certResult != 1) {
        throw SocketException('Falha ao carregar o certificado');
      }
      if (keyResult != 1) {
        throw SocketException('Falha ao carregar a chave privada');
      }
    }
  }

  /// Cria o objeto SSL, associa o descritor do socket e realiza o handshake.
  void _createSSLObject() {
    _ssl = _openSsl.SSL_new(_ctx);
    if (_ssl == ffi.nullptr) {
      throw SocketException('Falha ao criar o objeto SSL');
    }
    // Obtém o descritor subjacente: para Windows usa _socket!.address; para Unix, _fd.
    int fd = Platform.isWindows
        ? getWindowsSocketHandle()!.address
        : getUnixSocketHandle()!;
    // Associa o socket ao objeto SSL usando a função da extensão.
    int result = _openSsl.SSL_set_fd(_ssl, fd);
    if (result != 1) {
      throw SocketException('Falha ao associar o descritor ao SSL');
    }
    // Realiza o handshake de acordo com o modo (cliente ou servidor).
    if (_isServer) {
      if (_openSsl.SSL_accept(_ssl) != 1) {
        throw SocketException('Handshake SSL (servidor) falhou');
      }
    } else {
      if (_openSsl.SSL_connect(_ssl) != 1) {
        throw SocketException('Handshake SSL (cliente) falhou');
      }
    }
    _sslInitialized = true;
  }

  /// Envia dados criptografados via SSL_write.
  @override
  int send(Uint8List data) {
    if (!_sslInitialized) {
      throw SocketException('SSL não inicializado');
    }
    final buffer = calloc<ffi.Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      buffer[i] = data[i];
    }
    int sent = _openSsl.SSL_write(_ssl, buffer.cast(), data.length);
    calloc.free(buffer);
    if (sent <= 0) {
      throw SocketException('Falha na escrita SSL');
    }
    return sent;
  }

  /// Recebe dados criptografados via SSL_read.
  @override
  Uint8List recv(int bufferSize) {
    if (!_sslInitialized) {
      throw SocketException('SSL não inicializado');
    }
    final buffer = calloc<ffi.Uint8>(bufferSize);
    int received = _openSsl.SSL_read(_ssl, buffer.cast(), bufferSize);
    if (received <= 0) {
      calloc.free(buffer);
      throw SocketException('Falha na leitura SSL');
    }
    final data = Uint8List(received);
    for (int i = 0; i < received; i++) {
      data[i] = buffer[i];
    }
    calloc.free(buffer);
    return data;
  }

  /// Realiza o shutdown do SSL, libera os recursos e fecha o socket nativo.
  @override
  void close() {
    if (_sslInitialized) {
      _openSsl.SSL_shutdown(_ssl);
      _openSsl.SSL_free(_ssl);
      _openSsl.SSL_CTX_free(_ctx);
      _sslInitialized = false;
    }
    super.close();
  }
}
