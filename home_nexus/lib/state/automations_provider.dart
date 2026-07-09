import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import 'bridge_connection.dart';
import 'device_providers.dart';
import 'ha_connection.dart'
    show HaStatus, controllerProvider, localStoreProvider;
import 'scenes_provider.dart';

// ---------------------------------------------------------------------------
// Model (§6.2): trigger -> conditions -> actions
// ---------------------------------------------------------------------------

/// Default state key observed/compared for a capability type.
String stateKeyFor(String capabilityType) => switch (capabilityType) {
      CapabilityType.powerSwitch => 'on',
      CapabilityType.motion || CapabilityType.contact => 'active',
      CapabilityType.brightness => 'level',
      CapabilityType.targetTemperature => 'target',
      _ => 'value',
    };

sealed class Trigger {
  const Trigger();
  Map<String, dynamic> toJson();

  static Trigger fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'device' => DeviceTrigger.fromJson(json),
        'time' => TimeTrigger.fromJson(json),
        _ => throw ArgumentError('unknown trigger ${json['type']}'),
      };
}

/// Fires on the edge: condition false -> true.
class DeviceTrigger extends Trigger {
  final String deviceId;
  final String capabilityType;
  final String op; // '==', '>', '<'
  final dynamic value;

  const DeviceTrigger({
    required this.deviceId,
    required this.capabilityType,
    this.op = '==',
    required this.value,
  });

  bool matches(UniversalDevice? device) {
    final state =
        device?.capabilityOfType(capabilityType)?.state[stateKeyFor(capabilityType)];
    if (state == null) return false;
    return compareValues(state, op, value);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'device',
        'deviceId': deviceId,
        'capabilityType': capabilityType,
        'op': op,
        'value': value,
      };

  factory DeviceTrigger.fromJson(Map<String, dynamic> json) => DeviceTrigger(
        deviceId: json['deviceId'] as String,
        capabilityType: json['capabilityType'] as String,
        op: json['op'] as String? ?? '==',
        value: json['value'],
      );
}

class TimeTrigger extends Trigger {
  final int hour;
  final int minute;
  const TimeTrigger({required this.hour, required this.minute});

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'time', 'hour': hour, 'minute': minute};

  factory TimeTrigger.fromJson(Map<String, dynamic> json) => TimeTrigger(
      hour: json['hour'] as int, minute: json['minute'] as int);
}

/// AND-ed conditions. Currently: time-of-day window.
class TimeRangeCondition {
  final int startMinutes; // minutes since midnight
  final int endMinutes;
  const TimeRangeCondition(
      {required this.startMinutes, required this.endMinutes});

  bool matches(int nowMinutes) => startMinutes <= endMinutes
      ? nowMinutes >= startMinutes && nowMinutes <= endMinutes
      // overnight window, e.g. 22:00-06:00
      : nowMinutes >= startMinutes || nowMinutes <= endMinutes;

  Map<String, dynamic> toJson() =>
      {'type': 'timeRange', 'start': startMinutes, 'end': endMinutes};

  factory TimeRangeCondition.fromJson(Map<String, dynamic> json) =>
      TimeRangeCondition(
          startMinutes: json['start'] as int, endMinutes: json['end'] as int);
}

sealed class AutomationAction {
  const AutomationAction();
  Map<String, dynamic> toJson();

  static AutomationAction fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'setState' => SetStateAction.fromJson(json),
        'runScene' => RunSceneAction.fromJson(json),
        _ => throw ArgumentError('unknown action ${json['type']}'),
      };
}

class SetStateAction extends AutomationAction {
  final String deviceId;
  final String capabilityType;
  final dynamic value;

  const SetStateAction({
    required this.deviceId,
    required this.capabilityType,
    required this.value,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'setState',
        'deviceId': deviceId,
        'capabilityType': capabilityType,
        'value': value,
      };

  factory SetStateAction.fromJson(Map<String, dynamic> json) => SetStateAction(
        deviceId: json['deviceId'] as String,
        capabilityType: json['capabilityType'] as String,
        value: json['value'],
      );
}

class RunSceneAction extends AutomationAction {
  final String sceneId;
  const RunSceneAction({required this.sceneId});

  @override
  Map<String, dynamic> toJson() => {'type': 'runScene', 'sceneId': sceneId};

  factory RunSceneAction.fromJson(Map<String, dynamic> json) =>
      RunSceneAction(sceneId: json['sceneId'] as String);
}

class Automation {
  final String id;
  final String name;
  final bool enabled;
  final Trigger trigger;
  final TimeRangeCondition? condition;
  final List<AutomationAction> actions;

  const Automation({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.trigger,
    this.condition,
    required this.actions,
  });

  Automation copyWith({bool? enabled}) => Automation(
        id: id,
        name: name,
        enabled: enabled ?? this.enabled,
        trigger: trigger,
        condition: condition,
        actions: actions,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'trigger': trigger.toJson(),
        'condition': condition?.toJson(),
        'actions': [for (final a in actions) a.toJson()],
      };

  factory Automation.fromJson(Map<String, dynamic> json) => Automation(
        id: json['id'] as String,
        name: json['name'] as String,
        enabled: json['enabled'] as bool? ?? true,
        trigger:
            Trigger.fromJson((json['trigger'] as Map).cast<String, dynamic>()),
        condition: json['condition'] == null
            ? null
            : TimeRangeCondition.fromJson(
                (json['condition'] as Map).cast<String, dynamic>()),
        actions: [
          for (final a in (json['actions'] as List))
            AutomationAction.fromJson((a as Map).cast<String, dynamic>()),
        ],
      );
}

bool compareValues(dynamic state, String op, dynamic target) {
  switch (op) {
    case '==':
      if (state is num && target is num) return state == target;
      return '$state' == '$target';
    case '>':
      return state is num && target is num && state > target;
    case '<':
      return state is num && target is num && state < target;
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Bridge handoff (§6.2): rules whose trigger and actions all live on
// bridge-origin devices run on the Nexus Bridge 24/7; the app engine skips
// them while the bridge is connected.
// ---------------------------------------------------------------------------

bool _isBridgeDevice(String deviceId, List<UniversalDevice> devices) =>
    devices.any(
        (d) => d.id == deviceId && d.origin.type == OriginType.nexusBridge);

/// Expands runScene actions into their captured setState actions.
List<SetStateAction>? _flattenActions(
    Automation automation, List<Scene> scenes) {
  final out = <SetStateAction>[];
  for (final action in automation.actions) {
    switch (action) {
      case SetStateAction a:
        out.add(a);
      case RunSceneAction(:final sceneId):
        final scene = scenes.where((s) => s.id == sceneId).firstOrNull;
        if (scene == null) return null;
        out.addAll([
          for (final sa in scene.actions)
            SetStateAction(
              deviceId: sa.deviceId,
              capabilityType: sa.capabilityType,
              value: sa.value,
            ),
        ]);
    }
  }
  return out;
}

bool isBridgeRunnable(
    Automation automation, List<UniversalDevice> devices, List<Scene> scenes) {
  final trigger = automation.trigger;
  if (trigger is DeviceTrigger &&
      !_isBridgeDevice(trigger.deviceId, devices)) {
    return false;
  }
  final flat = _flattenActions(automation, scenes);
  if (flat == null || flat.isEmpty) return false;
  return flat.every((a) => _isBridgeDevice(a.deviceId, devices));
}

/// Bridge-protocol JSON for one runnable automation (scenes flattened).
Map<String, dynamic> bridgeAutomationJson(
    Automation automation, List<Scene> scenes) {
  final flat = _flattenActions(automation, scenes) ?? const [];
  return {
    'id': automation.id,
    'name': automation.name,
    'enabled': automation.enabled,
    'trigger': automation.trigger.toJson(),
    'condition': automation.condition?.toJson(),
    'actions': [for (final a in flat) a.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

class AutomationsNotifier extends Notifier<List<Automation>> {
  @override
  List<Automation> build() => const [];

  void load(String? json) {
    if (json == null) return;
    state = [
      for (final a in (jsonDecode(json) as List))
        Automation.fromJson((a as Map).cast<String, dynamic>()),
    ];
  }

  Future<void> save(Automation automation) async {
    state = [...state.where((a) => a.id != automation.id), automation];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((a) => a.id != id).toList();
    await _persist();
  }

  Future<void> toggle(String id, bool enabled) async {
    state = [
      for (final a in state) a.id == id ? a.copyWith(enabled: enabled) : a,
    ];
    await _persist();
  }

  Future<void> _persist() async {
    final store = await ref.read(localStoreProvider.future);
    await store
        .saveAutomationsJson(jsonEncode([for (final a in state) a.toJson()]));
  }
}

final automationsProvider =
    NotifierProvider<AutomationsNotifier, List<Automation>>(
        AutomationsNotifier.new);

// ---------------------------------------------------------------------------
// Engine — runs while the app is alive; the Nexus Bridge will take over
// bridge-origin automations for 24/7 reliability (§6.2, phase 4 follow-up).
// ---------------------------------------------------------------------------

class AutomationEngine {
  final Ref _ref;
  Timer? _clock;
  String _lastFiredMinute = '';

  AutomationEngine._(this._ref);

  static AutomationEngine? _instance;

  /// Wires the engine into provider changes; idempotent.
  static void attach(Ref ref) {
    if (_instance != null) return;
    final engine = AutomationEngine._(ref);
    _instance = engine;
    ref.listen<List<UniversalDevice>>(devicesProvider, (prev, next) {
      engine.onDevicesChanged(prev ?? const [], next);
    });
    engine._clock = Timer.periodic(
        const Duration(seconds: 20), (_) => engine.onTick(DateTime.now()));
    ref.onDispose(() {
      engine._clock?.cancel();
      _instance = null;
    });
  }

  @visibleForTesting
  static AutomationEngine forTest(Ref ref) => AutomationEngine._(ref);

  void onDevicesChanged(
      List<UniversalDevice> prev, List<UniversalDevice> next) {
    final prevById = {for (final d in prev) d.id: d};
    final nextById = {for (final d in next) d.id: d};

    for (final automation in _ref.read(automationsProvider)) {
      if (!automation.enabled || _bridgeHandles(automation)) continue;
      final trigger = automation.trigger;
      if (trigger is! DeviceTrigger) continue;

      final was = trigger.matches(prevById[trigger.deviceId]);
      final is_ = trigger.matches(nextById[trigger.deviceId]);
      if (!was && is_ && _conditionHolds(automation, DateTime.now())) {
        _runActions(automation);
      }
    }
  }

  void onTick(DateTime now) {
    final minuteKey = '${now.year}-${now.month}-${now.day}T${now.hour}:${now.minute}';
    if (minuteKey == _lastFiredMinute) return;
    _lastFiredMinute = minuteKey;

    for (final automation in _ref.read(automationsProvider)) {
      if (!automation.enabled || _bridgeHandles(automation)) continue;
      final trigger = automation.trigger;
      if (trigger is TimeTrigger &&
          trigger.hour == now.hour &&
          trigger.minute == now.minute &&
          _conditionHolds(automation, now)) {
        _runActions(automation);
      }
    }
  }

  /// True when the bridge is connected and runs this rule itself —
  /// the app engine must not double-fire it.
  bool _bridgeHandles(Automation automation) {
    if (_ref.read(bridgeConnectionProvider).status != HaStatus.connected) {
      return false;
    }
    return isBridgeRunnable(
        automation, _ref.read(devicesProvider), _ref.read(scenesProvider));
  }

  bool _conditionHolds(Automation automation, DateTime now) {
    final condition = automation.condition;
    if (condition == null) return true;
    return condition.matches(now.hour * 60 + now.minute);
  }

  Future<void> _runActions(Automation automation) async {
    final devices = _ref.read(devicesProvider);
    final controller = _ref.read(controllerProvider);
    for (final action in automation.actions) {
      try {
        switch (action) {
          case SetStateAction(:final deviceId, :final capabilityType, :final value):
            final device =
                devices.where((d) => d.id == deviceId).firstOrNull;
            final cap = device?.capabilityOfType(capabilityType);
            if (device != null && cap != null) {
              await cap.executeCommand(controller, device, value);
            }
          case RunSceneAction(:final sceneId):
            final scene = _ref
                .read(scenesProvider)
                .where((s) => s.id == sceneId)
                .firstOrNull;
            if (scene != null) {
              await _ref.read(scenesProvider.notifier).activate(scene);
            }
        }
      } catch (_) {
        // one failing action must not stop the rest
      }
    }
  }
}
