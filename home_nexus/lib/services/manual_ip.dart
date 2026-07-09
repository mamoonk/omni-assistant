import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:unification/unification.dart';

/// Template kinds for generic IP devices (§6.1).
enum ManualTemplate { switchDevice, dimmer, sensor }

/// User-authored config for one generic IP device.
class ManualIpConfig {
  final String id;
  final String name;
  final String roomId;
  final ManualTemplate template;
  final String ip;

  /// URL templates. Placeholders: {ip}, {value}.
  /// switch/dimmer: 'on', 'off'; dimmer also 'brightness'; sensor: 'poll'.
  final Map<String, String> urls;

  /// sensor: dot-path into the poll JSON, e.g. 'sensors.0.temperature'.
  final String valuePath;
  final String sensorType; // CapabilityType.* for sensors
  final String unit;
  final int pollSeconds;

  const ManualIpConfig({
    required this.id,
    required this.name,
    required this.roomId,
    required this.template,
    required this.ip,
    required this.urls,
    this.valuePath = '',
    this.sensorType = CapabilityType.currentTemperature,
    this.unit = '',
    this.pollSeconds = 30,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'roomId': roomId,
        'template': template.name,
        'ip': ip,
        'urls': urls,
        'valuePath': valuePath,
        'sensorType': sensorType,
        'unit': unit,
        'pollSeconds': pollSeconds,
      };

  factory ManualIpConfig.fromJson(Map<String, dynamic> json) => ManualIpConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        roomId: json['roomId'] as String? ?? 'unassigned',
        template: ManualTemplate.values.byName(json['template'] as String),
        ip: json['ip'] as String,
        urls: (json['urls'] as Map).cast<String, String>(),
        valuePath: json['valuePath'] as String? ?? '',
        sensorType:
            json['sensorType'] as String? ?? CapabilityType.currentTemperature,
        unit: json['unit'] as String? ?? '',
        pollSeconds: json['pollSeconds'] as int? ?? 30,
      );

  String get deviceId => 'manual:$id';

  /// Materializes the config into a dashboard device.
  UniversalDevice toDevice() {
    final capabilities = switch (template) {
      ManualTemplate.switchDevice => <Capability>[PowerSwitchCapability()],
      ManualTemplate.dimmer => <Capability>[
          PowerSwitchCapability(),
          BrightnessCapability(),
        ],
      ManualTemplate.sensor => <Capability>[
          SensorCapability(type: sensorType, unit: unit),
        ],
    };
    return UniversalDevice(
      id: deviceId,
      name: name,
      origin: DeviceOrigin(
        type: OriginType.manualIp,
        connectionId: 'local',
        nativeId: ip,
        protocol: 'wifi',
      ),
      capabilities: capabilities,
      roomId: roomId,
    );
  }

  String? urlFor(String key, {dynamic value}) {
    final template = urls[key];
    if (template == null || template.isEmpty) return null;
    return template
        .replaceAll('{ip}', ip)
        .replaceAll('{value}', '${value ?? ''}');
  }
}

/// Executes capability commands as HTTP GETs against the URL templates.
class ManualIpController implements DeviceController {
  final Map<String, ManualIpConfig> _configs; // deviceId -> config
  final HttpClient _http;

  ManualIpController(Iterable<ManualIpConfig> configs, {HttpClient? http})
      : _configs = {for (final c in configs) c.deviceId: c},
        _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 5));

  @override
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  ) async {
    final config = _configs[device.id];
    if (config == null) throw StateError('No config for ${device.id}');

    final url = switch (capabilityType) {
      CapabilityType.powerSwitch =>
        config.urlFor((value as bool) ? 'on' : 'off'),
      CapabilityType.brightness => config.urlFor('brightness', value: value),
      _ => null,
    };
    if (url == null) {
      throw UnsupportedError(
          'No URL template for $capabilityType on ${device.name}');
    }
    await _get(url);

    // optimistic local state; generic devices rarely push state back
    final cap = device.capabilityOfType(capabilityType);
    switch (cap) {
      case PowerSwitchCapability c:
        c.on = value as bool;
      case BrightnessCapability c:
        c.level = value as int;
      default:
        break;
    }
  }

  Future<String> _get(String url) async {
    final request = await _http.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} from $url');
    }
    return body;
  }

  /// One poll cycle for a sensor config: fetch, extract, return value.
  Future<num?> pollSensor(ManualIpConfig config) async {
    final url = config.urlFor('poll');
    if (url == null) return null;
    final body = await _get(url);
    final decoded = jsonDecode(body);
    final raw = extractPath(decoded, config.valuePath);
    return raw is num ? raw : num.tryParse('$raw');
  }
}

/// Walks a dot-path ('a.b.0.c') through decoded JSON. Empty path = root.
dynamic extractPath(dynamic json, String path) {
  if (path.isEmpty) return json;
  dynamic cursor = json;
  for (final part in path.split('.')) {
    if (cursor is Map) {
      cursor = cursor[part];
    } else if (cursor is List) {
      final i = int.tryParse(part);
      cursor = (i != null && i >= 0 && i < cursor.length) ? cursor[i] : null;
    } else {
      return null;
    }
  }
  return cursor;
}
