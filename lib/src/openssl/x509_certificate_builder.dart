import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:oracledb_dart/src/openssl/libcrypto_ff.dart';
import 'package:oracledb_dart/src/openssl/openssl_ffi.dart';

/// Constantes – os valores abaixo devem corresponder aos valores definidos na sua binding.
const int OSSL_PARAM_UNSIGNED_INTEGER = 1;
const int EVP_PKEY_KEYPAIR = 1; // Seleção para criação de par de chaves

/// Funções auxiliares para construir os parâmetros OSSL_PARAM para chave RSA.
Pointer<OSSL_PARAM> constructParams(int bits, int pubexp) {
  // Alocamos um array com 3 parâmetros: "rsa_bits", "rsa_pubexp" e o marcador de fim.
  const paramCount = 3;
  final params = calloc<OSSL_PARAM>(paramCount);

  // Primeiro parâmetro: "rsa_bits"
  final keyBits = "rsa_bits".toNativeUtf8();
  params[0].key = keyBits.cast<Int8>();
  params[0].data_type = OSSL_PARAM_UNSIGNED_INTEGER;
  // Aloca memória para armazenar o valor dos bits (uint32)
  final bitsPtr = calloc<Uint32>();
  bitsPtr.value = bits;
  params[0].data = bitsPtr.cast<Void>();
  params[0].data_size = sizeOf<Uint32>();

  // Segundo parâmetro: "rsa_pubexp"
  final keyPubexp = "rsa_pubexp".toNativeUtf8();
  params[1].key = keyPubexp.cast<Int8>();
  params[1].data_type = OSSL_PARAM_UNSIGNED_INTEGER;
  final pubexpPtr = calloc<Uint32>();
  pubexpPtr.value = pubexp;
  params[1].data = pubexpPtr.cast<Void>();
  params[1].data_size = sizeOf<Uint32>();

  // Terceiro parâmetro: marca o fim (key == nullptr)
  params[2].key = nullptr;

  return params;
}

void freeParams(Pointer<OSSL_PARAM> params) {
  // Libera as strings e os dados alocados para os parâmetros
  if (params[0].key != nullptr) {
    calloc.free(params[0].key);
    calloc.free(params[0].data);
  }
  if (params[1].key != nullptr) {
    calloc.free(params[1].key);
    calloc.free(params[1].data);
  }
  calloc.free(params);
}

/// Classe auxiliar para criar certificado autoassinado usando as novas APIs.
class X509CertificateBuilder {
  final OpenSslCrypto libcrypt;
  final OpenSsl openSsl;
  X509CertificateBuilder(this.libcrypt, this.openSsl);

  /// Gera um par de chaves RSA e retorna um ponteiro para EVP_PKEY utilizando EVP_PKEY_fromdata.
  Pointer<EVP_PKEY> generateKeyPair() {
    // Cria o contexto para geração da chave RSA.

    final ctx = libcrypt.EVP_PKEY_FROMDATA_CTX_new_id(EVP_PKEY_RSA, nullptr);
    if (ctx == nullptr) {
      throw Exception('Falha ao criar EVP_PKEY_FROMDATA_CTX');
    }

    if (libcrypt.EVP_PKEY_fromdata_init(ctx) != 1) {
      libcrypt.EVP_PKEY_FROMDATA_CTX_free(ctx);
      throw Exception('Falha ao inicializar EVP_PKEY_fromdata');
    }

    // Prepara os parâmetros para a chave RSA: 2048 bits e expoente 65537.
    final params = constructParams(2048, 65537);

    // Aloca um ponteiro para receber o EVP_PKEY criado.
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
    final ret =
        libcrypt.EVP_PKEY_fromdata(ctx, pkeyPtr, EVP_PKEY_KEYPAIR, params);
    // Libera os parâmetros (eles já foram utilizados internamente).
    freeParams(params);

    if (ret != 1) {
      calloc.free(pkeyPtr);
      libcrypt.EVP_PKEY_FROMDATA_CTX_free(ctx);
      throw Exception('EVP_PKEY_fromdata falhou');
    }

    final pkey = pkeyPtr.value;
    calloc.free(pkeyPtr);
    libcrypt.EVP_PKEY_FROMDATA_CTX_free(ctx);
    return pkey;
  }

  /// Cria um certificado X509 autoassinado com validade em [validityDays] dias.
  Pointer<x509_st> createSelfSignedCertificate(Pointer<EVP_PKEY> key,
      {int validityDays = 365}) {
    final cert = libcrypt.X509_new();
    if (cert == nullptr) {
      throw Exception('Falha ao criar X509');
    }
    // Define a versão para X509v3 (valor 2).
    libcrypt.X509_set_version(cert, 2);

    // Define o número de série.
    final serial = libcrypt.ASN1_INTEGER_new();
    if (serial == nullptr) {
      throw Exception('Falha ao criar ASN1_INTEGER');
    }
    libcrypt.ASN1_INTEGER_set(serial, 1);
    libcrypt.X509_set_serialNumber(cert, serial);

    // Define o período de validade.
    libcrypt.X509_gmtime_adj(libcrypt.X509_get_notBefore(cert), 0);
    libcrypt.X509_gmtime_adj(
        libcrypt.X509_get_notAfter(cert), validityDays * 24 * 3600);

    // Cria um nome para emissor e sujeito (no caso autoassinado, são iguais).
    final name = libcrypt.X509_NAME_new();
    if (name == nullptr) {
      throw Exception('Falha ao criar X509_NAME');
    }
    const int MBSTRING_ASC = 0; // Valor para ASCII.
    final cnKey = 'CN'.toNativeUtf8();
    final cnValue = 'SelfSignedCert'.toNativeUtf8();
    final ret = libcrypt.X509_NAME_add_entry_by_txt(
        name, cnKey.cast(), MBSTRING_ASC, cnValue.cast(), -1, -1, 0);
    calloc.free(cnKey);
    calloc.free(cnValue);
    if (ret != 1) {
      throw Exception('X509_NAME_add_entry_by_txt falhou');
    }
    libcrypt.X509_set_issuer_name(cert, name);
    libcrypt.X509_set_subject_name(cert, name);

    // Associa a chave pública.
    libcrypt.X509_set_pubkey(cert, key);

    // Assina o certificado com a chave privada usando SHA256.
    final signRet = libcrypt.X509_sign(cert, key, libcrypt.EVP_sha256());
    if (signRet <= 0) {
      throw Exception('X509_sign falhou');
    }
    return cert;
  }

  /// Converte o certificado X509 para uma String no formato PEM.
  String x509ToPem(Pointer<x509_st> cert) {
    final bio = openSsl.BIO_new(openSsl.BIO_s_mem());
    if (bio == nullptr) {
      throw Exception('Falha ao criar BIO');
    }
    final ret = libcrypt.PEM_write_bio_X509(bio, cert);
    if (ret != 1) {
      throw Exception('PEM_write_bio_X509 falhou');
    }
    // Obtém os dados do BIO.
    final outPtr = calloc<Pointer<Utf8>>();
    // Usamos o comando 0x31 para obter o ponteiro de memória do BIO.
    openSsl.BIO_ctrl(bio, 0x31, 0, outPtr.cast());
    final pem = outPtr.value.toDartString();
    calloc.free(outPtr);
    libcrypt.BIO_free_all(bio);
    return pem;
  }

  /// Converte a chave privada para uma String no formato PEM.
  String privateKeyToPem(Pointer<EVP_PKEY> key) {
    final bio = openSsl.BIO_new(openSsl.BIO_s_mem());
    if (bio == nullptr) {
      throw Exception('Falha ao criar BIO');
    }
    final ret = libcrypt.PEM_write_bio_PrivateKey(
        bio, key, nullptr, nullptr, 0, nullptr, nullptr);
    if (ret != 1) {
      throw Exception('PEM_write_bio_PrivateKey falhou');
    }
    final outPtr = calloc<Pointer<Utf8>>();
    openSsl.BIO_ctrl(bio, 0x31, 0, outPtr.cast());
    final pem = outPtr.value.toDartString();
    calloc.free(outPtr);
    libcrypt.BIO_free_all(bio);
    return pem;
  }
}
