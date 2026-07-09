import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../services/voice_intents.dart';
import 'device_providers.dart';
import 'ha_connection.dart' show controllerProvider;
import 'scenes_provider.dart';

/// Executes a parsed intent against live devices/scenes.
/// Returns a human response ("Turned on Hue Go").
Future<String> executeVoiceCommand(Ref ref, String input) async {
  final intent = parseVoiceCommand(input);
  if (intent == null) {
    return "Sorry, I didn't understand that. Try \"turn on the kitchen "
        'light" or "set thermostat to 21".';
  }
  final devices = ref.read(devicesProvider);
  final controller = ref.read(controllerProvider);

  switch (intent) {
    case PowerIntent(:final query, :final on):
      if (isBroadcastQuery(query)) {
        final lightsOnly = query.contains('light');
        final targets = devices.where((d) =>
            d.has(CapabilityType.powerSwitch) &&
            (!lightsOnly ||
                d.has(CapabilityType.brightness) ||
                d.name.toLowerCase().contains('light')));
        var count = 0;
        for (final device in targets) {
          final cap = device.capability<PowerSwitchCapability>()!;
          try {
            await cap.executeCommand(controller, device, on);
            count++;
          } catch (_) {}
        }
        return 'Turned ${on ? 'on' : 'off'} $count device(s)';
      }
      final device = bestDeviceMatch(query, devices);
      final cap = device?.capability<PowerSwitchCapability>();
      if (device == null || cap == null) {
        return 'No switchable device matches "$query"';
      }
      await cap.executeCommand(controller, device, on);
      return 'Turned ${on ? 'on' : 'off'} ${device.name}';

    case SetValueIntent(:final query, :final value, :final unit):
      final device = bestDeviceMatch(query, devices);
      if (device == null) return 'No device matches "$query"';

      final target = device.capability<TargetTemperatureCapability>();
      final brightness = device.capability<BrightnessCapability>();
      // explicit unit wins; otherwise prefer what the device supports
      final useTemp =
          unit == 'degrees' || (unit.isEmpty && target != null);
      if (useTemp && target != null) {
        await target.executeCommand(controller, device, value);
        return 'Set ${device.name} to $value°';
      }
      if (brightness != null) {
        final pct = value.clamp(0, 100).toInt();
        await brightness.executeCommand(controller, device, pct);
        return 'Set ${device.name} to $pct%';
      }
      return "${device.name} can't do that";

    case SceneIntent(:final query):
      final scenes = ref.read(scenesProvider);
      Scene? best;
      var bestScore = 0.0;
      for (final scene in scenes) {
        final score = matchScore(query, scene.name, '');
        if (score > bestScore) {
          bestScore = score;
          best = scene;
        }
      }
      if (best == null || bestScore < 0.6) {
        return 'No scene matches "$query"';
      }
      await ref.read(scenesProvider.notifier).activate(best);
      return 'Scene "${best.name}" activated';
  }
}

final voiceExecutorProvider =
    Provider<Future<String> Function(String)>((ref) {
  return (input) => executeVoiceCommand(ref, input);
});
