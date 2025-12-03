continue a portar o driver oracledb puro python C:\MyDartProjects\tlslite\oracledb_dart\python-oracledb para dart e atualizar o C:\MyDartProjects\tlslite\oracledb_dart\TODO.md

- [x] portar a fabrica de excecoes/DPY-xxxx e usar na verificacao de charset (`lib/src/exceptions.dart`, `lib/src/thin/protocol/capabilities.dart`).
- [x] portar helpers de protocolo para detectar end-of-response, Rowid e buffers basicos (`lib/src/thin/protocol/packet.dart`).
- [x] portar o transporte thin (envio/recepcao de pacotes) de `python-oracledb/src/oracledb/impl/thin/transport.pyx`.
- [x] iniciar port do esqueleto de mensagens base (erros/warnings parciais) (`lib/src/thin/protocol/messages/base.dart`).
- [x] criar stub de conexao thin e testes de integracao baseados em env (`lib/src/thin/connection.dart`, `test/integration`).
- [x] adicionar esqueleto de CONNECT/ACCEPT e parser parcial (`lib/src/thin/protocol/messages/connect.dart`).
- [x] documentar plano de handshake TTC (`doc/handshake_plan.md`).
- [x] portar constantes de CONNECT (GSO/NSI/protocol characteristics) (`lib/src/thin/protocol/constants.dart`).
- [x] montar CONNECT packet inicial e usar em `ThinConnection.connect()` com teste de handshake gated por `ORACLE_TESTS` (`lib/src/thin/connection.dart`, `test/integration/handshake_smoke_test.dart`).
- [x] adicionar plano de auth/login e teste de login/query placeholder (`doc/auth_plan.md`, `test/integration/login_query_test.dart`).
- [x] mapear plano de crypto para AUTH (CBC/PBKDF2 helpers) (`doc/crypto_plan.md`).
- [x] portar helpers de crypto (AES-CBC, PBKDF2) (`lib/src/thin/crypto.dart`, `pubspec.yaml`).
- [x] registrar status: auth TTC pendente e ERR_NOT_IMPLEMENTED em `ThinConnection.connect()` (`doc/status.md`).
- [x] adicionar padding zero e helpers hex para AUTH no crypto (`lib/src/thin/crypto.dart`).
- [x] parsear resposta AUTH em key/value para sessionData (AUTH_VFR_DATA, AUTH_SESSKEY, etc.).
- [x] ligar o parser base de mensagens ao transporte para AUTH (processBuffer/return params) e propagar metadata de sessao para `ThinConnection`.
- [x] montar o payload completo de AUTH TTC (phase1/phase2, PBKDF2 11g/12c, combo key) em `lib/src/thin/protocol/messages/auth.dart`.
- [ ] validar/auth TTC contra servidor XE real e ajustar verificador/sessao ate login funcionar.
- [ ] completar o parsing das mensagens base (warnings/piggybacks/row data/result sets) e amarrar ao transporte.
- [ ] expandir testes de integracao para login e queries simples (usar `ORACLE_TESTS=1`).
- [ ] exercitar login real contra o serviço `XEPDB1` com `dart_user/dart` (conexao mostrada no Navicat) e registrar sessionData para comparar com python-oracledb.
- [ ] remover os skips atuais de `test/integration/handshake_smoke_test.dart` e `test/integration/login_query_test.dart` assim que o fluxo de auth TTC permitir logons completos.

```
