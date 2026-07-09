import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import 'device_providers.dart';
import 'ha_connection.dart';

/// One captured device command inside a scene.
class SceneAction {
  final String deviceId;
  final String capabilityType;
  final dynamic value;

  const SceneAction({
    required this.deviceId,
    required this.capabilityType,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'capabilityType': capabilityType,
        'value': value,
      };

  factory SceneAction.fromJson(Map<String, dynamic> json) => SceneAction(
        deviceId: json['deviceId'] as String,
        capabilityType: json['capabilityType'] as String,
        value: json['value'],
      );
}

class Scene {
  final String id;
  final String name;
  final List<SceneAction> actions;

  const Scene({required this.id, required this.name, required this.actions});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'actions': [for (final a in actions) a.toJson()],
      };

  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
        id: json['id'] as String,
        name: json['name'] as String,
        actions: [
          for (final a in (json['actions'] as List))
            SceneAction.fromJson((a as Map).cast<String, dynamic>()),
        ],
      );
}

/// Capability types worth capturing into a scene snapshot, and how to read
/// the command value back out of the current state.
dynamic sceneValueFor(Capability cap) => switch (cap) {
      PowerSwitchCapability c => c.on,
      BrightnessCapability c => c.level,
      ColorRgbCapability c => [c.r, c.g, c.b],
      ColorTemperatureCapability c => c.mireds,
      TargetTemperatureCapability c => c.target,
      _ => null,
    };

class ScenesNotifier extends Notifier<List<Scene>> {
  @override
  List<Scene> build() => const [];

  void load(String? json) {
    if (json == null) return;
    state = [
      for (final s in (jsonDecode(json) as List))
        Scene.fromJson((s as Map).cast<String, dynamic>()),
    ];
  }

  /// Snapshot the current state of [deviceIds] into a new scene.
  Future<void> createFromCurrentState(String name, Set<String> deviceIds) async {
    final devices =
        ref.read(devicesProvider).where((d) => deviceIds.contains(d.id));
    final actions = <SceneAction>[
      for (final device in devices)
        for (final cap in device.capabilities)
          if (sceneValueFor(cap) != null)
            SceneAction(
              deviceId: device.id,
              capabilityType: cap.type,
              value: sceneValueFor(cap),
            ),
    ];
    final id = 'scene_${state.length}_${name.hashCode.toRadixString(16)}';
    state = [...state, Scene(id: id, name: name, actions: actions)];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  /// Fires all actions concurrently through the routing controller.
  Future<void> activate(Scene scene) async {
    final devices = ref.read(devicesProvider);
    final controller = ref.read(controllerProvider);
    await Future.wait([
      for (final action in scene.actions)
        () async {
          final device =
              devices.where((d) => d.id == action.deviceId).firstOrNull;
          final cap = device?.capabilityOfType(action.capabilityType);
          if (device == null || cap == null) return;
          await cap.executeCommand(controller, device, action.value);
        }(),
    ]);
  }

  Future<void> _persist() async {
    final store = await ref.read(localStoreProvider.future);
    await store
        .saveScenesJson(jsonEncode([for (final s in state) s.toJson()]));
  }
}

final scenesProvider =
    NotifierProvider<ScenesNotifier, List<Scene>>(ScenesNotifier.new);
