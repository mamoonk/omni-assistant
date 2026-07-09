import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart';
import 'package:unification/unification.dart';

import '../services/local_store.dart';
import 'device_providers.dart';
import 'ha_connection.dart' show HaStatus, localStoreProvider;

class BridgeConnectionState {
  final HaStatus status;
  final String? error;
  final BridgeConfig? config;
  final BridgeInfo? info;
  final int attempt;

  const BridgeConnectionState({
    this.status = HaStatus.disconnected,
    this.error,
    this.config,
    this.info,
    this.attempt = 0,
  });

  BridgeConnectionState copyWith({
    HaStatus? status,
    String? error,
    BridgeConfig? config,
    BridgeInfo? info,
    int? attempt,
    bool clearError = false,
  }) =>
      BridgeConnectionState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        config: config ?? this.config,
        info: info ?? this.info,
        attempt: attempt ?? this.attempt,
      );
}

class BridgeConnectionNotifier extends Notifier<BridgeConnectionState> {
  NexusBridgeAdapter? adapter;
  Timer? _retryTimer;
  Timer? _saveTimer;
  StreamSubscription? _updatesSub;
  StreamSubscription? _connSub;
  bool _userDisconnected = false;

  @override
  BridgeConnectionState build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      _saveTimer?.cancel();
      _teardown();
    });
    return const BridgeConnectionState();
  }

  Future<void> connect(BridgeConfig config, {bool save = true}) async {
    _userDisconnected = false;
    _retryTimer?.cancel();
    await _teardown();
    state = state.copyWith(
        status: HaStatus.connecting, config: config, clearError: true);

    final store = await ref.read(localStoreProvider.future);
    if (save) await store.saveBridgeConfig(config);

    try {
      final a = NexusBridgeAdapter(connectionId: 'primary');
      final info = await a.connect(config.host, config.port);
      adapter = a;

      final devices = await a.fetchAllDevices();
      final notifier = ref.read(devicesProvider.notifier)
        ..replaceOrigin(OriginType.nexusBridge, devices);
      await store.saveDevices(ref.read(devicesProvider));

      _updatesSub = a.deviceUpdates.listen((d) {
        notifier.upsert(d);
        _persistSoon(store);
      });
      _connSub = a.connectionEvents.listen((up) {
        if (!up) _onDropped();
      });

      state = state.copyWith(
          status: HaStatus.connected, info: info, attempt: 0, clearError: true);
    } catch (e) {
      await _teardown();
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
    await _teardown();
    if (forget) {
      final store = await ref.read(localStoreProvider.future);
      await store.clearBridgeConfig();
      ref
          .read(devicesProvider.notifier)
          .replaceOrigin(OriginType.nexusBridge, []);
      await store.saveDevices(ref.read(devicesProvider));
    }
    state = BridgeConnectionState(config: forget ? null : state.config);
  }

  void _persistSoon(LocalStore store) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2),
        () => store.saveDevices(ref.read(devicesProvider)));
  }

  Future<void> _teardown() async {
    await _updatesSub?.cancel();
    await _connSub?.cancel();
    _updatesSub = null;
    _connSub = null;
    await adapter?.disconnect();
    adapter = null;
  }
}

final bridgeConnectionProvider =
    NotifierProvider<BridgeConnectionNotifier, BridgeConnectionState>(
        BridgeConnectionNotifier.new);
