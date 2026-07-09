import 'package:home_assistant_adapter/home_assistant_adapter.dart';
import 'package:test/test.dart';
import 'package:unification/unification.dart';

void main() {
  group('mapHaEntity', () {
    test('color light -> power/brightness/colorTemp/rgb (§3.2 spec)', () {
      final device = mapHaEntity({
        'entity_id': 'light.hue_go',
        'state': 'on',
        'attributes': {
          'friendly_name': 'Hue Go',
          'supported_color_modes': ['color_temp', 'xy'],
          'brightness': 128,
          'color_temp': 350,
          'rgb_color': [255, 100, 50],
        },
      }, connectionId: 'test')!;

      expect(
        device.capabilities.map((c) => c.type),
        containsAll([
          CapabilityType.powerSwitch,
          CapabilityType.brightness,
          CapabilityType.colorTemperature,
          CapabilityType.colorRgb,
        ]),
      );
      expect(device.capability<PowerSwitchCapability>()!.on, isTrue);
      expect(device.capability<BrightnessCapability>()!.level, 50);
      expect(device.id, 'ha:test:light.hue_go');
    });

    test('binary_sensor door -> contact', () {
      final device = mapHaEntity({
        'entity_id': 'binary_sensor.front_door',
        'state': 'off',
        'attributes': {'device_class': 'door'},
      }, connectionId: 'test')!;

      final contact = device.capabilities.whereType<BinarySensorCapability>();
      expect(contact.single.type, CapabilityType.contact);
      expect(contact.single.active, isFalse);
    });

    test('climate -> power/target/current/fanMode', () {
      final device = mapHaEntity({
        'entity_id': 'climate.living_room',
        'state': 'heat',
        'attributes': {
          'temperature': 22,
          'current_temperature': 20.5,
          'min_temp': 5,
          'max_temp': 30,
          'fan_modes': ['auto', 'low'],
          'fan_mode': 'auto',
        },
      }, connectionId: 'test')!;

      expect(device.capability<PowerSwitchCapability>()!.on, isTrue);
      expect(device.capability<TargetTemperatureCapability>()!.target, 22);
      expect(device.capability<ModeCapability>()!.options, ['auto', 'low']);
      expect(device.primaryCapability, CapabilityType.targetTemperature);
    });

    test('unmapped domain -> null', () {
      expect(
        mapHaEntity({
          'entity_id': 'automation.morning',
          'state': 'on',
          'attributes': <String, dynamic>{},
        }, connectionId: 'test'),
        isNull,
      );
    });
  });
}
