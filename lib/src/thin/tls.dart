import 'dart:convert';
import 'dart:io';

import '../connect_params.dart';
import '../exceptions.dart';

const String pemWalletFileName = 'ewallet.pem';

/// TLS settings used to secure the transport.
class TlsConfig {
  TlsConfig(this.context, this.host, this.dnMatch, this.certDn);

  /// Builds the settings from the connection parameters.
  factory TlsConfig.fromParams(ConnectParams params, String host) => TlsConfig(
      params.securityContext ?? _buildContext(params),
      host,
      params.sslServerDnMatch,
      params.sslServerCertDn);

  final SecurityContext context;

  /// The host name the server certificate is verified against (and sent as
  /// the server name indication).
  final String host;
  final bool dnMatch;
  final String? certDn;

  /// Called when the server certificate cannot be verified. Verification is
  /// only bypassed when server DN matching has been explicitly disabled.
  bool onBadCertificate(X509Certificate certificate) => !dnMatch;

  /// Checks the distinguished name of the server certificate, if one was
  /// specified.
  void checkPeer(X509Certificate? certificate) {
    final expected = certDn;
    if (!dnMatch || expected == null) return;
    if (certificate == null ||
        !distinguishedNamesMatch(certificate.subject, expected)) {
      throw dpyError(ERR_INVALID_SERVER_CERT_DN,
          args: {'expected_dn': expected});
    }
  }

  static SecurityContext _buildContext(ConnectParams params) {
    final context = SecurityContext(withTrustedRoots: true);
    final location = params.walletLocation;
    if (location == null) return context;
    final file = File('$location${Platform.pathSeparator}$pemWalletFileName');
    if (!file.existsSync()) {
      throw dpyError(ERR_WALLET_FILE_MISSING, args: {'name': file.path});
    }
    final blocks = _pemBlocks(file.readAsStringSync());
    final certs =
        blocks.where((b) => b.contains('BEGIN CERTIFICATE')).join('\n');
    final keys = blocks.where((b) => b.contains('PRIVATE KEY')).toList();
    if (certs.isNotEmpty) {
      context.setTrustedCertificatesBytes(utf8.encode(certs));
    }
    if (keys.isNotEmpty && certs.isNotEmpty) {
      // mutual TLS: the wallet also holds the client certificate and key
      context.useCertificateChainBytes(utf8.encode(certs));
      context.usePrivateKeyBytes(utf8.encode(keys.first),
          password: params.walletPassword);
    }
    return context;
  }

  static List<String> _pemBlocks(String text) => [
        for (final m
            in RegExp(r'-----BEGIN ([A-Z ]+)-----[\s\S]*?-----END \1-----')
                .allMatches(text))
          m.group(0)!
      ];
}

/// Parses a distinguished name in either the RFC 4514 form used in connect
/// strings (`CN=x, O=y`) or the OpenSSL one-line form (`/O=y/CN=x`).
Map<String, String> parseDistinguishedName(String dn) {
  final result = <String, String>{};
  final text = dn.trim();
  final parts = <String>[];
  if (text.startsWith('/')) {
    parts.addAll(text.substring(1).split('/'));
  } else {
    var current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        parts.add(current.toString());
        current = StringBuffer();
        continue;
      }
      current.write(c);
    }
    parts.add(current.toString());
  }
  for (final part in parts) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final key = part.substring(0, eq).trim().toUpperCase();
    var value = part.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).replaceAll('""', '"');
    }
    result[key] = value;
  }
  return result;
}

bool distinguishedNamesMatch(String actual, String expected) {
  final a = parseDistinguishedName(actual);
  final e = parseDistinguishedName(expected);
  if (a.length != e.length) return false;
  for (final entry in e.entries) {
    if (a[entry.key] != entry.value) return false;
  }
  return true;
}
