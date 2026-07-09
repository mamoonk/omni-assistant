import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_assistant_adapter/home_assistant_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

import '../mock/mock_devices.dart';
import '../services/local_store.dart';
import 'bridge_connection.dart';
import 'device_providers.dart';
import 'history_provider.dart';
import 'layout_provider.dart';
import 'mqtt_connection.dart';
import 'scenes_provider.dart';

enum HaStatus { disconnected, connecting, connected, reconnecting, error }

class HaConnectionState {
  final HaStatus status;
  final String? error;
  final HaConfig? config;
  final int attempt;

  const HaConnectionState({
    this.status = HaStatus.disconnected,
    this.error,
    this.config,
    this.attempt = 0,
  });

  HaConnectionState copyWith({
    HaStatus? status,
    String? error,
    HaConfig? config,
    int? attempt,
    bool clearError = false,
  }) =>
      HaConnectionState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        config: config ?? this.config,
        attempt: attempt ?? this.attempt,
      );
}

class HaConnectionNotifier extends Notifier<HaConnectionState> {
  HomeAssistantAdapter? adapter;
  Timer? _retryTimer;
  Timer? _saveTimer;
  StreamSubscription? _updatesSub;
  StreamSubscription? _connSub;
  bool _userDisconnected = false;

  @override
  HaConnectionState build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      _saveTimer?.cancel();
      _teardown();
    });
    return const HaConnectionState();
  }

  Future<void> connect(HaConfig config, {bool save = true}) async {
    _userDisconnected = false;
    _retryTimer?.cancel();
    await _teardown();
    state = state.copyWith(
        status: HaStatus.connecting, config: config, clearError: true);

    final store = await ref.read(localStoreProvider.future);
    if (save) await store.saveConfig(config);

    try {
      final a = HomeAssistantAdapter(connectionId: 'primary');
      await a.connect(config.url, config.token);
      adapter = a;

      final devices = await a.fetchAllDevices();
      final notifier = ref.read(devicesProvider.notifier)
        ..replaceOrigin(OriginType.homeAssistant, devices);
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
    // 2s, 4s, 8s ... capped at 60s
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
      await store.clearConfig();
      await store.clearDevices();
      ref.read(devicesProvider.notifier).replaceAll(buildMockDevices());
    }
    state = HaConnectionState(config: forget ? null : state.config);
  }

  /// Debounced device-cache write: state_changed events can be chatty.
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

final haConnectionProvider =
    NotifierProvider<HaConnectionNotifier, HaConnectionState>(
        HaConnectionNotifier.new);

final localStoreProvider = FutureProvider<LocalStore>((ref) async =>
    LocalStore(await SharedPreferences.getInstance()));

/// Routes each command to the adapter that owns the device's origin.
/// Mock/demo devices always mutate locally.
class RoutingController implements DeviceController {
  final Ref _ref;
  RoutingController(this._ref);

  @override
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  ) {
    if (device.origin.connectionId == 'mock') {
      return MockDeviceController(_ref)
          .sendCommand(device, capabilityType, value);
    }
    final adapter = switch (device.origin.type) {
      OriginType.homeAssistant =>
        _ref.read(haConnectionProvider.notifier).adapter,
      OriginType.mqtt => _ref.read(mqttConnectionProvider.notifier).adapter,
      OriginType.nexusBridge =>
        _ref.read(bridgeConnectionProvider.notifier).adapter,
      _ => null,
    };
    if (adapter == null) {
      // offline: leave state untouched; card badge already shows staleness
      return Future.value();
    }
    return adapter.sendCommand(device, capabilityType, value);
  }
}

final controllerProvider = Provider<DeviceController>((ref) {
  // rebuild routing when any connection changes
  ref.watch(haConnectionProvider);
  ref.watch(mqttConnectionProvider);
  ref.watch(bridgeConnectionProvider);
  return RoutingController(ref);
});

/// Cold-start: load cached devices + auto-connect if configured.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final store = await ref.watch(localStoreProvider.future);

  ref.read(scenesProvider.notifier).load(store.loadScenesJson());
  ref.read(layoutProvider.notifier).load(store.loadLayoutJson());

  final cached = store.loadDevices();
  if (cached.isNotEmpty) {
    ref.read(devicesProvider.notifier).replaceAll(cached);
  } else {
    _seedMockHistory(ref);
  }

  final config = store.loadConfig();
  if (config != null) {
    // fire and forget; UI shows reconnecting state
    unawaited(
        ref.read(haConnectionProvider.notifier).connect(config, save: false));
  }
  final mqttConfig = store.loadMqttConfig();
  if (mqttConfig != null) {
    unawaited(ref
        .read(mqttConnectionProvider.notifier)
        .connect(mqttConfig, save: false));
  }
  final bridgeConfig = store.loadBridgeConfig();
  if (bridgeConfig != null) {
    unawaited(ref
        .read(bridgeConnectionProvider.notifier)
        .connect(bridgeConfig, save: false));
  }
});

/// Deterministic demo series so mock sensor cards show a chart.
void _seedMockHistory(Ref ref) {
  final history = ref.read(historyProvider.notifier);
  for (final device in ref.read(devicesProvider)) {
    final temp = device.capabilities
        .whereType<SensorCapability>()
        .where((c) => c.type == CapabilityType.currentTemperature)
        .firstOrNull;
    final base = temp?.value;
    if (base == null) continue;
    history.seed(device.id, [
      for (var i = 0; i < 24; i++)
        (base + sin(i / 3) * 1.2).toDouble().roundTo(1),
    ]);
  }
}

extension on double {
  double roundTo(int places) {
    final f = pow(10, places);
    return (this * f).round() / f;
  }
}
