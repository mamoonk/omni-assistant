import 'package:flutter_test/flutter_test.dart';
import 'package:unification/unification.dart';

import 'package:home_nexus/state/automations_provider.dart';
import 'package:home_nexus/state/scenes_provider.dart';

UniversalDevice _device(String id, OriginType origin) => UniversalDevice(
      id: id,
      name: id,
      origin: DeviceOrigin(
          type: origin, connectionId: 'c', nativeId: id, protocol: 'x'),
      capabilities: [PowerSwitchCapability()],
    );

void main() {
  final devices = [
    _device('bridge:b0:motion', OriginType.nexusBridge),
    _device('bridge:b0:plug', OriginType.nexusBridge),
    _device('ha:x:light', OriginType.homeAssistant),
  ];

  Automation auto(String triggerDevice, List<AutomationAction> actions) =>
      Automation(
        id: 'a',
        name: 'a',
        trigger: DeviceTrigger(
          deviceId: triggerDevice,
          capabilityType: CapabilityType.powerSwitch,
          value: true,
        ),
        actions: actions,
      );

  test('all-bridge automation is runnable on the bridge', () {
    final a = auto('bridge:b0:motion', const [
      SetStateAction(
          deviceId: 'bridge:b0:plug',
          capabilityType: CapabilityType.powerSwitch,
          value: true),
    ]);
    expect(isBridgeRunnable(a, devices, const []), isTrue);
  });

  test('HA trigger or action disqualifies', () {
    final haTrigger = auto('ha:x:light', const [
      SetStateAction(
          deviceId: 'bridge:b0:plug',
          capabilityType: CapabilityType.powerSwitch,
          value: true),
    ]);
    expect(isBridgeRunnable(haTrigger, devices, const []), isFalse);

    final haAction = auto('bridge:b0:motion', const [
      SetStateAction(
          deviceId: 'ha:x:light',
          capabilityType: CapabilityType.powerSwitch,
          value: true),
    ]);
    expect(isBridgeRunnable(haAction, devices, const []), isFalse);
  });

  test('time trigger with bridge-only scene flattens for the bridge', () {
    const scene = Scene(id: 's1', name: 'night', actions: [
      SceneAction(
          deviceId: 'bridge:b0:plug',
          capabilityType: CapabilityType.powerSwitch,
          value: false),
    ]);
    final a = Automation(
      id: 'a',
      name: 'night',
      trigger: const TimeTrigger(hour: 23, minute: 0),
      actions: const [RunSceneAction(sceneId: 's1')],
    );

    expect(isBridgeRunnable(a, devices, const [scene]), isTrue);
    final json = bridgeAutomationJson(a, const [scene]);
    final actions = json['actions'] as List;
    expect(actions, hasLength(1));
    expect((actions.single as Map)['type'], 'setState');
    expect((actions.single as Map)['deviceId'], 'bridge:b0:plug');
  });

  test('scene touching a non-bridge device disqualifies', () {
    const scene = Scene(id: 's2', name: 'mixed', actions: [
      SceneAction(
          deviceId: 'bridge:b0:plug',
          capabilityType: CapabilityType.powerSwitch,
          value: false),
      SceneAction(
          deviceId: 'ha:x:light',
          capabilityType: CapabilityType.powerSwitch,
          value: false),
    ]);
    final a = Automation(
      id: 'a',
      name: 'mixed',
      trigger: const TimeTrigger(hour: 23, minute: 0),
      actions: const [RunSceneAction(sceneId: 's2')],
    );
    expect(isBridgeRunnable(a, devices, const [scene]), isFalse);
  });
}
