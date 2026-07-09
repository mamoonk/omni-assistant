// E2E: sync an automation to a live `nexus-bridge -demo`, trip its trigger
// via a device command, and verify the bridge runs the rule itself.
//   dart run example/automation_smoke.dart [host] [port]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart';
import 'package:unification/unification.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 8927;
  final token = args.length > 2 ? args[2] : '';

  final adapter = NexusBridgeAdapter(connectionId: 'smoke');
  await adapter.connect(host, port, token: token);

  // include two demo devices: bulb (join #1) and motion sensor (join #2)
  for (var i = 0; i < 2; i++) {
    final done = adapter.joinEvents
        .firstWhere((e) => e is DeviceInterviewed)
        .timeout(const Duration(seconds: 15));
    await adapter.permitJoin(duration: 10);
    await done;
  }
  final devices = await adapter.fetchAllDevices();
  final bulb = devices.firstWhere((d) => d.has(CapabilityType.powerSwitch));
  final motion = devices.firstWhere((d) => d.has(CapabilityType.motion));
  print('devices ready: ${bulb.name}, ${motion.name}');

  // rule: motion active -> bulb on (lives entirely on the bridge)
  await adapter.syncAutomations([
    {
      'id': 'smoke-rule',
      'name': 'motion -> bulb',
      'enabled': true,
      'trigger': {
        'type': 'device',
        'deviceId': motion.id,
        'capabilityType': CapabilityType.motion,
        'op': '==',
        'value': true,
      },
      'actions': [
        {
          'type': 'setState',
          'deviceId': bulb.id,
          'capabilityType': CapabilityType.powerSwitch,
          'value': true,
        },
      ],
    }
  ]);
  print('automation synced');

  var bulbOn = false;
  final sub = adapter.deviceUpdates.listen((d) {
    if (d.id == bulb.id && d.capability<PowerSwitchCapability>()?.on == true) {
      bulbOn = true;
    }
  });

  // trip the trigger: the demo manager treats motion 'active' as commandable
  // via its generic state mutation, so simulate by executing on the motion
  // sensor's capability directly through the bridge.
  await adapter.sendCommand(motion, CapabilityType.motion, true);
  await Future<void>.delayed(const Duration(seconds: 2));
  await sub.cancel();
  await adapter.disconnect();

  if (bulbOn) {
    print('AUTOMATION SMOKE PASS: bridge fired the rule and bulb turned on');
    exit(0);
  }
  print('FAIL: bulb did not turn on');
  exit(1);
}
