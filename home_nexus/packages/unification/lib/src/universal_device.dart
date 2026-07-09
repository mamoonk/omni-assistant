import 'capability.dart';
import 'device_origin.dart';

/// The Rosetta Stone: every device from any source becomes this.
class UniversalDevice {
  final String id;
  final String name;
  final String manufacturer;
  final String model;
  final DeviceOrigin origin;
  final List<Capability> capabilities;
  final String roomId;

  UniversalDevice({
    required this.id,
    required this.name,
    this.manufacturer = '',
    this.model = '',
    required this.origin,
    required this.capabilities,
    this.roomId = 'unassigned',
  });

  /// Merged live state across all capabilities.
  Map<String, dynamic> get currentState => {
        for (final c in capabilities) c.type: c.state,
      };

  T? capability<T extends Capability>() =>
      capabilities.whereType<T>().firstOrNull;

  Capability? capabilityOfType(String type) {
    for (final c in capabilities) {
      if (c.type == type) return c;
    }
    return null;
  }

  bool has(String type) => capabilityOfType(type) != null;

  /// Drives which dashboard widget renders this device.
  String get primaryCapability {
    const priority = [
      CapabilityType.colorRgb,
      CapabilityType.brightness,
      CapabilityType.targetTemperature,
      CapabilityType.cover,
      CapabilityType.lock,
      CapabilityType.powerSwitch,
      CapabilityType.motion,
      CapabilityType.contact,
      CapabilityType.currentTemperature,
    ];
    for (final p in priority) {
      if (has(p)) return p;
    }
    return capabilities.isNotEmpty ? capabilities.first.type : '';
  }
}
