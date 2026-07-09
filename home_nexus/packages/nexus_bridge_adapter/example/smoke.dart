// E2E smoke against a live `nexus-bridge -demo` instance:
//   dart run example/smoke.dart [host] [port]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart';
import 'package:unification/unification.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 8927;
  final token = args.length > 2 ? args[2] : '';

  final adapter = NexusBridgeAdapter(connectionId: 'smoke');
  final info = await adapter.connect(host, port, token: token);
  print('connected: ${info.name} v${info.version} ${info.protocols}');

  final joins = <JoinEvent>[];
  final sub = adapter.joinEvents.listen((e) {
    joins.add(e);
    print('join event: ${e.runtimeType}');
  });

  await adapter.permitJoin(duration: 30);
  print('permit_join accepted, waiting for demo device...');
  await Future<void>.delayed(const Duration(seconds: 6));
  await sub.cancel();

  final interviewed = joins.whereType<DeviceInterviewed>().toList();
  if (interviewed.isEmpty) {
    print('FAIL: no device interviewed');
    exit(1);
  }
  final device = interviewed.first.device;
  print('interviewed: ${device.name} '
      '[${device.capabilities.map((c) => c.type).join(', ')}]');

  final devices = await adapter.fetchAllDevices();
  print('device list: ${devices.length}');

  if (device.has(CapabilityType.powerSwitch)) {
    var echoed = false;
    final updateSub = adapter.deviceUpdates.listen((d) {
      if (d.id == device.id &&
          d.capability<PowerSwitchCapability>()?.on == true) {
        echoed = true;
      }
    });
    await adapter.sendCommand(device, CapabilityType.powerSwitch, true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await updateSub.cancel();
    print(echoed
        ? 'command round-trip OK (state_changed echoed on=true)'
        : 'FAIL: no state_changed echo');
    if (!echoed) exit(1);
  }

  await adapter.disconnect();
  print('SMOKE PASS');
  exit(0);
}
