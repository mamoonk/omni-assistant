import 'package:unification/unification.dart';

/// Converts a Home Assistant entity state object into a UniversalDevice.
/// Returns null for domains we don't map yet.
UniversalDevice? mapHaEntity(
  Map<String, dynamic> entity, {
  required String connectionId,
  String roomId = 'unassigned',
}) {
  final entityId = entity['entity_id'] as String;
  final domain = entityId.split('.').first;
  final attrs = (entity['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
  final state = entity['state'] as String? ?? 'unknown';
  final capabilities = <Capability>[];

  switch (domain) {
    case 'light':
      capabilities.add(PowerSwitchCapability(on: state == 'on'));
      final modes =
          (attrs['supported_color_modes'] as List?)?.cast<String>() ?? const [];
      final dimmable = modes.any((m) => m != 'onoff');
      if (dimmable) {
        final raw = attrs['brightness'];
        capabilities.add(BrightnessCapability(
          level: raw is num ? (raw / 255 * 100).round() : 0,
        ));
      }
      if (modes.contains('color_temp')) {
        capabilities.add(ColorTemperatureCapability(
          mireds: (attrs['color_temp'] as num?)?.toInt() ?? 300,
        ));
      }
      if (modes.any((m) => const {'xy', 'hs', 'rgb', 'rgbw', 'rgbww'}.contains(m))) {
        final rgb = (attrs['rgb_color'] as List?)?.cast<num>();
        capabilities.add(ColorRgbCapability(
          r: rgb?[0].toInt() ?? 255,
          g: rgb?[1].toInt() ?? 255,
          b: rgb?[2].toInt() ?? 255,
        ));
      }

    case 'switch' || 'input_boolean' || 'fan':
      capabilities.add(PowerSwitchCapability(on: state == 'on'));

    case 'binary_sensor':
      final deviceClass = attrs['device_class'] as String?;
      final type = switch (deviceClass) {
        'motion' || 'occupancy' || 'presence' => CapabilityType.motion,
        'door' || 'window' || 'opening' || 'garage_door' => CapabilityType.contact,
        _ => CapabilityType.contact,
      };
      capabilities.add(BinarySensorCapability(type: type, active: state == 'on'));

    case 'sensor':
      final deviceClass = attrs['device_class'] as String?;
      final type = switch (deviceClass) {
        'temperature' => CapabilityType.currentTemperature,
        'humidity' => CapabilityType.humidity,
        'illuminance' => CapabilityType.illuminance,
        'battery' => CapabilityType.battery,
        _ => null,
      };
      if (type == null) return null; // skip unmapped sensor classes for now
      capabilities.add(SensorCapability(
        type: type,
        value: num.tryParse(state),
        unit: attrs['unit_of_measurement'] as String? ?? '',
      ));

    case 'climate':
      capabilities.add(PowerSwitchCapability(on: state != 'off'));
      capabilities.add(TargetTemperatureCapability(
        target: (attrs['temperature'] as num?) ?? 21,
        min: (attrs['min_temp'] as num?) ?? 7,
        max: (attrs['max_temp'] as num?) ?? 35,
      ));
      capabilities.add(SensorCapability(
        type: CapabilityType.currentTemperature,
        value: attrs['current_temperature'] as num?,
        unit: '°',
      ));
      final fanModes = (attrs['fan_modes'] as List?)?.cast<String>();
      if (fanModes != null && fanModes.isNotEmpty) {
        capabilities.add(ModeCapability(
          type: CapabilityType.fanMode,
          mode: attrs['fan_mode'] as String? ?? fanModes.first,
          options: fanModes,
        ));
      }

    default:
      return null; // unmapped domain
  }

  return UniversalDevice(
    id: 'ha:$connectionId:$entityId',
    name: attrs['friendly_name'] as String? ?? entityId,
    origin: DeviceOrigin(
      type: OriginType.homeAssistant,
      connectionId: connectionId,
      nativeId: entityId,
      protocol: 'wifi',
    ),
    capabilities: capabilities,
    roomId: roomId,
  );
}
