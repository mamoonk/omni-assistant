import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unification/unification.dart';

import 'package:home_nexus/services/manual_ip.dart';

void main() {
  group('extractPath', () {
    test('walks maps and list indices', () {
      final json = {
        'sensors': [
          {'temperature': 21.5},
        ],
        'ok': true,
      };
      expect(extractPath(json, 'sensors.0.temperature'), 21.5);
      expect(extractPath(json, 'ok'), true);
      expect(extractPath(json, 'missing.path'), isNull);
      expect(extractPath(42, ''), 42);
    });
  });

  group('ManualIpController', () {
    late HttpServer server;
    final requests = <String>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        requests.add(req.uri.toString());
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'sensors': [
              {'temperature': 19.5},
            ],
          }));
        req.response.close();
      });
    });

    tearDown(() => server.close());

    ManualIpConfig config(ManualTemplate template) => ManualIpConfig(
          id: 't1',
          name: 'Test',
          roomId: 'Lab',
          template: template,
          ip: '127.0.0.1:${server.port}',
          urls: {
            'on': 'http://{ip}/relay/0?turn=on',
            'off': 'http://{ip}/relay/0?turn=off',
            'brightness': 'http://{ip}/light/0?brightness={value}',
            'poll': 'http://{ip}/status',
          },
          valuePath: 'sensors.0.temperature',
        );

    test('power command substitutes {ip} and mutates state optimistically',
        () async {
      final c = config(ManualTemplate.switchDevice);
      final controller = ManualIpController([c]);
      final device = c.toDevice();

      await controller.sendCommand(device, CapabilityType.powerSwitch, true);
      expect(requests.single, '/relay/0?turn=on');
      expect(device.capability<PowerSwitchCapability>()!.on, isTrue);

      await controller.sendCommand(device, CapabilityType.powerSwitch, false);
      expect(requests.last, '/relay/0?turn=off');
      expect(device.capability<PowerSwitchCapability>()!.on, isFalse);
    });

    test('brightness command substitutes {value}', () async {
      final c = config(ManualTemplate.dimmer);
      final controller = ManualIpController([c]);
      final device = c.toDevice();

      await controller.sendCommand(device, CapabilityType.brightness, 75);
      expect(requests.single, '/light/0?brightness=75');
      expect(device.capability<BrightnessCapability>()!.level, 75);
    });

    test('pollSensor extracts value via path', () async {
      final c = config(ManualTemplate.sensor);
      final controller = ManualIpController([c]);
      expect(await controller.pollSensor(c), 19.5);
    });
  });
}
