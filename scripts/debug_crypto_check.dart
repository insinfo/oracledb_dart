import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// ============================================================================
// DADOS COPIADOS DO SEU LOG PYTHON (GROUND TRUTH)
// ============================================================================
const String inputPassword = "dart";
const String logVfrData = "FC7FA8D9C4A198F9A02D34EFDCEEB400";
const String logServerSessKey = "DD09C1AF786F9C747AC6EF56B72AF5895CB8006B229B1A916673BDC94C5B6983";

// Valores esperados (calculados pelo Python):
const String expectedPasswordKey = "19AD22BE4AE8C25FAA33E9DA7A5FB67E12B8BFDA51B331BF64746E791F687FFFC6C53B45C88CC58DD8AED319992069A2C52744C9568C63C597941D460A52D95C";
const String expectedPasswordHash = "6DB2092FA972C27100D0D571246CABD7682DB012C90DFFE335B6DF5B47697736";
const String expectedSessionKeyPartA = "04A86E1DC56921494B1475B70FE55CDB4A0D58E340DC905D783993E1760B6155";
const String expectedEncodedClientKey = "6D780B2C383D98B4B6F0F05DA1415F4782085B38C5DD24B30D9C6C65B11167741E069CFDADCAC27D7D14351E36ABAA67";
const String expectedComboKey = "62E969956B4B6F315BE88DB57D8D952BB0B39965C6D6FFA5A9A1989C8ADFEBDA";
const String expectedEncryptedPassword = "6BAFF3284826A11214BF6CA7FD68747B0EFC6340DFAA359758E38E353CFB3A65";

// Valores Aleatórios gerados pelo Python (temos que forçar o Dart a usar os mesmos para comparar)
const String forcedSessionKeyPartB = "E012289797C083F3766CBDD2B1CBC400C44E01909C7E9BBA1D3603A76DC8E211";
const String forcedPasswordSalt = "D0911298A10B410DF200AC3170BB802D";

// Salt PBKDF2 (Não estava no log explícito, mas é necessário para o passo do ComboKey).
// Se falhar aqui, sabemos que o problema é o SALT do CSK que não temos no log.
// Porém, podemos testar a criptografia final usando a ComboKey DO PYTHON para isolar o problema.
// Tentei deduzir de logs anteriores, mas varia. Vamos pular a validação da geração
// da ComboKey se não tivermos o salt, e focar na criptografia final.

// ============================================================================
// FUNÇÕES DE AJUDA (CÓPIA SIMPLIFICADA DO SEU CRYPTO.DART)
// ============================================================================
Uint8List hexToBytes(String hex) {
  hex = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (hex.length % 2 != 0) hex = '0$hex';
  final len = hex.length ~/ 2;
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Uint8List concat(List<Uint8List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}

Uint8List pbkdf2Sha512(Uint8List password, Uint8List salt, int iterations, int keyLength) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA512Digest(), 128))
    ..init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(password);
}

Uint8List sha512Bytes(Uint8List data) => SHA512Digest().process(data);

Uint8List aesCbcDecrypt(Uint8List key, Uint8List ciphertext) {
  final engine = AESEngine();
  final cbc = CBCBlockCipher(engine)
    ..init(false, ParametersWithIV(KeyParameter(key), Uint8List(16))); // IV Zero
  
  final out = Uint8List(ciphertext.length);
  var offset = 0;
  while (offset < ciphertext.length) {
    offset += cbc.processBlock(ciphertext, offset, out, offset);
  }
  return out;
}

Uint8List aesCbcEncrypt(Uint8List key, Uint8List plaintext) {
  // Padding manual PKCS7 para garantir alinhamento com Python
  final blockSize = 16;
  final padLen = blockSize - (plaintext.length % blockSize);
  final padded = Uint8List(plaintext.length + padLen);
  padded.setRange(0, plaintext.length, plaintext);
  for (var i = plaintext.length; i < padded.length; i++) {
    padded[i] = padLen;
  }

  final engine = AESEngine();
  final cbc = CBCBlockCipher(engine)
    ..init(true, ParametersWithIV(KeyParameter(key), Uint8List(16))); // IV Zero
  
  final out = Uint8List(padded.length);
  var offset = 0;
  while (offset < padded.length) {
    offset += cbc.processBlock(padded, offset, out, offset);
  }
  return out;
}

// ============================================================================
// TESTE PRINCIPAL
// ============================================================================
void main() {
  print("=== INICIANDO DIAGNÓSTICO DE CRIPTOGRAFIA DART vs PYTHON ===");
  
  final passwordBytes = Uint8List.fromList(utf8.encode(inputPassword));
  final vfrData = hexToBytes(logVfrData);
  
  // ---------------------------------------------------------
  // 1. Gerar Password Key (PBKDF2)
  // ---------------------------------------------------------
  final authSpeedyKey = Uint8List.fromList("AUTH_PBKDF2_SPEEDY_KEY".codeUnits);
  final salt1 = concat([vfrData, authSpeedyKey]);
  
  // Nota: Iterations é 4096 (padrão 12c) baseado no log anterior, embora não impresso neste.
  // Se falhar, pode ser esse número.
  final dartPasswordKey = pbkdf2Sha512(passwordBytes, salt1, 4096, 64);
  final dartPasswordKeyHex = bytesToHex(dartPasswordKey);
  
  print("\n[1] Password Key Check:");
  print("    Dart:   $dartPasswordKeyHex");
  print("    Python: $expectedPasswordKey");
  print("    MATCH:  ${dartPasswordKeyHex == expectedPasswordKey}");

  // ---------------------------------------------------------
  // 2. Gerar Password Hash (SHA512)
  // ---------------------------------------------------------
  // Python: password_key (64 bytes) + verifier_data -> SHA512 -> Truncate to 32 bytes
  final hashInput = concat([dartPasswordKey, vfrData]);
  final fullHash = sha512Bytes(hashInput);
  final dartPasswordHash = fullHash.sublist(0, 32); // Truncate 32
  final dartPasswordHashHex = bytesToHex(dartPasswordHash);

  print("\n[2] Password Hash Check:");
  print("    Dart:   $dartPasswordHashHex");
  print("    Python: $expectedPasswordHash");
  print("    MATCH:  ${dartPasswordHashHex == expectedPasswordHash}");
  
  // Se falhou aqui, pare.
  if (dartPasswordHashHex != expectedPasswordHash) {
    print("CRÍTICO: Erro na geração do hash da senha. Verifique iterações ou lógica SHA.");
    return;
  }

  // ---------------------------------------------------------
  // 3. Descriptografar Chave do Servidor (Parte A)
  // ---------------------------------------------------------
  final serverSessKeyBytes = hexToBytes(logServerSessKey);
  // Python usa decrypt_cbc puro (sem unpad automático no meio da lógica as vezes, mas aqui é chave).
  // As chaves 12c geralmente são 32, 48 ou 64 bytes.
  final dartPartA = aesCbcDecrypt(dartPasswordHash, serverSessKeyBytes);
  
  // Python faz um slice [:32] em alguns casos se a chave for 32 bytes mas vier com padding.
  // No log Python: session_key_part_a (Decrypted): 04A86E... (32 bytes)
  // O input era 48 bytes (DD09... -> 96 chars / 2 = 48 bytes).
  // Então o AES decriptou 48 bytes. Os primeiros 32 são a chave.
  final dartPartATrunc = dartPartA.sublist(0, 32);
  final dartPartAHex = bytesToHex(dartPartATrunc);

  print("\n[3] Session Key Part A (Decrypted) Check:");
  print("    Dart:   $dartPartAHex");
  print("    Python: $expectedSessionKeyPartA");
  print("    MATCH:  ${dartPartAHex == expectedSessionKeyPartA}");

  // ---------------------------------------------------------
  // 4. Criptografar Chave do Cliente (Parte B)
  // ---------------------------------------------------------
  // Aqui usamos a chave "aleatória" que o Python gerou para ver se nossa criptografia bate
  final partBBytes = hexToBytes(forcedSessionKeyPartB);
  
  // Python encrypt_cbc adiciona padding.
  // PartB é 32 bytes. AES block é 16. 32 % 16 == 0.
  // Padding PKCS7 adiciona um bloco cheio de 16s (0x10) ou o Python driver faz manual?
  // O log Python mostra: encoded_client_key (To Send): 6D78... (48 bytes).
  // 32 bytes input -> 48 bytes output significa que houve padding de 16 bytes.
  
  final dartEncodedClientKey = aesCbcEncrypt(dartPasswordHash, partBBytes);
  final dartEncodedClientKeyHex = bytesToHex(dartEncodedClientKey);

  print("\n[4] Encoded Client Key (Part B) Check:");
  print("    Dart:   $dartEncodedClientKeyHex");
  print("    Python: $expectedEncodedClientKey");
  print("    MATCH:  ${dartEncodedClientKeyHex == expectedEncodedClientKey}");

  // ---------------------------------------------------------
  // 5. Validação Final da Senha (O Pulo do Gato)
  // ---------------------------------------------------------
  // Como não temos o SALT do ComboKey neste log específico, vamos testar
  // se o algoritmo de encriptação final está correto USANDO A COMBO KEY DO PYTHON.
  // Se isso funcionar, sua lógica AES final está certa, e o erro é só na geração da ComboKey (falta de salt).
  
  final pythonComboKey = hexToBytes(expectedComboKey);
  final pwdSalt = hexToBytes(forcedPasswordSalt);
  final pwdClean = Uint8List.fromList(utf8.encode(inputPassword));
  
  final payload = concat([pwdSalt, pwdClean]);
  final dartFinalEncrypted = aesCbcEncrypt(pythonComboKey, payload);
  final dartFinalHex = bytesToHex(dartFinalEncrypted);
  
  print("\n[5] Final Password Encryption Check (Using Python's ComboKey):");
  print("    Dart:   $dartFinalHex");
  print("    Python: $expectedEncryptedPassword");
  print("    MATCH:  ${dartFinalHex == expectedEncryptedPassword}");

  if (dartFinalHex == expectedEncryptedPassword) {
    print("\nCONCLUSÃO: Sua lógica de criptografia AES e Hash está PERFEITA.");
    print("O problema é apenas garantir que você pegue o SALT correto (AUTH_PBKDF2_CSK_SALT)");
    print("para gerar a ComboKey correta no Dart.");
  } else {
    print("\nCONCLUSÃO: Há uma diferença na forma como o Padding ou AES é aplicado na etapa final.");
  }
}