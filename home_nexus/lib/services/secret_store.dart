import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Narrow secret-storage interface so tests inject an in-memory impl and
/// the backing plugin can change without touching callers.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// OS keychain/DPAPI-backed store. Falls back to process memory when the
/// platform channel is unavailable (unit tests, unsupported platforms) —
/// secrets are then session-only rather than silently plaintext-persisted.
class SecureSecretStore implements SecretStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _fallback = <String, String>{};
  bool _broken = false;

  // a hung platform channel must not stall app bootstrap forever
  static const _timeout = Duration(seconds: 5);

  @override
  Future<String?> read(String key) async {
    if (_broken) return _fallback[key];
    try {
      return await _storage.read(key: key).timeout(_timeout);
    } catch (_) {
      _broken = true;
      return _fallback[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (_broken) {
      _fallback[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value).timeout(_timeout);
    } catch (_) {
      _broken = true;
      _fallback[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _fallback.remove(key);
    if (_broken) return;
    try {
      await _storage.delete(key: key).timeout(_timeout);
    } catch (_) {
      _broken = true;
    }
  }
}

class InMemorySecretStore implements SecretStore {
  final _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}
