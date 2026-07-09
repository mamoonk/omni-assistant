import 'package:flutter_riverpod/flutter_riverpod.dart';

const _maxPoints = 60;

/// In-memory ring buffer of temperature readings per device id.
/// Feeds the sensor sparkline cards.
class HistoryNotifier extends Notifier<Map<String, List<num>>> {
  @override
  Map<String, List<num>> build() => const {};

  void record(String deviceId, num value) {
    final existing = state[deviceId] ?? const <num>[];
    if (existing.isNotEmpty && existing.last == value) return;
    final next = [...existing, value];
    if (next.length > _maxPoints) next.removeAt(0);
    state = {...state, deviceId: next};
  }

  void seed(String deviceId, List<num> values) =>
      state = {...state, deviceId: values.take(_maxPoints).toList()};
}

final historyProvider =
    NotifierProvider<HistoryNotifier, Map<String, List<num>>>(
        HistoryNotifier.new);
