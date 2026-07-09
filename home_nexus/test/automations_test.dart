import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

import 'package:home_nexus/state/automations_provider.dart';
import 'package:home_nexus/state/device_providers.dart';
import 'package:home_nexus/state/ha_connection.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProviderContainer, AutomationEngine)> setup() async {
    final container = ProviderContainer();
    await container.read(localStoreProvider.future);
    // engine wired via a probe provider so it gets a real Ref
    late AutomationEngine engine;
    final probe = Provider<AutomationEngine>(AutomationEngine.forTest);
    engine = container.read(probe);
    return (container, engine);
  }

  UniversalDevice motion(bool active) => UniversalDevice(
        id: 'mock:hall_motion',
        name: 'Hallway Motion',
        origin: const DeviceOrigin(
          type: OriginType.homeAssistant,
          connectionId: 'mock',
          nativeId: 'mock',
        ),
        capabilities: [
          BinarySensorCapability(type: CapabilityType.motion, active: active),
        ],
      );

  test('device trigger fires on edge and runs action', () async {
    final (container, engine) = await setup();
    addTearDown(container.dispose);

    final devices = container.read(devicesProvider);
    final coffee = devices.firstWhere((d) => d.id == 'mock:coffee');
    expect(coffee.capability<PowerSwitchCapability>()!.on, isFalse);

    await container.read(automationsProvider.notifier).save(Automation(
          id: 'a1',
          name: 'Motion -> coffee on',
          trigger: const DeviceTrigger(
            deviceId: 'mock:hall_motion',
            capabilityType: CapabilityType.motion,
            value: true,
          ),
          actions: const [
            SetStateAction(
              deviceId: 'mock:coffee',
              capabilityType: CapabilityType.powerSwitch,
              value: true,
            ),
          ],
        ));

    // inactive -> active edge
    engine.onDevicesChanged([motion(false)], [motion(true)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coffee.capability<PowerSwitchCapability>()!.on, isTrue,
        reason: 'edge should fire the action');

    // still active: no re-fire (turn coffee off manually, stay active)
    coffee.capability<PowerSwitchCapability>()!.on = false;
    engine.onDevicesChanged([motion(true)], [motion(true)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coffee.capability<PowerSwitchCapability>()!.on, isFalse,
        reason: 'no edge, no fire');
  });

  test('time-range condition gates the trigger', () async {
    final (container, engine) = await setup();
    addTearDown(container.dispose);

    final coffee = container
        .read(devicesProvider)
        .firstWhere((d) => d.id == 'mock:coffee');

    await container.read(automationsProvider.notifier).save(Automation(
          id: 'a2',
          name: 'Gated',
          trigger: const DeviceTrigger(
            deviceId: 'mock:hall_motion',
            capabilityType: CapabilityType.motion,
            value: true,
          ),
          // window that can never contain "now": start == end == impossible
          condition:
              const TimeRangeCondition(startMinutes: -2, endMinutes: -1),
          actions: const [
            SetStateAction(
              deviceId: 'mock:coffee',
              capabilityType: CapabilityType.powerSwitch,
              value: true,
            ),
          ],
        ));

    engine.onDevicesChanged([motion(false)], [motion(true)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coffee.capability<PowerSwitchCapability>()!.on, isFalse,
        reason: 'condition outside window blocks the action');
  });

  test('time trigger fires once per matching minute', () async {
    final (container, engine) = await setup();
    addTearDown(container.dispose);

    final coffee = container
        .read(devicesProvider)
        .firstWhere((d) => d.id == 'mock:coffee');

    await container.read(automationsProvider.notifier).save(Automation(
          id: 'a3',
          name: 'Morning coffee',
          trigger: const TimeTrigger(hour: 7, minute: 30),
          actions: const [
            SetStateAction(
              deviceId: 'mock:coffee',
              capabilityType: CapabilityType.powerSwitch,
              value: true,
            ),
          ],
        ));

    engine.onTick(DateTime(2026, 1, 1, 7, 30, 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coffee.capability<PowerSwitchCapability>()!.on, isTrue);

    coffee.capability<PowerSwitchCapability>()!.on = false;
    engine.onTick(DateTime(2026, 1, 1, 7, 30, 25)); // same minute
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coffee.capability<PowerSwitchCapability>()!.on, isFalse,
        reason: 'same minute must not re-fire');
  });

  test('overnight time range wraps midnight', () {
    const window = TimeRangeCondition(
        startMinutes: 22 * 60, endMinutes: 6 * 60); // 22:00-06:00
    expect(window.matches(23 * 60), isTrue);
    expect(window.matches(3 * 60), isTrue);
    expect(window.matches(12 * 60), isFalse);
  });

  test('automation round-trips through JSON', () {
    final automation = Automation(
      id: 'a4',
      name: 'RT',
      trigger: const DeviceTrigger(
        deviceId: 'd1',
        capabilityType: CapabilityType.currentTemperature,
        op: '<',
        value: 18,
      ),
      condition: const TimeRangeCondition(startMinutes: 60, endMinutes: 120),
      actions: const [
        SetStateAction(
            deviceId: 'd2',
            capabilityType: CapabilityType.targetTemperature,
            value: 22),
        RunSceneAction(sceneId: 's1'),
      ],
    );
    final restored = Automation.fromJson(automation.toJson());
    expect(restored.name, 'RT');
    expect((restored.trigger as DeviceTrigger).op, '<');
    expect(restored.condition!.endMinutes, 120);
    expect(restored.actions, hasLength(2));
    expect(restored.actions.last, isA<RunSceneAction>());
  });
}
