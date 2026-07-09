import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart';
import 'package:test/test.dart';
import 'package:unification/unification.dart';

/// In-process fake bridge speaking the Nexus protocol.
class FakeBridge {
  late HttpServer server;
  WebSocket? socket;
  final receivedCommands = <Map<String, dynamic>>[];

  /// When set, auth succeeds only with this token.
  String? requiredToken;

  int get port => server.port;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path != '/ws') return;
      socket = await WebSocketTransformer.upgrade(req);
      socket!.listen((raw) {
        final cmd = jsonDecode(raw as String) as Map<String, dynamic>;
        if (cmd['type'] == 'auth') {
          _send({
            'type': 'auth_result',
            'success': requiredToken == null || cmd['token'] == requiredToken,
          });
          return;
        }
        receivedCommands.add(cmd);
        _respond(cmd);
      });
    });
  }

  void _respond(Map<String, dynamic> cmd) {
    final id = cmd['id'];
    switch ('${cmd['domain']}.${cmd['action']}') {
      case 'bridge.info':
        _send({
          'id': id,
          'type': 'result',
          'success': true,
          'result': {
            'name': 'Fake Bridge',
            'version': '0.1.0',
            'protocols': ['zigbee'],
          },
        });
      case 'device.list':
        _send({
          'id': id,
          'type': 'result',
          'success': true,
          'result': {
            'devices': [_demoBulbJson()],
          },
        });
      case 'zigbee.permit_join':
        _send({'id': id, 'type': 'result', 'success': true});
        _send({
          'type': 'event',
          'domain': 'zigbee',
          'event': 'device_joined',
          'data': {'ieee_address': '0xabc', 'interviewing': true},
        });
        _send({
          'type': 'event',
          'domain': 'zigbee',
          'event': 'device_interviewed',
          'data': {'device': _demoBulbJson()},
        });
      case 'device.execute':
        _send({'id': id, 'type': 'result', 'success': true});
    }
  }

  Map<String, dynamic> _demoBulbJson() => {
        'id': 'bridge:test:0xabc',
        'name': 'Demo Bulb 1',
        'manufacturer': 'Nexus Demo',
        'model': 'BULB-1',
        'origin': {
          'type': 'nexusBridge',
          'connectionId': 'test',
          'nativeId': '0xabc',
          'protocol': 'zigbee',
        },
        'roomId': 'unassigned',
        'capabilities': [
          {
            'type': 'powerSwitch',
            'state': {'on': false},
          },
          {
            'type': 'brightness',
            'state': {'level': 100},
          },
        ],
      };

  void _send(Map<String, dynamic> msg) => socket?.add(jsonEncode(msg));

  Future<void> stop() async {
    await socket?.close();
    await server.close();
  }
}

void main() {
  late FakeBridge bridge;
  late NexusBridgeAdapter adapter;

  setUp(() async {
    bridge = FakeBridge();
    await bridge.start();
    adapter = NexusBridgeAdapter(connectionId: 'test');
  });

  tearDown(() async {
    await adapter.disconnect();
    await bridge.stop();
  });

  test('connect returns bridge info', () async {
    final info = await adapter.connect('127.0.0.1', bridge.port);
    expect(info.name, 'Fake Bridge');
    expect(info.protocols, ['zigbee']);
  });

  test('auth: correct token accepted, wrong token rejected', () async {
    bridge.requiredToken = 'secret';
    final info =
        await adapter.connect('127.0.0.1', bridge.port, token: 'secret');
    expect(info.name, 'Fake Bridge');
    await adapter.disconnect();

    final rejected = NexusBridgeAdapter(connectionId: 'test2');
    await expectLater(
      rejected.connect('127.0.0.1', bridge.port, token: 'wrong'),
      throwsA(isA<StateError>()),
    );
  });

  test('fetchAllDevices maps protocol JSON to UniversalDevice', () async {
    await adapter.connect('127.0.0.1', bridge.port);
    final devices = await adapter.fetchAllDevices();

    expect(devices, hasLength(1));
    final bulb = devices.single;
    expect(bulb.id, 'bridge:test:0xabc');
    expect(bulb.origin.type, OriginType.nexusBridge);
    expect(bulb.has(CapabilityType.powerSwitch), isTrue);
    expect(bulb.capability<BrightnessCapability>()!.level, 100);
  });

  test('permitJoin streams join -> interviewed events', () async {
    await adapter.connect('127.0.0.1', bridge.port);
    final events = <JoinEvent>[];
    final sub = adapter.joinEvents.listen(events.add);

    await adapter.permitJoin();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();

    expect(events.whereType<DeviceJoined>(), hasLength(1));
    final interviewed = events.whereType<DeviceInterviewed>().single;
    expect(interviewed.device.name, 'Demo Bulb 1');
  });

  test('sendCommand posts device.execute with capability payload', () async {
    await adapter.connect('127.0.0.1', bridge.port);
    final devices = await adapter.fetchAllDevices();

    await adapter.sendCommand(
        devices.single, CapabilityType.powerSwitch, true);

    final execute = bridge.receivedCommands
        .lastWhere((c) => c['action'] == 'execute');
    expect(execute['params'], {
      'deviceId': 'bridge:test:0xabc',
      'capability': 'powerSwitch',
      'value': true,
    });
  });
}
