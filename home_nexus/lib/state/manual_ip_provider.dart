import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../services/manual_ip.dart';
import 'device_providers.dart';
import 'ha_connection.dart' show localStoreProvider;

class ManualIpNotifier extends Notifier<List<ManualIpConfig>> {
  final _pollTimers = <String, Timer>{};

  @override
  List<ManualIpConfig> build() {
    ref.onDispose(() {
      for (final t in _pollTimers.values) {
        t.cancel();
      }
    });
    return const [];
  }

  void load(String? json) {
    if (json == null) return;
    state = [
      for (final c in (jsonDecode(json) as List))
        ManualIpConfig.fromJson((c as Map).cast<String, dynamic>()),
    ];
    _materializeAll();
  }

  Future<void> add(ManualIpConfig config) async {
    state = [...state.where((c) => c.id != config.id), config];
    _materializeAll();
    await _persist();
  }

  Future<void> remove(String configId) async {
    final config = state.where((c) => c.id == configId).firstOrNull;
    state = state.where((c) => c.id != configId).toList();
    _pollTimers.remove(configId)?.cancel();
    if (config != null) {
      final devices = ref.read(devicesProvider);
      ref.read(devicesProvider.notifier).replaceAll(
          devices.where((d) => d.id != config.deviceId).toList());
    }
    await _persist();
  }

  void _materializeAll() {
    final notifier = ref.read(devicesProvider.notifier);
    for (final config in state) {
      // keep live state when the device already exists
      final existing = ref
          .read(devicesProvider)
          .where((d) => d.id == config.deviceId)
          .firstOrNull;
      if (existing == null) notifier.upsert(config.toDevice());
      _schedulePoll(config);
    }
  }

  void _schedulePoll(ManualIpConfig config) {
    _pollTimers.remove(config.id)?.cancel();
    if (config.template != ManualTemplate.sensor ||
        (config.urls['poll'] ?? '').isEmpty) {
      return;
    }
    _pollTimers[config.id] = Timer.periodic(
      Duration(seconds: config.pollSeconds),
      (_) => _pollOnce(config),
    );
    _pollOnce(config);
  }

  Future<void> _pollOnce(ManualIpConfig config) async {
    try {
      final value =
          await ref.read(manualIpControllerProvider).pollSensor(config);
      if (value == null) return;
      final device = ref
          .read(devicesProvider)
          .where((d) => d.id == config.deviceId)
          .firstOrNull;
      final sensor = device?.capabilities.whereType<SensorCapability>().firstOrNull;
      if (device == null || sensor == null) return;
      sensor.value = value;
      ref.read(devicesProvider.notifier).upsert(device);
    } catch (_) {
      // unreachable device: keep last value, retry next cycle
    }
  }

  Future<void> _persist() async {
    final store = await ref.read(localStoreProvider.future);
    await store.saveManualDevicesJson(
        jsonEncode([for (final c in state) c.toJson()]));
  }
}

final manualIpProvider =
    NotifierProvider<ManualIpNotifier, List<ManualIpConfig>>(
        ManualIpNotifier.new);

final manualIpControllerProvider = Provider<ManualIpController>(
    (ref) => ManualIpController(ref.watch(manualIpProvider)));
