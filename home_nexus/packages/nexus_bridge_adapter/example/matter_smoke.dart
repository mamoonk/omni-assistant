// E2E: commission a simulated Matter device on a live `nexus-bridge -demo`.
//   dart run example/matter_smoke.dart [host] [port]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart';
import 'package:unification/unification.dart';

const chipTestQR = 'MT:Y.K9042C00KA0648G00';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 8927;
  final token = args.length > 2 ? args[2] : '';

  final adapter = NexusBridgeAdapter(connectionId: 'smoke');
  final info = await adapter.connect(host, port, token: token);
  print('connected: protocols ${info.protocols}');
  if (!info.protocols.contains('matter')) {
    print('FAIL: bridge does not advertise matter');
    exit(1);
  }

  final interviewed = adapter.joinEvents
      .firstWhere((e) => e is DeviceInterviewed)
      .timeout(const Duration(seconds: 10));

  // invalid code must be rejected
  try {
    await adapter.commission('MT:INVALID!!');
    print('FAIL: invalid code accepted');
    exit(1);
  } catch (e) {
    print('invalid code rejected: OK');
  }

  await adapter.commission(chipTestQR);
  final device = ((await interviewed) as DeviceInterviewed).device;
  print('commissioned: ${device.name} '
      '(${device.manufacturer} / ${device.model}, '
      'protocol ${device.origin.protocol})');

  if (device.manufacturer != 'VID 0xFFF1' || device.model != 'PID 0x8000') {
    print('FAIL: payload decoded incorrectly');
    exit(1);
  }

  await adapter.sendCommand(device, CapabilityType.powerSwitch, true);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final devices = await adapter.fetchAllDevices();
  final on = devices
      .firstWhere((d) => d.id == device.id)
      .capability<PowerSwitchCapability>()!
      .on;
  await adapter.disconnect();

  if (!on) {
    print('FAIL: matter device did not switch on');
    exit(1);
  }
  print('MATTER SMOKE PASS');
  exit(0);
}
