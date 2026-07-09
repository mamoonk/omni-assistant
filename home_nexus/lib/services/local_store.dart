import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

class HaConfig {
  final String url;
  final String token;
  const HaConfig({required this.url, required this.token});

  Map<String, dynamic> toJson() => {'url': url, 'token': token};

  factory HaConfig.fromJson(Map<String, dynamic> json) =>
      HaConfig(url: json['url'] as String, token: json['token'] as String);
}

/// Local persistence for connection config and the device cache so the
/// dashboard renders instantly offline on cold start.
/// Interface kept narrow so the backing store can move to Isar/Drift later.
class LocalStore {
  static const _configKey = 'ha_config';
  static const _devicesKey = 'device_cache';

  final SharedPreferences _prefs;
  LocalStore(this._prefs);

  Future<void> saveConfig(HaConfig config) =>
      _prefs.setString(_configKey, jsonEncode(config.toJson()));

  HaConfig? loadConfig() {
    final raw = _prefs.getString(_configKey);
    if (raw == null) return null;
    return HaConfig.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> clearConfig() => _prefs.remove(_configKey);

  Future<void> saveDevices(List<UniversalDevice> devices) => _prefs.setString(
      _devicesKey, jsonEncode([for (final d in devices) deviceToJson(d)]));

  List<UniversalDevice> loadDevices() {
    final raw = _prefs.getString(_devicesKey);
    if (raw == null) return const [];
    return [
      for (final d in (jsonDecode(raw) as List))
        deviceFromJson((d as Map).cast<String, dynamic>()),
    ];
  }

  Future<void> clearDevices() => _prefs.remove(_devicesKey);
}
