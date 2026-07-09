import 'capability.dart';
import 'device_origin.dart';
import 'universal_device.dart';

/// Capability state maps already carry everything needed to rebuild them,
/// so serialization is just {type, state}.
Map<String, dynamic> capabilityToJson(Capability c) => {
      'type': c.type,
      'state': c.state,
    };

Capability capabilityFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  final s = (json['state'] as Map).cast<String, dynamic>();
  switch (type) {
    case CapabilityType.powerSwitch:
      return PowerSwitchCapability(on: s['on'] == true);
    case CapabilityType.brightness:
      return BrightnessCapability(level: (s['level'] as num?)?.toInt() ?? 0);
    case CapabilityType.colorRgb:
      return ColorRgbCapability(
        r: (s['r'] as num?)?.toInt() ?? 255,
        g: (s['g'] as num?)?.toInt() ?? 255,
        b: (s['b'] as num?)?.toInt() ?? 255,
      );
    case CapabilityType.colorTemperature:
      return ColorTemperatureCapability(
          mireds: (s['mireds'] as num?)?.toInt() ?? 300);
    case CapabilityType.targetTemperature:
      return TargetTemperatureCapability(
        target: s['target'] as num? ?? 21,
        min: s['min'] as num? ?? 7,
        max: s['max'] as num? ?? 35,
      );
    default:
      // Structural fallback covers all typed sensor/mode variants.
      if (s.containsKey('active')) {
        return BinarySensorCapability(type: type, active: s['active'] == true);
      }
      if (s.containsKey('mode')) {
        return ModeCapability(
          type: type,
          mode: s['mode'] as String? ?? '',
          options: (s['options'] as List?)?.cast<String>() ?? const [],
        );
      }
      return SensorCapability(
        type: type,
        value: s['value'] as num?,
        unit: s['unit'] as String? ?? '',
      );
  }
}

Map<String, dynamic> deviceToJson(UniversalDevice d) => {
      'id': d.id,
      'name': d.name,
      'manufacturer': d.manufacturer,
      'model': d.model,
      'origin': d.origin.toJson(),
      'roomId': d.roomId,
      'capabilities': [for (final c in d.capabilities) capabilityToJson(c)],
    };

UniversalDevice deviceFromJson(Map<String, dynamic> json) => UniversalDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      manufacturer: json['manufacturer'] as String? ?? '',
      model: json['model'] as String? ?? '',
      origin:
          DeviceOrigin.fromJson((json['origin'] as Map).cast<String, dynamic>()),
      roomId: json['roomId'] as String? ?? 'unassigned',
      capabilities: [
        for (final c in (json['capabilities'] as List))
          capabilityFromJson((c as Map).cast<String, dynamic>()),
      ],
    );
