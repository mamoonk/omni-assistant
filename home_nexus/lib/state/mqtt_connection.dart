import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_adapter/mqtt_adapter.dart';
import 'package:unification/unification.dart';

import '../services/local_store.dart';
import 'device_providers.dart';
import 'ha_connection.dart' show HaStatus, localStoreProvider;

class MqttConnectionState {
  final HaStatus status;
  final String? error;
  final MqttConfig? config;
  final int attempt;

  const MqttConnectionState({
    this.status = HaStatus.disconnected,
    this.error,
    this.config,
    this.attempt = 0,
  });

  MqttConnectionState copyWith({
    HaStatus? status,
    String? error,
    MqttConfig? config,
    int? attempt,
    bool clearError = false,
  }) =>
      MqttConnectionState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        config: config ?? this.config,
        attempt: attempt ?? this.attempt,
      );
}

class MqttConnectionNotifier extends Notifier<MqttConnectionState> {
  MqttAdapter? adapter;
  Timer? _retryTimer;
  Timer? _saveTimer;
  StreamSubscription? _updatesSub;
  StreamSubscription? _connSub;
  bool _userDisconnected = false;

  @override
  MqttConnectionState build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      _saveTimer?.cancel();
      _teardown();
    });
    return const MqttConnectionState();
  }

  Future<void> connect(MqttConfig config, {bool save = true}) async {
    _userDisconnected = false;
    _retryTimer?.cancel();
    _teardown();
    state = state.copyWith(
        status: HaStatus.connecting, config: config, clearError: true);

    final store = await ref.read(localStoreProvider.future);
    if (save) await store.saveMqttConfig(config);

    try {
      final a = MqttAdapter(
          connectionId: 'primary', baseTopic: config.baseTopic);
      await a.connect(
        config.host,
        config.port,
        username: config.username,
        password: config.password,
      );
      adapter = a;

      final devices = await a.discoverDevices();
      final notifier = ref.read(devicesProvider.notifier)
        ..replaceOrigin(OriginType.mqtt, devices);
      await store.saveDevices(ref.read(devicesProvider));

      _updatesSub = a.deviceUpdates.listen((d) {
        notifier.upsert(d);
        _persistSoon(store);
      });
      _connSub = a.connectionEvents.listen((up) {
        if (!up) _onDropped();
      });

      state = state.copyWith(
          status: HaStatus.connected, attempt: 0, clearError: true);
    } catch (e) {
      _teardown();
      state = state.copyWith(status: HaStatus.error, error: '$e');
      _scheduleReconnect();
    }
  }

  void _onDropped() {
    if (_userDisconnected) return;
    state = state.copyWith(status: HaStatus.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final config = state.config;
    if (_userDisconnected || config == null) return;
    final attempt = state.attempt + 1;
    final delay = Duration(seconds: min(60, pow(2, min(attempt, 6)).toInt()));
    state = state.copyWith(attempt: attempt);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => connect(config, save: false));
  }

  Future<void> disconnect({bool forget = false}) async {
    _userDisconnected = true;
    _retryTimer?.cancel();
    _saveTimer?.cancel();
    _teardown();
    if (forget) {
      final store = await ref.read(localStoreProvider.future);
      await store.clearMqttConfig();
      ref.read(devicesProvider.notifier).replaceOrigin(OriginType.mqtt, []);
      await store.saveDevices(ref.read(devicesProvider));
    }
    state = MqttConnectionState(config: forget ? null : state.config);
  }

  void _persistSoon(LocalStore store) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2),
        () => store.saveDevices(ref.read(devicesProvider)));
  }

  void _teardown() {
    _updatesSub?.cancel();
    _connSub?.cancel();
    _updatesSub = null;
    _connSub = null;
    adapter?.disconnect();
    adapter = null;
  }
}

final mqttConnectionProvider =
    NotifierProvider<MqttConnectionNotifier, MqttConnectionState>(
        MqttConnectionNotifier.new);
