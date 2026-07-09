import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_nexus/services/network_discovery.dart';

void main() {
  test('classifyPort maps known service ports', () {
    expect(classifyPort(8123), IntegrationKind.homeAssistant);
    expect(classifyPort(1883), IntegrationKind.mqttBroker);
    expect(classifyPort(8927), IntegrationKind.nexusBridge);
    expect(classifyPort(80), isNull);
  });

  test('subnetBase strips the host octet', () {
    expect(subnetBase('192.168.1.37'), '192.168.1');
    expect(subnetBase('10.0.42.254'), '10.0.42');
  });

  test('probePort detects open and closed ports', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    expect(await probePort('127.0.0.1', server.port), isTrue);
    // a fresh ephemeral port that nothing listens on
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = probe.port;
    await probe.close();
    expect(await probePort('127.0.0.1', closedPort), isFalse);
  });

  test('localIPv4Addresses returns LAN-looking addresses', () async {
    final ips = await localIPv4Addresses();
    for (final ip in ips) {
      expect(ip, isNot('127.0.0.1'));
      expect(ip.split('.'), hasLength(4));
    }
  });
}
