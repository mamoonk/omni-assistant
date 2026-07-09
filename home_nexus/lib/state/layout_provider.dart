import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ha_connection.dart';

/// User-created tab with an explicit device set.
class CustomTab {
  final String id;
  final String name;
  final List<String> deviceIds;

  const CustomTab(
      {required this.id, required this.name, required this.deviceIds});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'deviceIds': deviceIds};

  factory CustomTab.fromJson(Map<String, dynamic> json) => CustomTab(
        id: json['id'] as String,
        name: json['name'] as String,
        deviceIds: (json['deviceIds'] as List).cast<String>(),
      );
}

/// Dashboard layout: one global device order, per-device column span,
/// and user-defined tabs. Persisted as a single JSON blob.
class DashboardLayout {
  final List<String> order;
  final Map<String, int> spans; // deviceId -> 1 or 2 columns
  final List<CustomTab> tabs;

  const DashboardLayout({
    this.order = const [],
    this.spans = const {},
    this.tabs = const [],
  });

  DashboardLayout copyWith({
    List<String>? order,
    Map<String, int>? spans,
    List<CustomTab>? tabs,
  }) =>
      DashboardLayout(
        order: order ?? this.order,
        spans: spans ?? this.spans,
        tabs: tabs ?? this.tabs,
      );

  Map<String, dynamic> toJson() => {
        'order': order,
        'spans': spans,
        'tabs': [for (final t in tabs) t.toJson()],
      };

  factory DashboardLayout.fromJson(Map<String, dynamic> json) =>
      DashboardLayout(
        order: (json['order'] as List?)?.cast<String>() ?? const [],
        spans: ((json['spans'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        tabs: [
          for (final t in (json['tabs'] as List? ?? const []))
            CustomTab.fromJson((t as Map).cast<String, dynamic>()),
        ],
      );
}

class LayoutNotifier extends Notifier<DashboardLayout> {
  @override
  DashboardLayout build() => const DashboardLayout();

  void load(String? json) {
    if (json == null) return;
    state =
        DashboardLayout.fromJson((jsonDecode(json) as Map).cast<String, dynamic>());
  }

  /// Sorts [deviceIds] by the saved global order; unknown ids keep their
  /// incoming relative order at the end.
  List<String> sorted(List<String> deviceIds) {
    final rank = {
      for (var i = 0; i < state.order.length; i++) state.order[i]: i
    };
    final list = [...deviceIds];
    list.sort((a, b) =>
        (rank[a] ?? 1 << 30).compareTo(rank[b] ?? 1 << 30));
    return list;
  }

  int spanOf(String deviceId) => state.spans[deviceId] ?? 1;

  /// Moves [dragged] immediately before [target] in the global order.
  Future<void> moveBefore(
      String dragged, String target, List<String> visibleIds) async {
    if (dragged == target) return;
    // ensure every currently visible device exists in the order list
    final order = [
      ...state.order,
      ...visibleIds.where((id) => !state.order.contains(id)),
    ]..remove(dragged);
    final at = order.indexOf(target);
    order.insert(at < 0 ? order.length : at, dragged);
    state = state.copyWith(order: order);
    await _persist();
  }

  Future<void> toggleSpan(String deviceId) async {
    state = state.copyWith(spans: {
      ...state.spans,
      deviceId: spanOf(deviceId) == 1 ? 2 : 1,
    });
    await _persist();
  }

  Future<void> addTab(String name, List<String> deviceIds) async {
    final id = 'tab_${state.tabs.length}_${name.hashCode.toRadixString(16)}';
    state = state.copyWith(
        tabs: [...state.tabs, CustomTab(id: id, name: name, deviceIds: deviceIds)]);
    await _persist();
  }

  Future<void> removeTab(String id) async {
    state =
        state.copyWith(tabs: state.tabs.where((t) => t.id != id).toList());
    await _persist();
  }

  Future<void> _persist() async {
    final store = await ref.read(localStoreProvider.future);
    await store.saveLayoutJson(jsonEncode(state.toJson()));
  }
}

final layoutProvider =
    NotifierProvider<LayoutNotifier, DashboardLayout>(LayoutNotifier.new);

/// Dashboard edit mode (drag to reorder, resize, manage tabs/scenes).
final editModeProvider = StateProvider<bool>((ref) => false);
