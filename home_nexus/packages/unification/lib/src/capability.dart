import 'device_controller.dart';
import 'universal_device.dart';

/// Well-known capability type strings. Adapters map native features to these.
abstract final class CapabilityType {
  static const powerSwitch = 'powerSwitch';
  static const brightness = 'brightness';
  static const colorRgb = 'colorRgb';
  static const colorTemperature = 'colorTemperature';
  static const targetTemperature = 'targetTemperature';
  static const currentTemperature = 'currentTemperature';
  static const humidity = 'humidity';
  static const fanMode = 'fanMode';
  static const motion = 'motion';
  static const contact = 'contact';
  static const illuminance = 'illuminance';
  static const battery = 'battery';
  static const cover = 'cover';
  static const lock = 'lock';
  static const power = 'power'; // instantaneous draw, W
  static const energy = 'energy'; // cumulative, kWh
}

abstract class Capability {
  String get type;
  Map<String, dynamic> get state;

  Future<void> executeCommand(
    DeviceController controller,
    UniversalDevice device,
    dynamic value,
  ) =>
      controller.sendCommand(device, type, value);
}

/// On/off. state: {'on': bool}
class PowerSwitchCapability extends Capability {
  bool on;
  PowerSwitchCapability({this.on = false});

  @override
  String get type => CapabilityType.powerSwitch;

  @override
  Map<String, dynamic> get state => {'on': on};
}

/// 0-100 percent. state: {'level': int}
class BrightnessCapability extends Capability {
  int level;
  BrightnessCapability({this.level = 0});

  @override
  String get type => CapabilityType.brightness;

  @override
  Map<String, dynamic> get state => {'level': level};
}

/// state: {'r': int, 'g': int, 'b': int}
class ColorRgbCapability extends Capability {
  int r, g, b;
  ColorRgbCapability({this.r = 255, this.g = 255, this.b = 255});

  @override
  String get type => CapabilityType.colorRgb;

  @override
  Map<String, dynamic> get state => {'r': r, 'g': g, 'b': b};
}

/// Mireds. state: {'mireds': int}
class ColorTemperatureCapability extends Capability {
  int mireds;
  ColorTemperatureCapability({this.mireds = 300});

  @override
  String get type => CapabilityType.colorTemperature;

  @override
  Map<String, dynamic> get state => {'mireds': mireds};
}

/// Read-only numeric sensor (temperature, humidity, illuminance, battery...).
class SensorCapability extends Capability {
  @override
  final String type;
  num? value;
  final String unit;
  SensorCapability({required this.type, this.value, this.unit = ''});

  @override
  Map<String, dynamic> get state => {'value': value, 'unit': unit};
}

/// Boolean sensor (motion, contact). state: {'active': bool}
class BinarySensorCapability extends Capability {
  @override
  final String type;
  bool active;
  BinarySensorCapability({required this.type, this.active = false});

  @override
  Map<String, dynamic> get state => {'active': active};
}

/// Climate setpoint. state: {'target': num}
class TargetTemperatureCapability extends Capability {
  num target;
  final num min;
  final num max;
  TargetTemperatureCapability({this.target = 21, this.min = 7, this.max = 35});

  @override
  String get type => CapabilityType.targetTemperature;

  @override
  Map<String, dynamic> get state => {'target': target, 'min': min, 'max': max};
}

/// Enumerated mode (fan speed, HVAC mode...). state: {'mode': String, 'options': [...]}
class ModeCapability extends Capability {
  @override
  final String type;
  String mode;
  final List<String> options;
  ModeCapability({required this.type, required this.mode, this.options = const []});

  @override
  Map<String, dynamic> get state => {'mode': mode, 'options': options};
}
