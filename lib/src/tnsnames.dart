import 'dart:io';

import 'exceptions.dart';

/// Returns true if [dsn] looks like a net service name (alias) rather than
/// an Easy Connect string or a connect descriptor.
bool isTnsAlias(String dsn) =>
    dsn.isNotEmpty &&
    RegExp(r'^[A-Za-z0-9_.$#-]+$').hasMatch(dsn) &&
    !RegExp(r'^\d+(\.\d+){3}$').hasMatch(dsn) &&
    dsn != 'localhost';

/// Determines the directory holding `tnsnames.ora`.
String? tnsConfigDir([String? configDir]) {
  if (configDir != null) return configDir;
  final env = Platform.environment;
  final tnsAdmin = env['TNS_ADMIN'];
  if (tnsAdmin != null && tnsAdmin.isNotEmpty) return tnsAdmin;
  final oracleHome = env['ORACLE_HOME'];
  if (oracleHome != null && oracleHome.isNotEmpty) {
    return '$oracleHome${Platform.pathSeparator}network'
        '${Platform.pathSeparator}admin';
  }
  return null;
}

/// Looks up [alias] in the `tnsnames.ora` file of the configuration
/// directory and returns its connect descriptor. Returns null if [alias] is
/// not an alias that can be resolved and no configuration exists; throws if
/// the file exists but the alias is not defined.
String? resolveTnsAlias(String alias, {String? configDir}) {
  final dir = tnsConfigDir(configDir);
  if (dir == null) {
    if (configDir == null) return null;
    throw dpyError(ERR_NO_CONFIG_DIR);
  }
  final file = File('$dir${Platform.pathSeparator}tnsnames.ora');
  if (!file.existsSync()) {
    if (configDir == null && Platform.environment['TNS_ADMIN'] == null) {
      return null;
    }
    throw dpyError(ERR_MISSING_FILE, args: {'file_name': file.path});
  }
  final entries = parseTnsNames(file);
  final descriptor = entries[alias.toUpperCase()];
  if (descriptor == null) {
    throw dpyError(ERR_TNS_ENTRY_NOT_FOUND,
        args: {'name': alias, 'file_name': file.path});
  }
  return descriptor;
}

/// Parses a `tnsnames.ora` file (following IFILE directives) and returns
/// the descriptors keyed by upper case alias.
Map<String, String> parseTnsNames(File file, [Set<String>? visited]) {
  visited ??= <String>{};
  final entries = <String, String>{};
  if (!visited.add(file.absolute.path)) return entries;
  final text = file.readAsLinesSync().map((line) {
    final hash = line.indexOf('#');
    return hash >= 0 ? line.substring(0, hash) : line;
  }).join('\n');
  var pos = 0;
  final n = text.length;
  while (pos < n) {
    // read the names (comma separated) up to the equals sign
    final eq = text.indexOf('=', pos);
    if (eq < 0) break;
    final names = text
        .substring(pos, eq)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    pos = eq + 1;
    while (pos < n &&
        (text[pos] == ' ' ||
            text[pos] == '\t' ||
            text[pos] == '\n' ||
            text[pos] == '\r')) {
      pos++;
    }
    String value;
    if (pos < n && text[pos] == '(') {
      var depth = 0;
      final start = pos;
      while (pos < n) {
        final c = text[pos];
        if (c == '(') depth++;
        if (c == ')') {
          depth--;
          if (depth == 0) {
            pos++;
            break;
          }
        }
        pos++;
      }
      value = text.substring(start, pos);
    } else {
      final end = text.indexOf('\n', pos);
      value = text.substring(pos, end < 0 ? n : end).trim();
      pos = end < 0 ? n : end + 1;
    }
    value = value.replaceAll(RegExp(r'\s+'), '');
    for (final name in names) {
      final upper = name.toUpperCase();
      if (upper == 'IFILE') {
        var path = value.replaceAll('"', '');
        if (!File(path).isAbsolute) {
          path = '${file.parent.path}${Platform.pathSeparator}$path';
        }
        final included = File(path);
        if (included.existsSync()) {
          entries.addAll(parseTnsNames(included, visited));
        }
      } else {
        entries[upper] = value;
      }
    }
  }
  return entries;
}
