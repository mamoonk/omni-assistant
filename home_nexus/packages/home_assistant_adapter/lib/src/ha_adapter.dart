import 'dart:async';
import 'dart:convert';

import 'package:unification/unification.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ha_entity_mapper.dart';

/// Home Assistant WebSocket adapter.
///
/// Lifecycle: connect() -> authenticates -> subscribes to state_changed.
/// fetchAllDevices() pulls areas + registry + states and maps them.
/// Implements DeviceController so capabilities can execute commands.
class HomeAssistantAdapter implements DeviceController {
  final String connectionId;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _msgId = 0;
  final _pending = <int, Completer<dynamic>>{};
  final _deviceUpdates = StreamController<UniversalDevice>.broadcast();

  /// entity_id -> area name, populated during fetchAllDevices.
  final _entityRoom = <String, String>{};

  HomeAssistantAdapter({this.connectionId = 'default'});

  /// Real-time device state updates (already mapped to UniversalDevice).
  Stream<UniversalDevice> get deviceUpdates => _deviceUpdates.stream;

  Future<void> connect(String url, String token) async {
    final wsUrl = url
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/api/websocket');
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    final authOk = Completer<void>();
    _sub = _channel!.stream.listen(
      (raw) => _onMessage(jsonDecode(raw as String), token, authOk),
      onError: (Object e) {
        if (!authOk.isCompleted) authOk.completeError(e);
      },
      onDone: () {
        if (!authOk.isCompleted) {
          authOk.completeError(StateError('Connection closed during auth'));
        }
      },
    );
    await authOk.future.timeout(const Duration(seconds: 15));

    await _send({
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });
  }

  void _onMessage(
    Map<String, dynamic> msg,
    String token,
    Completer<void> authOk,
  ) {
    switch (msg['type']) {
      case 'auth_required':
        _channel!.sink.add(jsonEncode({'type': 'auth', 'access_token': token}));
      case 'auth_ok':
        if (!authOk.isCompleted) authOk.complete();
      case 'auth_invalid':
        if (!authOk.isCompleted) {
          authOk.completeError(StateError('Invalid access token'));
        }
      case 'result':
        final id = msg['id'] as int;
        final completer = _pending.remove(id);
        if (completer == null) return;
        if (msg['success'] == true) {
          completer.complete(msg['result']);
        } else {
          completer.completeError(
              StateError(msg['error']?['message'] as String? ?? 'HA error'));
        }
      case 'event':
        _onStateChanged(msg);
    }
  }

  void _onStateChanged(Map<String, dynamic> msg) {
    final data = msg['event']?['data'] as Map?;
    final newState = data?['new_state'] as Map?;
    if (newState == null) return;
    final entityId = newState['entity_id'] as String;
    final device = mapHaEntity(
      newState.cast<String, dynamic>(),
      connectionId: connectionId,
      roomId: _entityRoom[entityId] ?? 'unassigned',
    );
    if (device != null) _deviceUpdates.add(device);
  }

  Future<dynamic> _send(Map<String, dynamic> payload) {
    final id = ++_msgId;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _channel!.sink.add(jsonEncode({'id': id, ...payload}));
    return completer.future.timeout(const Duration(seconds: 30));
  }

  /// Pulls areas, device/entity registries, and states; maps everything.
  Future<List<UniversalDevice>> fetchAllDevices() async {
    final results = await Future.wait([
      _send({'type': 'config/area_registry/list'}),
      _send({'type': 'config/device_registry/list'}),
      _send({'type': 'config/entity_registry/list'}),
      _send({'type': 'get_states'}),
    ]);

    final areas = {
      for (final a in (results[0] as List).cast<Map>())
        a['area_id'] as String: a['name'] as String,
    };
    final deviceArea = {
      for (final d in (results[1] as List).cast<Map>())
        d['id'] as String: d['area_id'] as String?,
    };
    _entityRoom.clear();
    for (final e in (results[2] as List).cast<Map>()) {
      final areaId =
          (e['area_id'] as String?) ?? deviceArea[e['device_id'] as String?];
      if (areaId != null) {
        _entityRoom[e['entity_id'] as String] = areas[areaId] ?? 'unassigned';
      }
    }

    final devices = <UniversalDevice>[];
    for (final state in (results[3] as List).cast<Map>()) {
      final entity = state.cast<String, dynamic>();
      final device = mapHaEntity(
        entity,
        connectionId: connectionId,
        roomId: _entityRoom[entity['entity_id']] ?? 'unassigned',
      );
      if (device != null) devices.add(device);
    }
    return devices;
  }

  Future<void> callService(
    String domain,
    String service,
    Map<String, dynamic> data,
  ) =>
      _send({
        'type': 'call_service',
        'domain': domain,
        'service': service,
        'service_data': data,
      });

  @override
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  ) {
    final entityId = device.origin.nativeId;
    final domain = entityId.split('.').first;
    switch (capabilityType) {
      case CapabilityType.powerSwitch:
        final service = (value as bool) ? 'turn_on' : 'turn_off';
        // climate uses its own domain services; lights/switches use homeassistant.*
        return callService(
          domain == 'climate' ? 'climate' : 'homeassistant',
          service,
          {'entity_id': entityId},
        );
      case CapabilityType.brightness:
        return callService('light', 'turn_on', {
          'entity_id': entityId,
          'brightness_pct': value,
        });
      case CapabilityType.colorRgb:
        return callService('light', 'turn_on', {
          'entity_id': entityId,
          'rgb_color': value, // [r, g, b]
        });
      case CapabilityType.colorTemperature:
        return callService('light', 'turn_on', {
          'entity_id': entityId,
          'color_temp': value,
        });
      case CapabilityType.targetTemperature:
        return callService('climate', 'set_temperature', {
          'entity_id': entityId,
          'temperature': value,
        });
      case CapabilityType.fanMode:
        return callService('climate', 'set_fan_mode', {
          'entity_id': entityId,
          'fan_mode': value,
        });
      default:
        throw UnsupportedError('No HA mapping for capability $capabilityType');
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }
}
