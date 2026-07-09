import 'package:unification/unification.dart';

/// Natural-language command engine ("voice brain"). Pure Dart so the same
/// intents work from mic transcription and typed commands, and it's fully
/// unit-testable.
sealed class VoiceIntent {
  const VoiceIntent();
}

/// "turn on the kitchen light" / "switch everything off"
class PowerIntent extends VoiceIntent {
  final String query; // device words; 'everything'/'all ...' = broadcast
  final bool on;
  const PowerIntent({required this.query, required this.on});
}

/// "set hue go to 50 percent" / "dim the ceiling light to 30"
/// "set thermostat to 21.5 degrees" — unit resolves the capability.
class SetValueIntent extends VoiceIntent {
  final String query;
  final num value;
  final String unit; // 'percent' | 'degrees' | ''
  const SetValueIntent(
      {required this.query, required this.value, this.unit = ''});
}

/// "activate scene movie night" / "run the evening scene"
class SceneIntent extends VoiceIntent {
  final String query;
  const SceneIntent({required this.query});
}

final _powerA = RegExp(r'^(?:turn|switch)\s+(on|off)\s+(?:the\s+)?(.+)$');
final _powerB = RegExp(r'^(?:turn|switch)\s+(?:the\s+)?(.+?)\s+(on|off)$');
final _scene = RegExp(
    r'^(?:run|activate|start|play)\s+(?:the\s+)?(?:scene\s+)?(.+?)(?:\s+scene)?$');
final _setValue = RegExp(
    r'^(?:set|dim|brighten)\s+(?:the\s+)?(.+?)\s+(?:temperature\s+)?to\s+(-?\d+(?:\.\d+)?)\s*(percent|%|degrees?|°c?)?$');

VoiceIntent? parseVoiceCommand(String input) {
  final text = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w%°.\s-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return null;

  if (_setValue.firstMatch(text) case final m?) {
    final rawUnit = m.group(3) ?? '';
    final unit = rawUnit.startsWith('deg') || rawUnit.startsWith('°')
        ? 'degrees'
        : (rawUnit.isNotEmpty || text.startsWith('dim') || text.startsWith('brighten'))
            ? 'percent'
            : '';
    return SetValueIntent(
      query: m.group(1)!,
      value: num.parse(m.group(2)!),
      unit: unit,
    );
  }
  if (_powerA.firstMatch(text) case final m?) {
    return PowerIntent(query: m.group(2)!, on: m.group(1) == 'on');
  }
  if (_powerB.firstMatch(text) case final m?) {
    return PowerIntent(query: m.group(1)!, on: m.group(2) == 'on');
  }
  // scene phrasing only when it can't be a power/set command
  if (_scene.firstMatch(text) case final m?) {
    return SceneIntent(query: m.group(1)!);
  }
  return null;
}

bool isBroadcastQuery(String query) {
  final q = query.trim();
  return q == 'everything' ||
      q == 'all' ||
      q.startsWith('all ') ||
      q == 'all devices' ||
      q == 'the lights' ||
      q == 'lights';
}

/// Token-overlap score of [query] against a device's name + room.
/// 0 = no match; higher is better.
double matchScore(String query, String name, String room) {
  final queryTokens = _tokens(query);
  if (queryTokens.isEmpty) return 0;
  final target = {..._tokens(name), ..._tokens(room)};
  var hits = 0;
  for (final token in queryTokens) {
    if (target.any((t) => t.startsWith(token) || token.startsWith(t))) hits++;
  }
  if (hits == 0) return 0;
  // all query tokens should land; partial coverage scores low
  return hits / queryTokens.length + hits * 0.01;
}

Set<String> _tokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'[\s_\-]+'))
    .where((t) => t.isNotEmpty && !const {'the', 'a', 'my'}.contains(t))
    .toSet();

UniversalDevice? bestDeviceMatch(
    String query, List<UniversalDevice> devices) {
  UniversalDevice? best;
  var bestScore = 0.0;
  for (final device in devices) {
    final score = matchScore(query, device.name, device.roomId);
    if (score > bestScore) {
      bestScore = score;
      best = device;
    }
  }
  return bestScore >= 0.6 ? best : null;
}
