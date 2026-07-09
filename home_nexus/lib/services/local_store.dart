import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

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

  const BridgeConfig({required this.host, this.port = 8927});

  Map<String, dynamic> toJson() => {'host': host, 'port': port};

  factory BridgeConfig.fromJson(Map<String, dynamic> json) => BridgeConfig(
        host: json['host'] as String,
        port: json['port'] as int? ?? 8927,
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

  Future<void> saveMqttConfig(MqttConfig config) =>
      _prefs.setString(_mqttConfigKey, jsonEncode(config.toJson()));

  MqttConfig? loadMqttConfig() {
    final raw = _prefs.getString(_mqttConfigKey);
    if (raw == null) return null;
    return MqttConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> clearMqttConfig() => _prefs.remove(_mqttConfigKey);

  Future<void> saveBridgeConfig(BridgeConfig config) =>
      _prefs.setString(_bridgeConfigKey, jsonEncode(config.toJson()));

  BridgeConfig? loadBridgeConfig() {
    final raw = _prefs.getString(_bridgeConfigKey);
    if (raw == null) return null;
    return BridgeConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> clearBridgeConfig() => _prefs.remove(_bridgeConfigKey);

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
}
