# Status
- CONNECT/ACCEPT implementado; AUTH em duas fases com parse de key/value básico já grava `sessionData` (AUTH_VFR_DATA, AUTH_SESSKEY, etc.) e envia pacotes DATA.
- Verificador 11g/12c/19c gerado localmente, mas ainda sem validação em servidor real; parsing TTC completo e setup de sessão permanecem pendentes.
- Testes de integração de login/query seguem pulados até concluir TTC auth/session.
- Criptografia (AES-CBC com padding configurável, PBKDF2) disponível em `lib/src/thin/crypto.dart`.
