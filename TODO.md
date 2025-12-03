continue a portar o driver oracledb puro python C:\MyDartProjects\tlslite\oracledb_dart\python-oracledb para dart e atualizar o C:\MyDartProjects\tlslite\oracledb_dart\TODO.md

- [x] portar a fábrica de exceções/DPY-xxxx e usar na verificação de charset (`lib/src/exceptions.dart`, `lib/src/thin/protocol/capabilities.dart`).
- [x] portar helpers de protocolo para detectar end-of-response, Rowid e buffers básicos (`lib/src/thin/protocol/packet.dart`).
- [x] portar o transporte thin (envio/recepção de pacotes) de `python-oracledb/src/oracledb/impl/thin/transport.pyx`.
- [x] iniciar port do esqueleto de mensagens base (erros/warnings parciais) (`lib/src/thin/protocol/messages/base.dart`).
- [x] criar stub de conexão thin e testes de integração baseados em env (`lib/src/thin/connection.dart`, `test/integration`).
- [x] adicionar esqueleto de CONNECT/ACCEPT e parser parcial (`lib/src/thin/protocol/messages/connect.dart`).
- [x] documentar plano de handshake TTC (`doc/handshake_plan.md`).
- [x] portar constantes de CONNECT (GSO/NSI/protocol characteristics) (`lib/src/thin/protocol/constants.dart`).
- [x] montar CONNECT packet inicial e usar em `ThinConnection.connect()` com teste de handshake gated por `ORACLE_TESTS` (`lib/src/thin/connection.dart`, `test/integration/handshake_smoke_test.dart`).
- [x] adicionar plano de auth/login e teste de login/query placeholder (`doc/auth_plan.md`, `test/integration/login_query_test.dart`).
- [x] mapear plano de crypto para AUTH (CBC/PBKDF2 helpers) (`doc/crypto_plan.md`).
- [x] portar helpers de crypto (AES-CBC, PBKDF2) (`lib/src/thin/crypto.dart`, `pubspec.yaml`).
- [ ] completar o parsing das mensagens base (warnings/piggybacks/row data/result sets) e amarrar ao transporte.
- [ ] implementar login TTC completo (AUTH, session setup) após CONNECT/ACCEPT.
- [ ] expandir testes de integração para login e queries simples (usar `ORACLE_TESTS=1`).
