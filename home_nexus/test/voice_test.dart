import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

import 'package:home_nexus/services/voice_intents.dart';
import 'package:home_nexus/state/device_providers.dart';
import 'package:home_nexus/state/ha_connection.dart';
import 'package:home_nexus/state/voice_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parseVoiceCommand', () {
    test('power phrasings', () {
      final a = parseVoiceCommand('Turn on the kitchen light') as PowerIntent;
      expect((a.query, a.on), ('kitchen light', true));

      final b = parseVoiceCommand('switch the coffee maker off') as PowerIntent;
      expect((b.query, b.on), ('coffee maker', false));

      final c = parseVoiceCommand('turn off everything') as PowerIntent;
      expect(c.on, isFalse);
      expect(isBroadcastQuery(c.query), isTrue);
    });

    test('set value with units', () {
      final pct = parseVoiceCommand('set hue go to 50 percent') as SetValueIntent;
      expect((pct.query, pct.value, pct.unit), ('hue go', 50, 'percent'));

      final dim = parseVoiceCommand('dim the ceiling light to 30') as SetValueIntent;
      expect((dim.query, dim.value, dim.unit), ('ceiling light', 30, 'percent'));

      final temp = parseVoiceCommand('set thermostat to 21.5 degrees') as SetValueIntent;
      expect((temp.query, temp.value, temp.unit), ('thermostat', 21.5, 'degrees'));

      final bare = parseVoiceCommand('set the thermostat to 22') as SetValueIntent;
      expect(bare.unit, ''); // capability decides
    });

    test('scenes and garbage', () {
      final scene = parseVoiceCommand('activate scene movie night') as SceneIntent;
      expect(scene.query, 'movie night');
      expect(parseVoiceCommand('what is the meaning of life'), isNull);
      expect(parseVoiceCommand(''), isNull);
    });
  });

  group('device matching', () {
    UniversalDevice device(String name, String room) => UniversalDevice(
          id: name,
          name: name,
          origin: const DeviceOrigin(
              type: OriginType.manualIp, connectionId: 'x', nativeId: 'x'),
          capabilities: [PowerSwitchCapability()],
          roomId: room,
        );

    test('matches by name, room, and prefix', () {
      final devices = [
        device('Hue Go', 'Living Room'),
        device('Ceiling Light', 'Living Room'),
        device('Coffee Maker', 'Kitchen'),
      ];
      expect(bestDeviceMatch('hue go', devices)!.name, 'Hue Go');
      expect(bestDeviceMatch('coffee', devices)!.name, 'Coffee Maker');
      expect(bestDeviceMatch('living room ceiling', devices)!.name,
          'Ceiling Light');
      expect(bestDeviceMatch('garage door', devices), isNull);
    });
  });

  group('executeVoiceCommand', () {
    test('end-to-end against mock devices', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(localStoreProvider.future);
      final devices = container.read(devicesProvider);

      final coffee = devices.firstWhere((d) => d.id == 'mock:coffee');
      var reply = await executeVoiceCommandForTest(
          container, 'turn on the coffee maker');
      expect(reply, contains('Coffee Maker'));
      expect(coffee.capability<PowerSwitchCapability>()!.on, isTrue);

      final hue = devices.firstWhere((d) => d.id == 'mock:hue_go');
      reply = await executeVoiceCommandForTest(container, 'dim hue go to 25');
      expect(reply, contains('25%'));
      expect(hue.capability<BrightnessCapability>()!.level, 25);

      final thermostat = devices.firstWhere((d) => d.id == 'mock:thermostat');
      reply = await executeVoiceCommandForTest(
          container, 'set the thermostat to 23');
      expect(reply, contains('23°'));
      expect(
          thermostat.capability<TargetTemperatureCapability>()!.target, 23);

      reply = await executeVoiceCommandForTest(container, 'open the pod bay doors');
      expect(reply, contains("didn't understand"));
    });
  });
}

Future<String> executeVoiceCommandForTest(
        ProviderContainer container, String input) =>
    container.read(voiceExecutorProvider)(input);
