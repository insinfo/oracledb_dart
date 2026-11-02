import 'dart:collection';

import 'exceptions.dart';

/// The style of the bind placeholders used in SQL statements.
enum PlaceholderIdentifier {
  /// Oracle style placeholders: `:name` or `:1` (the default).
  colon,

  /// Question mark placeholders similar to PHP PDO / JDBC (`?`), bound by
  /// position with a [List] of values.
  onlyQuestionMark,
}

const int _maxCachedConversions = 256;
final LinkedHashMap<String, String> _conversionCache =
    LinkedHashMap<String, String>();

/// Converts the `?` placeholders of [sql] into Oracle positional placeholders
/// (`:1`, `:2`, ...). Question marks inside string literals, quoted
/// identifiers and comments are left untouched.
String convertQuestionMarks(String sql) {
  final cached = _conversionCache.remove(sql);
  if (cached != null) {
    _conversionCache[sql] = cached;
    return cached;
  }
  final converted = _convert(sql);
  _conversionCache[sql] = converted;
  if (_conversionCache.length > _maxCachedConversions) {
    _conversionCache.remove(_conversionCache.keys.first);
  }
  return converted;
}

String _convert(String sql) {
  final n = sql.length;
  if (!sql.contains('?')) return sql;
  final out = StringBuffer();
  var start = 0;
  var pos = 0;
  var index = 0;
  while (pos < n) {
    final ch = sql.codeUnitAt(pos);
    if (ch == 39) {
      // string literal, possibly a q-string: q'[...]'
      final prev = pos > 0 ? sql.codeUnitAt(pos - 1) : 0;
      if ((prev == 113 || prev == 81) && pos + 1 < n) {
        final open = sql.codeUnitAt(pos + 1);
        final close = switch (open) {
          91 => 93,
          123 => 125,
          60 => 62,
          40 => 41,
          _ => open,
        };
        final end = sql.indexOf('${String.fromCharCode(close)}\'', pos + 2);
        if (end < 0) throw dpyError(ERR_MISSING_ENDING_SINGLE_QUOTE);
        pos = end + 2;
      } else {
        pos = _skipQuoted(sql, pos, 39, ERR_MISSING_ENDING_SINGLE_QUOTE);
      }
    } else if (ch == 34) {
      pos = _skipQuoted(sql, pos, 34, ERR_MISSING_ENDING_DOUBLE_QUOTE);
    } else if (ch == 45 && pos + 1 < n && sql.codeUnitAt(pos + 1) == 45) {
      final end = sql.indexOf('\n', pos);
      pos = end < 0 ? n : end;
    } else if (ch == 47 && pos + 1 < n && sql.codeUnitAt(pos + 1) == 42) {
      final end = sql.indexOf('*/', pos + 2);
      pos = end < 0 ? n : end + 2;
    } else if (ch == 63) {
      out
        ..write(sql.substring(start, pos))
        ..write(':')
        ..write(++index);
      pos++;
      start = pos;
    } else {
      pos++;
    }
  }
  out.write(sql.substring(start));
  return out.toString();
}

int _skipQuoted(String sql, int pos, int quote, int errorNum) {
  // doubled quotes inside the literal are handled naturally: the closing
  // quote ends the literal and the next one starts a new literal
  final end = sql.indexOf(String.fromCharCode(quote), pos + 1);
  if (end < 0) throw dpyError(errorNum);
  return end + 1;
}

/// Converts [sql] according to [identifier].
String prepareSql(String sql, PlaceholderIdentifier identifier) =>
    identifier == PlaceholderIdentifier.onlyQuestionMark
        ? convertQuestionMarks(sql)
        : sql;
