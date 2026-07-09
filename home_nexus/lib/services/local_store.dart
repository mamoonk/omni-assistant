import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

import 'secret_store.dart';

class MqttConfig {
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String baseTopic;

  const MqttConfig({
    required this.host,
    this.port = 1883,
    this.username,
    this.password,
    this.baseTopic = 'zigbee2mqtt',
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'baseTopic': baseTopic,
      };

  factory MqttConfig.fromJson(Map<String, dynamic> json) => MqttConfig(
        host: json['host'] as String,
        port: json['port'] as int? ?? 1883,
        username: json['username'] as String?,
        password: json['password'] as String?,
        baseTopic: json['baseTopic'] as String? ?? 'zigbee2mqtt',
      );
}

class BridgeConfig {
  final String host;
  final int port;
  final String token; // pairing token printed by the bridge on startup

  const BridgeConfig({required this.host, this.port = 8927, this.token = ''});

  Map<String, dynamic> toJson() =>
      {'host': host, 'port': port, 'token': token};

  factory BridgeConfig.fromJson(Map<String, dynamic> json) => BridgeConfig(
        host: json['host'] as String,
        port: json['port'] as int? ?? 8927,
        token: json['token'] as String? ?? '',
      );
}

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
  static const _mqttConfigKey = 'mqtt_config';
  static const _bridgeConfigKey = 'bridge_config';
  static const _devicesKey = 'device_cache';
  static const _scenesKey = 'scenes';
  static const _layoutKey = 'layout';
  static const _manualDevicesKey = 'manual_devices';
  static const _automationsKey = 'automations';
  static const _themeModeKey = 'theme_mode';

  final SharedPreferences _prefs;
  final SecretStore _secrets;
  LocalStore(this._prefs, this._secrets);

  /// Connection configs carry credentials -> secret store. A legacy
  /// plaintext copy in prefs is migrated on first read, then removed.
  Future<String?> _readSecret(String key) async {
    final secret = await _secrets.read(key);
    if (secret != null) return secret;
    final legacy = _prefs.getString(key);
    if (legacy != null) {
      await _secrets.write(key, legacy);
      await _prefs.remove(key);
    }
    return legacy;
  }

  Future<void> saveConfig(HaConfig config) =>
      _secrets.write(_configKey, jsonEncode(config.toJson()));

  Future<HaConfig?> loadConfig() async {
    final raw = await _readSecret(_configKey);
    if (raw == null) return null;
    return HaConfig.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> clearConfig() => _secrets.delete(_configKey);

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

  Future<void> saveMqttConfig(MqttConfig config) =>
      _secrets.write(_mqttConfigKey, jsonEncode(config.toJson()));

  Future<MqttConfig?> loadMqttConfig() async {
    final raw = await _readSecret(_mqttConfigKey);
    if (raw == null) return null;
    return MqttConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> clearMqttConfig() => _secrets.delete(_mqttConfigKey);

  Future<void> saveBridgeConfig(BridgeConfig config) =>
      _secrets.write(_bridgeConfigKey, jsonEncode(config.toJson()));

  Future<BridgeConfig?> loadBridgeConfig() async {
    final raw = await _readSecret(_bridgeConfigKey);
    if (raw == null) return null;
    return BridgeConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> clearBridgeConfig() => _secrets.delete(_bridgeConfigKey);

  Future<void> saveScenesJson(String json) => _prefs.setString(_scenesKey, json);
  String? loadScenesJson() => _prefs.getString(_scenesKey);

  Future<void> saveLayoutJson(String json) => _prefs.setString(_layoutKey, json);
  String? loadLayoutJson() => _prefs.getString(_layoutKey);

  Future<void> saveManualDevicesJson(String json) =>
      _prefs.setString(_manualDevicesKey, json);
  String? loadManualDevicesJson() => _prefs.getString(_manualDevicesKey);

  Future<void> saveAutomationsJson(String json) =>
      _prefs.setString(_automationsKey, json);
  String? loadAutomationsJson() => _prefs.getString(_automationsKey);

  Future<void> saveThemeMode(String mode) =>
      _prefs.setString(_themeModeKey, mode);
  String? loadThemeMode() => _prefs.getString(_themeModeKey);

  Future<void> saveHomeLocation(double lat, double lon) async {
    await _prefs.setDouble('home_lat', lat);
    await _prefs.setDouble('home_lon', lon);
  }

  ({double lat, double lon})? loadHomeLocation() {
    final lat = _prefs.getDouble('home_lat');
    final lon = _prefs.getDouble('home_lon');
    if (lat == null || lon == null) return null;
    return (lat: lat, lon: lon);
  }
}
