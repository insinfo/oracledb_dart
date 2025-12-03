# Crypto helpers to port for TTC auth

Reference: `python-oracledb/src/oracledb/impl/thin/messages/auth.pyx` and its helper functions.

Functions to bring over:
- `encrypt_cbc` / `decrypt_cbc` (AES-CBC with zero/PKCS padding as used by auth)
- PBKDF2 key derivation (`get_derived_key`) for 12c/19c verifiers and combo keys
- SHA1/SHA512 hashing helpers (Dart `crypto` package)

Dependencies:
- Add `crypto` (Dart package) for AES and PBKDF2; or implement minimal AES via `pointycastle` if needed.
- Ensure deterministic big-endian byte handling for salts, session keys.

Usage in auth:
- `_generate_verifier`: uses PBKDF2, AES-CBC encrypt/decrypt, SHA1/SHA512.
- `_encrypt_passwords`: AES-CBC over password+salt with combo key.
- JDWP debug payload encryption (optional).

Plan:
1) Add crypto dependency (prefer `pointycastle` for AES + PBKDF2; `crypto` lacks AES).
2) Implement utility module `lib/src/thin/crypto.dart` exposing CBC encrypt/decrypt and PBKDF2.
3) Wire into `AuthMessage` for verifier generation and password encryption.
4) Add unit tests for the crypto helpers with known vectors.
