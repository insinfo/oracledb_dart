import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:oracledb_dart/src/openssl/libcrypto_ff.dart';
import 'package:oracledb_dart/src/openssl/x509_certificate_builder.dart';
import 'package:oracledb_dart/src/socket/secure_socket_native.dart';
import 'package:oracledb_dart/src/socket/socket_native.dart';
import 'package:oracledb_dart/src/openssl/openssl_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('SecureSocketNative Tests', () {
    late String certFile;
    late String keyFile;
    late Directory tempDir;

    // Cria os certificados autoassinados usando X509CertificateBuilder.
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('secure_socket_test');
      certFile = path.join(tempDir.path, 'test_cert.pem');
      keyFile = path.join(tempDir.path, 'test_key.pem');

      // Carrega a biblioteca OpenSSL.
      final dllLibssl = Platform.isWindows
          ? DynamicLibrary.open('libssl-3-x64.dll')
          : Platform.isMacOS
              ? DynamicLibrary.open('libssl.dylib')
              : DynamicLibrary.open('libssl.so');

      final openSsl = OpenSsl(dllLibssl);

      final dllLibcrypto = Platform.isWindows
          ? DynamicLibrary.open('libcrypto-3-x64.dll')
          : Platform.isMacOS
              ? DynamicLibrary.open('libcrypto.dylib')
              : DynamicLibrary.open('libcrypto.so');
              
      final libcrypt = OpenSslCrypto(dllLibcrypto);
      // Cria o builder e gera par de chaves e certificado.
      final builder = X509CertificateBuilder(libcrypt, openSsl);
      final key = builder.generateKeyPair();
      final cert = builder.createSelfSignedCertificate(key, validityDays: 365);
      final certPem = builder.x509ToPem(cert);
      final keyPem = builder.privateKeyToPem(key);

      await File(certFile).writeAsString(certPem);
      await File(keyFile).writeAsString(keyPem);
    });

    tearDownAll(() async {
      await File(certFile).delete();
      await File(keyFile).delete();
      await tempDir.delete(recursive: true);
    });

    test('Client-Server communication', () async {
      // Escolhe uma porta para o servidor (verifique se a porta está disponível)
      final serverPort = 8443;

      // Função que inicia o servidor seguro.
      Future<void> startServer() async {
        // Cria o socket em modo servidor com os certificados autoassinados gerados.
        final serverSocket = SecureSocketNative.server(
          AF_INET,
          SOCK_STREAM,
          IPPROTO_TCP,
          certFile,
          keyFile,
        );
        serverSocket.bind('127.0.0.1', serverPort);
        serverSocket.listen(5);
        // Aceita uma conexão do cliente.
        final clientConnection = serverSocket.accept();
        // Recebe a mensagem do cliente.
        final receivedData = clientConnection.recv(1024);
        final clientMessage = utf8.decode(receivedData);
        print('Servidor recebeu: $clientMessage');
        // Envia resposta ao cliente.
        final response = 'Hello from server!';
        clientConnection.send(utf8.encode(response));
        clientConnection.close();
        serverSocket.close();
      }

      // Inicia o servidor em uma tarefa assíncrona.
      final serverFuture = startServer();

      // Aguarda um curto intervalo para que o servidor inicie.
      await Future.delayed(Duration(milliseconds: 500));

      // Inicia o socket cliente (modo cliente).
      final clientSocket =
          SecureSocketNative(AF_INET, SOCK_STREAM, IPPROTO_TCP);
      clientSocket.connect('127.0.0.1', serverPort);
      final message = 'Hello from client!';
      clientSocket.send(utf8.encode(message));
      final responseData = clientSocket.recv(1024);
      final responseMessage = utf8.decode(responseData);
      print('Cliente recebeu: $responseMessage');
      clientSocket.close();

      // Aguarda o término do servidor.
      await serverFuture;

      // Verifica se o cliente recebeu a resposta esperada.
      expect(responseMessage, equals('Hello from server!'));
    });
  });
}
