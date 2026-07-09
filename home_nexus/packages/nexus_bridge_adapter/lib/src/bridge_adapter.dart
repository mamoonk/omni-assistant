import 'dart:async';
import 'dart:convert';

import 'package:unification/unification.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Join-wizard progress events (§5.3).
sealed class JoinEvent {
  const JoinEvent();
}

class PermitJoinChanged extends JoinEvent {
  final bool enabled;
  final int duration;
  const PermitJoinChanged({required this.enabled, required this.duration});
}

class DeviceJoined extends JoinEvent {
  final String nativeId;
  const DeviceJoined(this.nativeId);
}

class DeviceInterviewed extends JoinEvent {
  final UniversalDevice device;
  const DeviceInterviewed(this.device);
}

/// Info returned by bridge.info.
class BridgeInfo {
  final String name;
  final String version;
  final List<String> protocols;
  const BridgeInfo(
      {required this.name, required this.version, required this.protocols});
}

/// WebSocket client for the Nexus Bridge. Speaks the JSON protocol from
/// §5.3 and implements DeviceController for bridge-origin devices.
class NexusBridgeAdapter implements DeviceController {
  final String connectionId;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _msgId = 0;
  final _pending = <String, Completer<dynamic>>{};
  final _deviceUpdates = StreamController<UniversalDevice>.broadcast();
  final _joinEvents = StreamController<JoinEvent>.broadcast();
  final _connectionEvents = StreamController<bool>.broadcast();
  bool _userDisconnected = false;

  NexusBridgeAdapter({this.connectionId = 'default'});

  Stream<UniversalDevice> get deviceUpdates => _deviceUpdates.stream;
  Stream<JoinEvent> get joinEvents => _joinEvents.stream;

  /// true after connect, false on unexpected drop.
  Stream<bool> get connectionEvents => _connectionEvents.stream;

  Future<BridgeInfo> connect(String host, int port) async {
    _userDisconnected = false;
    final uri = Uri.parse('ws://$host:$port/ws');
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _sub = _channel!.stream.listen(
      (raw) => _onMessage(jsonDecode(raw as String) as Map<String, dynamic>),
      onError: (_) {
        if (!_userDisconnected) _connectionEvents.add(false);
      },
      onDone: () {
        if (!_userDisconnected) _connectionEvents.add(false);
      },
    );

    final info = await _request('bridge', 'info');
    _connectionEvents.add(true);
    return BridgeInfo(
      name: info['name'] as String? ?? 'Nexus Bridge',
      version: info['version'] as String? ?? '?',
      protocols: (info['protocols'] as List?)?.cast<String>() ?? const [],
    );
  }

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'result':
        final completer = _pending.remove(msg['id']);
        if (completer == null) return;
        if (msg['success'] == true) {
          completer.complete(msg['result']);
        } else {
          completer.completeError(
              StateError(msg['error'] as String? ?? 'bridge error'));
        }
      case 'event':
        _onEvent(msg);
    }
  }

  void _onEvent(Map<String, dynamic> msg) {
    final data = (msg['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (msg['event']) {
      case 'permit_join_changed':
        _joinEvents.add(PermitJoinChanged(
          enabled: data['enabled'] == true,
          duration: (data['duration'] as num?)?.toInt() ?? 0,
        ));
      case 'device_joined':
        _joinEvents.add(DeviceJoined(data['ieee_address'] as String? ?? '?'));
      case 'device_interviewed':
        final device = _parseDevice(data['device']);
        if (device != null) {
          _joinEvents.add(DeviceInterviewed(device));
          _deviceUpdates.add(device);
        }
      case 'state_changed':
        final device = _parseDevice(data['device']);
        if (device != null) _deviceUpdates.add(device);
    }
  }

  UniversalDevice? _parseDevice(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return deviceFromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _request(String domain, String action,
      [Map<String, dynamic>? params]) {
    final id = 'req-${++_msgId}';
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _channel!.sink.add(jsonEncode({
      'id': id,
      'type': 'command',
      'domain': domain,
      'action': action,
      'params': ?params,
    }));
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<List<UniversalDevice>> fetchAllDevices() async {
    final result = await _request('device', 'list');
    return [
      for (final d in (result['devices'] as List? ?? const []))
        ?_parseDevice(d),
    ];
  }

  /// Opens the network for inclusion; join progress arrives on [joinEvents].
  Future<void> permitJoin({String protocol = 'zigbee', int duration = 60}) =>
      _request(protocol, 'permit_join', {'duration': duration});

  /// Replaces the bridge's 24/7 automation rule set (§6.2).
  Future<void> syncAutomations(List<Map<String, dynamic>> automations) =>
      _request('automation', 'sync', {'automations': automations});

  @override
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  ) =>
      _request('device', 'execute', {
        'deviceId': device.id,
        'capability': capabilityType,
        'value': value,
      });

  Future<void> disconnect() async {
    _userDisconnected = true;
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }
}
