import 'package:unification/unification.dart';

/// Zigbee2MQTT publishes brightness as 0..254.
const z2mBrightnessMax = 254;

/// Maps one entry of `zigbee2mqtt/bridge/devices` to a UniversalDevice.
/// Returns null for the coordinator and devices without a definition.
UniversalDevice? mapZ2mDevice(
  Map<String, dynamic> entry, {
  required String connectionId,
}) {
  if (entry['type'] == 'Coordinator') return null;
  final definition = entry['definition'] as Map?;
  final friendlyName = entry['friendly_name'] as String?;
  if (definition == null || friendlyName == null) return null;

  final capabilities = <Capability>[];
  for (final expose in (definition['exposes'] as List? ?? const [])) {
    capabilities.addAll(
        _parseExpose((expose as Map).cast<String, dynamic>()));
  }
  if (capabilities.isEmpty) return null;

  return UniversalDevice(
    id: 'mqtt:$connectionId:$friendlyName',
    name: friendlyName,
    manufacturer: definition['vendor'] as String? ?? '',
    model: definition['model'] as String? ?? '',
    origin: DeviceOrigin(
      type: OriginType.mqtt,
      connectionId: connectionId,
      nativeId: friendlyName,
      protocol: 'zigbee',
    ),
    capabilities: capabilities,
    roomId: 'Zigbee',
  );
}

List<Capability> _parseExpose(Map<String, dynamic> expose) {
  switch (expose['type']) {
    case 'light' || 'switch':
      final caps = <Capability>[];
      for (final f in (expose['features'] as List? ?? const [])) {
        final feature = (f as Map).cast<String, dynamic>();
        switch (feature['property']) {
          case 'state':
            caps.add(PowerSwitchCapability());
          case 'brightness':
            caps.add(BrightnessCapability());
          case 'color_temp':
            caps.add(ColorTemperatureCapability());
          case 'color':
            caps.add(ColorRgbCapability());
        }
      }
      return caps;

    case 'climate':
      final caps = <Capability>[];
      for (final f in (expose['features'] as List? ?? const [])) {
        final feature = (f as Map).cast<String, dynamic>();
        switch (feature['property']) {
          case 'occupied_heating_setpoint' || 'current_heating_setpoint':
            caps.add(TargetTemperatureCapability(
              min: feature['value_min'] as num? ?? 7,
              max: feature['value_max'] as num? ?? 35,
            ));
          case 'local_temperature':
            caps.add(SensorCapability(
                type: CapabilityType.currentTemperature, unit: '°C'));
          case 'fan_mode':
            caps.add(ModeCapability(
              type: CapabilityType.fanMode,
              mode: '',
              options: (feature['values'] as List?)?.cast<String>() ?? const [],
            ));
        }
      }
      return caps;

    case 'binary':
      return switch (expose['property']) {
        'occupancy' || 'presence' => [
            BinarySensorCapability(type: CapabilityType.motion)
          ],
        // z2m: contact == true means CLOSED; active means open in our model
        'contact' => [BinarySensorCapability(type: CapabilityType.contact)],
        _ => const [],
      };

    case 'numeric':
      final type = switch (expose['property']) {
        'temperature' => CapabilityType.currentTemperature,
        'humidity' => CapabilityType.humidity,
        'illuminance' || 'illuminance_lux' => CapabilityType.illuminance,
        'battery' => CapabilityType.battery,
        _ => null,
      };
      if (type == null) return const [];
      return [
        SensorCapability(type: type, unit: expose['unit'] as String? ?? ''),
      ];

    default:
      return const [];
  }
}

/// Applies a state topic payload (`zigbee2mqtt/<name>`) onto the device's
/// capabilities in place. Returns true if anything changed.
bool applyZ2mState(UniversalDevice device, Map<String, dynamic> payload) {
  var changed = false;

  void mark() => changed = true;

  for (final entry in payload.entries) {
    switch (entry.key) {
      case 'state':
        final power = device.capability<PowerSwitchCapability>();
        if (power != null) {
          power.on = entry.value == 'ON';
          mark();
        }
      case 'brightness':
        final b = device.capability<BrightnessCapability>();
        if (b != null && entry.value is num) {
          b.level =
              ((entry.value as num) / z2mBrightnessMax * 100).round();
          mark();
        }
      case 'color_temp':
        final ct = device.capability<ColorTemperatureCapability>();
        if (ct != null && entry.value is num) {
          ct.mireds = (entry.value as num).toInt();
          mark();
        }
      case 'occupancy' || 'presence':
        final m = device.capabilities
            .whereType<BinarySensorCapability>()
            .where((c) => c.type == CapabilityType.motion)
            .firstOrNull;
        if (m != null) {
          m.active = entry.value == true;
          mark();
        }
      case 'contact':
        final c = device.capabilities
            .whereType<BinarySensorCapability>()
            .where((c) => c.type == CapabilityType.contact)
            .firstOrNull;
        if (c != null) {
          c.active = entry.value == false; // contact=false -> open
          mark();
        }
      case 'temperature' || 'local_temperature':
        final s = device.capabilities
            .whereType<SensorCapability>()
            .where((c) => c.type == CapabilityType.currentTemperature)
            .firstOrNull;
        if (s != null && entry.value is num) {
          s.value = entry.value as num;
          mark();
        }
      case 'humidity' || 'battery' || 'illuminance' || 'illuminance_lux':
        final type = switch (entry.key) {
          'humidity' => CapabilityType.humidity,
          'battery' => CapabilityType.battery,
          _ => CapabilityType.illuminance,
        };
        final s = device.capabilities
            .whereType<SensorCapability>()
            .where((c) => c.type == type)
            .firstOrNull;
        if (s != null && entry.value is num) {
          s.value = entry.value as num;
          mark();
        }
      case 'occupied_heating_setpoint' || 'current_heating_setpoint':
        final t = device.capability<TargetTemperatureCapability>();
        if (t != null && entry.value is num) {
          t.target = entry.value as num;
          mark();
        }
      case 'fan_mode':
        final m = device.capabilities
            .whereType<ModeCapability>()
            .where((c) => c.type == CapabilityType.fanMode)
            .firstOrNull;
        if (m != null && entry.value is String) {
          m.mode = entry.value as String;
          mark();
        }
    }
  }
  return changed;
}

/// Builds the JSON body for `zigbee2mqtt/<name>/set`.
Map<String, dynamic> z2mCommandPayload(String capabilityType, dynamic value) {
  switch (capabilityType) {
    case CapabilityType.powerSwitch:
      return {'state': (value as bool) ? 'ON' : 'OFF'};
    case CapabilityType.brightness:
      return {
        'brightness': ((value as num) / 100 * z2mBrightnessMax).round()
      };
    case CapabilityType.colorRgb:
      final rgb = value as List;
      return {
        'color': {'r': rgb[0], 'g': rgb[1], 'b': rgb[2]}
      };
    case CapabilityType.colorTemperature:
      return {'color_temp': value};
    case CapabilityType.targetTemperature:
      return {'occupied_heating_setpoint': value};
    case CapabilityType.fanMode:
      return {'fan_mode': value};
    default:
      throw UnsupportedError('No z2m mapping for capability $capabilityType');
  }
}
