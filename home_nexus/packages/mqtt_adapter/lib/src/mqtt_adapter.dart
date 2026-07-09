import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:unification/unification.dart';

import 'z2m_mapper.dart';

/// Direct MQTT adapter for Zigbee2MQTT (§4.2).
///
/// connect() -> subscribes `<base>/#` -> retained `<base>/bridge/devices`
/// drives discovery; per-device state topics stream live updates.
/// Implements DeviceController: commands publish to `<base>/<name>/set`.
class MqttAdapter implements DeviceController {
  final String connectionId;
  final String baseTopic;

  MqttServerClient? _client;
  final _devices = <String, UniversalDevice>{}; // friendly_name -> device
  final _deviceUpdates = StreamController<UniversalDevice>.broadcast();
  final _connectionEvents = StreamController<bool>.broadcast();
  Completer<List<UniversalDevice>>? _discovery;
  bool _userDisconnected = false;

  MqttAdapter({this.connectionId = 'default', this.baseTopic = 'zigbee2mqtt'});

  Stream<UniversalDevice> get deviceUpdates => _deviceUpdates.stream;

  /// true after connect, false on unexpected drop (clean disconnect is silent).
  Stream<bool> get connectionEvents => _connectionEvents.stream;

  Future<void> connect(
    String host,
    int port, {
    String? username,
    String? password,
  }) async {
    _userDisconnected = false;
    final client = MqttServerClient.withPort(
        host, 'home_nexus_$connectionId', port)
      ..logging(on: false)
      ..keepAlivePeriod = 30
      ..autoReconnect = false
      ..connectionMessage =
          MqttConnectMessage().withClientIdentifier('home_nexus_$connectionId').startClean();

    client.onDisconnected = () {
      if (!_userDisconnected) _connectionEvents.add(false);
    };

    final status = await client.connect(username, password);
    if (status?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('MQTT connect failed: ${status?.state}');
    }
    _client = client;

    client.updates!.listen(_onMessages);
    client.subscribe('$baseTopic/#', MqttQos.atMostOnce);
    _connectionEvents.add(true);
  }

  /// Resolves once the retained bridge/devices list arrives.
  Future<List<UniversalDevice>> discoverDevices(
      {Duration timeout = const Duration(seconds: 10)}) {
    if (_devices.isNotEmpty) return Future.value(_devices.values.toList());
    _discovery ??= Completer<List<UniversalDevice>>();
    return _discovery!.future.timeout(timeout, onTimeout: () => const []);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final pub = event.payload;
      if (pub is! MqttPublishMessage) continue;
      final raw =
          MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      final topic = event.topic;

      if (topic == '$baseTopic/bridge/devices') {
        _onDeviceList(raw);
        continue;
      }
      // state topic is exactly <base>/<friendly_name>
      final name = topic.startsWith('$baseTopic/')
          ? topic.substring(baseTopic.length + 1)
          : null;
      final device = name == null ? null : _devices[name];
      if (device == null) continue;

      final decoded = _tryDecode(raw);
      if (decoded == null) continue;
      if (applyZ2mState(device, decoded)) _deviceUpdates.add(device);
    }
  }

  void _onDeviceList(String raw) {
    final list = _tryDecodeList(raw);
    if (list == null) return;
    for (final entry in list) {
      final device = mapZ2mDevice(
        (entry as Map).cast<String, dynamic>(),
        connectionId: connectionId,
      );
      if (device != null) _devices[device.origin.nativeId] = device;
    }
    if (_discovery != null && !_discovery!.isCompleted) {
      _discovery!.complete(_devices.values.toList());
    }
  }

  @override
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  ) async {
    final client = _client;
    if (client == null) throw StateError('MQTT not connected');
    final payload = z2mCommandPayload(capabilityType, value);
    final builder = MqttClientPayloadBuilder()..addString(jsonEncode(payload));
    client.publishMessage(
      '$baseTopic/${device.origin.nativeId}/set',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void disconnect() {
    _userDisconnected = true;
    _client?.disconnect();
    _client = null;
  }

  Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map ? v.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  List? _tryDecodeList(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }
}
