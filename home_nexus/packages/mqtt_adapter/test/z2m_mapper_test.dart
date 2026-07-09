import 'package:mqtt_adapter/mqtt_adapter.dart';
import 'package:test/test.dart';
import 'package:unification/unification.dart';

Map<String, dynamic> _bulbEntry() => {
      'type': 'Router',
      'friendly_name': 'office_bulb',
      'ieee_address': '0x00158d0001e5c123',
      'definition': {
        'vendor': 'IKEA',
        'model': 'LED1924G9',
        'exposes': [
          {
            'type': 'light',
            'features': [
              {'type': 'binary', 'name': 'state', 'property': 'state'},
              {
                'type': 'numeric',
                'name': 'brightness',
                'property': 'brightness'
              },
              {
                'type': 'numeric',
                'name': 'color_temp',
                'property': 'color_temp'
              },
              {'type': 'composite', 'name': 'color_xy', 'property': 'color'},
            ],
          },
          {'type': 'numeric', 'property': 'linkquality'},
        ],
      },
    };

void main() {
  group('mapZ2mDevice', () {
    test('bulb exposes -> power/brightness/colorTemp/rgb', () {
      final device = mapZ2mDevice(_bulbEntry(), connectionId: 'b1')!;

      expect(
        device.capabilities.map((c) => c.type),
        containsAll([
          CapabilityType.powerSwitch,
          CapabilityType.brightness,
          CapabilityType.colorTemperature,
          CapabilityType.colorRgb,
        ]),
      );
      expect(device.id, 'mqtt:b1:office_bulb');
      expect(device.origin.protocol, 'zigbee');
      expect(device.manufacturer, 'IKEA');
    });

    test('coordinator and definition-less devices are skipped', () {
      expect(mapZ2mDevice({'type': 'Coordinator'}, connectionId: 'b1'), isNull);
      expect(
        mapZ2mDevice(
          {'type': 'EndDevice', 'friendly_name': 'x', 'definition': null},
          connectionId: 'b1',
        ),
        isNull,
      );
    });

    test('contact + battery sensor', () {
      final device = mapZ2mDevice({
        'type': 'EndDevice',
        'friendly_name': 'door',
        'definition': {
          'vendor': 'Aqara',
          'model': 'MCCGQ11LM',
          'exposes': [
            {'type': 'binary', 'property': 'contact'},
            {'type': 'numeric', 'property': 'battery', 'unit': '%'},
          ],
        },
      }, connectionId: 'b1')!;

      expect(device.has(CapabilityType.contact), isTrue);
      expect(device.has(CapabilityType.battery), isTrue);
    });
  });

  group('applyZ2mState', () {
    test('updates power, brightness scaling, and inverts contact', () {
      final bulb = mapZ2mDevice(_bulbEntry(), connectionId: 'b1')!;
      final changed =
          applyZ2mState(bulb, {'state': 'ON', 'brightness': 127});

      expect(changed, isTrue);
      expect(bulb.capability<PowerSwitchCapability>()!.on, isTrue);
      expect(bulb.capability<BrightnessCapability>()!.level, 50);

      final door = mapZ2mDevice({
        'type': 'EndDevice',
        'friendly_name': 'door',
        'definition': {
          'exposes': [
            {'type': 'binary', 'property': 'contact'},
          ],
        },
      }, connectionId: 'b1')!;
      applyZ2mState(door, {'contact': false}); // z2m false = open
      expect(
        door.capabilities.whereType<BinarySensorCapability>().single.active,
        isTrue,
      );
    });

    test('irrelevant keys change nothing', () {
      final bulb = mapZ2mDevice(_bulbEntry(), connectionId: 'b1')!;
      expect(applyZ2mState(bulb, {'linkquality': 66}), isFalse);
    });
  });

  group('z2mCommandPayload', () {
    test('maps capability commands to set payloads', () {
      expect(z2mCommandPayload(CapabilityType.powerSwitch, true),
          {'state': 'ON'});
      expect(z2mCommandPayload(CapabilityType.brightness, 50),
          {'brightness': 127});
      expect(z2mCommandPayload(CapabilityType.colorRgb, [1, 2, 3]), {
        'color': {'r': 1, 'g': 2, 'b': 3}
      });
      expect(z2mCommandPayload(CapabilityType.targetTemperature, 21.5),
          {'occupied_heating_setpoint': 21.5});
    });
  });
}
