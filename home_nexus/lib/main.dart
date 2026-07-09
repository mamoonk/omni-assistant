import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:unification/unification.dart';

import 'screens/add_device_screen.dart';
import 'screens/automations_screen.dart';
import 'screens/manual_ip_screen.dart';
import 'screens/settings_screen.dart';
import 'state/device_providers.dart';
import 'state/ha_connection.dart';
import 'state/layout_provider.dart';
import 'widgets/device_card.dart';
import 'widgets/new_tab_dialog.dart';
import 'widgets/scene_bar.dart';

void main() => runApp(const ProviderScope(child: HomeNexusApp()));

class HomeNexusApp extends StatelessWidget {
  const HomeNexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Nexus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4E7FFF),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4E7FFF),
        brightness: Brightness.dark,
      ),
      home: const _Bootstrap(),
    );
  }
}

/// Loads the device cache and kicks off auto-connect before showing the
/// dashboard, so offline cold starts render instantly from cache.
class _Bootstrap extends ConsumerWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    return boot.when(
      data: (_) => const DashboardScreen(),
      error: (_, _) => const DashboardScreen(),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// A dashboard tab: either the implicit all/room tabs or a user tab.
class _TabSpec {
  final String title;
  final String? room; // room filter
  final CustomTab? custom; // explicit device list
  const _TabSpec.all() : title = 'All Devices', room = null, custom = null;
  const _TabSpec.room(String this.room) : title = room, custom = null;
  _TabSpec.custom(CustomTab this.custom) : title = custom.name, room = null;
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider);
    final layout = ref.watch(layoutProvider);
    final editing = ref.watch(editModeProvider);
    final tabs = <_TabSpec>[
      const _TabSpec.all(),
      for (final room in rooms) _TabSpec.room(room),
      for (final tab in layout.tabs) _TabSpec.custom(tab),
    ];

    return DefaultTabController(
      key: ValueKey('tabs_${tabs.length}'),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Home Nexus'),
          actions: [
            const _ConnectionIndicator(),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add device',
              onPressed: () => _pickAddFlow(context),
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Automations',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AutomationsScreen()),
              ),
            ),
            if (editing)
              IconButton(
                icon: const Icon(Icons.tab),
                tooltip: 'New tab',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const NewTabDialog(),
                ),
              ),
            IconButton(
              icon: Icon(editing ? Icons.check : Icons.edit_outlined),
              tooltip: editing ? 'Done editing' : 'Edit dashboard',
              onPressed: () =>
                  ref.read(editModeProvider.notifier).state = !editing,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Connections',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final tab in tabs)
                Tab(
                  child: GestureDetector(
                    onLongPress: editing && tab.custom != null
                        ? () => _confirmDeleteTab(context, ref, tab.custom!)
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tab.title),
                        if (editing && tab.custom != null) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.close, size: 14),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        body: Column(
          children: [
            const SceneBar(),
            Expanded(
              child: TabBarView(
                children: [for (final tab in tabs) _DeviceGrid(tab: tab)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickAddFlow(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Zigbee / Z-Wave device'),
              subtitle: const Text('Guided inclusion via Nexus Bridge'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AddDeviceScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Generic IP device'),
              subtitle: const Text('HTTP switch, light, or sensor'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ManualIpScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTab(BuildContext context, WidgetRef ref, CustomTab tab) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete tab "${tab.name}"?'),
        content: const Text('Devices stay on the dashboard.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(layoutProvider.notifier).removeTab(tab.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ConnectionIndicator extends ConsumerWidget {
  const _ConnectionIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(haConnectionProvider);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, tip) = switch (conn.status) {
      HaStatus.connected => (Icons.cloud_done, scheme.primary, 'Connected'),
      HaStatus.connecting => (Icons.cloud_sync, scheme.tertiary, 'Connecting…'),
      HaStatus.reconnecting => (
          Icons.cloud_sync,
          scheme.tertiary,
          'Reconnecting…'
        ),
      HaStatus.error => (Icons.cloud_off, scheme.error, 'Connection failed'),
      HaStatus.disconnected => (Icons.cloud_off, scheme.outline, 'Offline'),
    };
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _DeviceGrid extends ConsumerWidget {
  final _TabSpec tab;
  const _DeviceGrid({required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(devicesProvider);
    final layoutNotifier = ref.watch(layoutProvider.notifier);
    ref.watch(layoutProvider); // rebuild on order/span changes
    final editing = ref.watch(editModeProvider);

    final filtered = all.where((d) {
      if (tab.custom != null) return tab.custom!.deviceIds.contains(d.id);
      if (tab.room != null) return d.roomId == tab.room;
      return true;
    }).toList();

    final orderedIds = layoutNotifier.sorted([for (final d in filtered) d.id]);
    final byId = {for (final d in filtered) d.id: d};
    final devices = [for (final id in orderedIds) byId[id]!];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 210).floor().clamp(2, 6);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: StaggeredGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (final device in devices)
                StaggeredGridTile.count(
                  crossAxisCellCount:
                      min(layoutNotifier.spanOf(device.id), columns),
                  mainAxisCellCount: 0.75,
                  child: _EditableTile(
                    device: device,
                    editing: editing,
                    orderedIds: orderedIds,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Wraps a card with drag-to-reorder and span toggling in edit mode.
class _EditableTile extends ConsumerWidget {
  final UniversalDevice device;
  final bool editing;
  final List<String> orderedIds;

  const _EditableTile({
    required this.device,
    required this.editing,
    required this.orderedIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = DeviceCard(device: device);
    if (!editing) return card;

    return LongPressDraggable<String>(
      data: device.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 200, height: 150, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: DragTarget<String>(
        onAcceptWithDetails: (details) => ref
            .read(layoutProvider.notifier)
            .moveBefore(details.data, device.id, orderedIds),
        builder: (context, candidates, _) => Stack(
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: candidates.isEmpty ? 1 : 0.5,
              child: card,
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: IconButton(
                icon: const Icon(Icons.aspect_ratio, size: 18),
                tooltip: 'Toggle width',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(layoutProvider.notifier).toggleSpan(device.id),
              ),
            ),
            const Positioned(
              left: 6,
              bottom: 6,
              child: Icon(Icons.drag_indicator, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
