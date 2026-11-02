// Extension points used to customize how connections are established, for
// example by cloud configuration providers or token authentication plugins.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'connect_params.dart';
import 'exceptions.dart';

/// Called with the parameters of every connection (and pool) before it is
/// established; returns the parameters to use (for example with an access
/// token acquired from a cloud identity provider).
typedef ParamsHook = FutureOr<ConnectParams> Function(ConnectParams params);

/// Resolves a connect string of the form `protocol://argument`; [params]
/// holds the other parameters supplied by the application.
typedef ProtocolHook = FutureOr<ConnectParams> Function(
    String protocol, String argument, ConnectParams params);

/// Returns the password described by [args] (which contains at least the key
/// `type`), for example by reading it from a secret vault.
typedef PasswordTypeHook = FutureOr<String> Function(Map<String, Object?> args);

final List<ParamsHook> _paramsHooks = [];
final Map<String, ProtocolHook> _protocolHooks = {
  'config-file': _configFileHook,
};
final Map<String, PasswordTypeHook> _passwordTypeHooks = {
  'base64': (args) => utf8.decode(base64.decode(args['value'] as String)),
};

/// Registers a hook called before every connection is established. Hooks
/// are invoked in order of registration.
void registerParamsHook(ParamsHook hook) => _paramsHooks.add(hook);

void unregisterParamsHook(ParamsHook hook) => _paramsHooks.remove(hook);

/// Registers (or, with a null [hook], removes) the handler of connect
/// strings starting with `protocol://`.
void registerProtocol(String protocol, ProtocolHook? hook) {
  final key = protocol.toLowerCase();
  if (hook == null) {
    _protocolHooks.remove(key);
  } else {
    _protocolHooks[key] = hook;
  }
}

/// Registers (or, with a null [hook], removes) the handler of passwords
/// given as a map with the key `type` set to [type].
void registerPasswordType(String type, PasswordTypeHook? hook) {
  final key = type.toLowerCase();
  if (hook == null) {
    _passwordTypeHooks.remove(key);
  } else {
    _passwordTypeHooks[key] = hook;
  }
}

/// Returns the hook registered for the protocol of [dsn], if it uses one.
(ProtocolHook, String, String)? protocolHookFor(String dsn) {
  final idx = dsn.indexOf('://');
  if (idx <= 0) return null;
  final protocol = dsn.substring(0, idx).toLowerCase();
  if (protocol == 'tcp' || protocol == 'tcps') return null;
  final hook = _protocolHooks[protocol];
  if (hook == null) {
    throw dpyError(ERR_FEATURE_NOT_SUPPORTED,
        args: {'feature': 'protocol $protocol', 'driver_type': 'thick'});
  }
  return (hook, protocol, dsn.substring(idx + 3));
}

/// Resolves a password supplied either as a string or as a map handled by a
/// registered password type hook.
Future<String?> resolvePassword(Object? password) async {
  if (password == null || password is String) return password as String?;
  if (password is Map) {
    final args = password.cast<String, Object?>();
    final type = (args['type'] as String?)?.toLowerCase();
    final hook = type == null ? null : _passwordTypeHooks[type];
    if (hook == null) {
      throw dpyError(ERR_INVALID_PASSWORD_TYPE, args: {'password_type': type});
    }
    try {
      return await hook(args);
    } catch (e) {
      throw dpyError(ERR_PASSWORD_TYPE_HANDLER_FAILED,
          args: {'password_type': type}, message: '$e', cause: e);
    }
  }
  throw dpyError(ERR_INVALID_PASSWORD_TYPE,
      args: {'password_type': password.runtimeType});
}

/// Applies the registered parameter hooks.
Future<ConnectParams> applyParamsHooks(ConnectParams params) async {
  for (final hook in List.of(_paramsHooks)) {
    try {
      params = await hook(params);
    } catch (e) {
      throw dpyError(ERR_PARAMS_HOOK_HANDLER_FAILED, message: '$e', cause: e);
    }
  }
  return params;
}

/// Applies a configuration (as returned by a configuration provider) to
/// [params]: `connect_descriptor`, `user` and `password` (a string or a map
/// handled by a password type hook).
Future<ConnectParams> applyConfig(
    Map<String, Object?> config, ConnectParams params) async {
  final descriptor = config['connect_descriptor'];
  if (descriptor is! String) throw dpyError(ERR_MISSING_CONNECT_DESCRIPTOR);
  final user = config['user'] as String? ?? params.user;
  var password = params.password;
  if (config.containsKey('password')) {
    password = await resolvePassword(config['password']);
  }
  return params.withConnectString(descriptor, user: user, password: password);
}

/// Handles `config-file://<file name>[?key=<key>]`: the file contains a JSON
/// configuration (or a map of configurations selected by `key`). Relative
/// file names are resolved against the `TNS_ADMIN` directory.
Future<ConnectParams> _configFileHook(
    String protocol, String argument, ConnectParams params) async {
  var fileName = argument;
  String? key;
  final pos = argument.indexOf('?');
  if (pos >= 0) {
    fileName = argument.substring(0, pos);
    key = Uri.splitQueryString(argument.substring(pos + 1))['key'];
  }
  var file = File(fileName);
  if (!file.isAbsolute) {
    final dir = Platform.environment['TNS_ADMIN'];
    if (dir == null) throw dpyError(ERR_NO_CONFIG_DIR);
    file = File('$dir${Platform.pathSeparator}$fileName');
  }
  if (!file.existsSync()) {
    throw dpyError(ERR_MISSING_FILE, args: {'file_name': file.path});
  }
  var config = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  if (key != null) config = config[key] as Map<String, Object?>;
  return applyConfig(config, params);
}
