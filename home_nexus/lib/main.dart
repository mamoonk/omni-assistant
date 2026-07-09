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
import 'state/kiosk_provider.dart';
import 'state/layout_provider.dart';
import 'state/mqtt_connection.dart';
import 'state/bridge_connection.dart';
import 'theme/ambient.dart';
import 'widgets/screensaver.dart';
import 'widgets/ambient_header.dart';
import 'widgets/device_card.dart';
import 'widgets/energy_view.dart';
import 'widgets/new_tab_dialog.dart';
import 'widgets/scene_bar.dart';
import 'widgets/voice_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initKioskSupport();
  runApp(const ProviderScope(child: HomeNexusApp()));
}

class HomeNexusApp extends ConsumerWidget {
  const HomeNexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      themeMode: ref.watch(themeModeProvider),
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

/// A dashboard section: implicit all/room tabs, the energy view, or a user tab.
class _TabSpec {
  final String title;
  final IconData icon;
  final String? room; // room filter
  final CustomTab? custom; // explicit device list
  final bool energy;

  const _TabSpec.all()
      : title = 'All Devices',
        icon = Icons.grid_view_rounded,
        room = null,
        custom = null,
        energy = false;
  _TabSpec.room(String this.room)
      : title = room,
        icon = _roomIcon(room),
        custom = null,
        energy = false;
  _TabSpec.custom(CustomTab this.custom)
      : title = custom.name,
        icon = Icons.dashboard_customize_outlined,
        room = null,
        energy = false;
  const _TabSpec.energy()
      : title = 'Energy',
        icon = Icons.bolt,
        room = null,
        custom = null,
        energy = true;

  static IconData _roomIcon(String room) {
    final r = room.toLowerCase();
    if (r.contains('living')) return Icons.weekend_outlined;
    if (r.contains('kitchen')) return Icons.kitchen_outlined;
    if (r.contains('bed')) return Icons.bed_outlined;
    if (r.contains('bath')) return Icons.bathtub_outlined;
    if (r.contains('hall')) return Icons.sensor_door_outlined;
    if (r.contains('office')) return Icons.desk_outlined;
    if (r.contains('garage')) return Icons.garage_outlined;
    if (r.contains('zigbee')) return Icons.hub_outlined;
    return Icons.meeting_room_outlined;
  }
}

/// Echo Show/Hub-style ambient dashboard: always dark, time-of-day gradient,
/// oversized clock, frosted tiles. Side rail on wide (wall-mount landscape)
/// screens, pill row on phones.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsProvider);
    final layout = ref.watch(layoutProvider);
    final editing = ref.watch(editModeProvider);
    final hasEnergy = ref.watch(devicesProvider).any((d) =>
        d.has(CapabilityType.power) || d.has(CapabilityType.energy));

    final tabs = <_TabSpec>[
      const _TabSpec.all(),
      if (hasEnergy) const _TabSpec.energy(),
      for (final room in rooms) _TabSpec.room(room),
      for (final tab in layout.tabs) _TabSpec.custom(tab),
    ];
    final selected = min(_selected, tabs.length - 1);
    final tab = tabs[selected];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final kiosk = ref.watch(kioskProvider);
    final actions = <Widget>[
      const _ConnectionIndicator(),
      AmbientIconButton(
        icon: Icons.mic_none,
        tooltip: 'Voice / command',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const VoiceSheet(),
        ),
      ),
      AmbientIconButton(
        icon: kiosk ? Icons.fullscreen_exit : Icons.fullscreen,
        tooltip: kiosk ? 'Exit display mode' : 'Display mode',
        highlighted: kiosk,
        onPressed: () => setKioskMode(ref, !kiosk),
      ),
      AmbientIconButton(
        icon: Icons.add,
        tooltip: 'Add device',
        onPressed: () => _pickAddFlow(context),
      ),
      AmbientIconButton(
        icon: Icons.auto_awesome_outlined,
        tooltip: 'Automations',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AutomationsScreen()),
        ),
      ),
      if (editing)
        AmbientIconButton(
          icon: Icons.tab,
          tooltip: 'New tab',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const NewTabDialog(),
          ),
        ),
      AmbientIconButton(
        icon: editing ? Icons.check : Icons.edit_outlined,
        tooltip: editing ? 'Done editing' : 'Edit dashboard',
        highlighted: editing,
        onPressed: () =>
            ref.read(editModeProvider.notifier).state = !editing,
      ),
      AmbientIconButton(
        icon: Icons.settings_outlined,
        tooltip: 'Connections',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmbientHeader(actions: actions),
        const SceneBar(),
        if (!wide) _TabPills(
          tabs: tabs,
          selected: selected,
          editing: editing,
          onSelect: (i) => setState(() => _selected = i),
          onDeleteCustom: (t) => _confirmDeleteTab(context, t),
        ),
        Expanded(
          child: tab.energy
              ? const EnergyView()
              : _DeviceGrid(room: tab.room, custom: tab.custom),
        ),
      ],
    );

    return Theme(
      data: Ambient.theme(),
      child: Builder(
        builder: (context) => IdleScreensaver(
          child: Container(
          decoration: BoxDecoration(
            gradient: Ambient.backgroundGradient(DateTime.now().hour),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: !wide
                  ? content
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SideRail(
                          tabs: tabs,
                          selected: selected,
                          editing: editing,
                          onSelect: (i) => setState(() => _selected = i),
                          onDeleteCustom: (t) =>
                              _confirmDeleteTab(context, t),
                        ),
                        Expanded(child: content),
                      ],
                    ),
            ),
          ),
          ),
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
              title: const Text('Zigbee / Z-Wave / Matter device'),
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

  void _confirmDeleteTab(BuildContext context, CustomTab tab) {
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
              setState(() => _selected = 0);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Horizontal pill navigation (phone / portrait).
class _TabPills extends StatelessWidget {
  final List<_TabSpec> tabs;
  final int selected;
  final bool editing;
  final ValueChanged<int> onSelect;
  final ValueChanged<CustomTab> onDeleteCustom;

  const _TabPills({
    required this.tabs,
    required this.selected,
    required this.editing,
    required this.onSelect,
    required this.onDeleteCustom,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      // non-lazy: every pill exists even off-screen (small count anyway)
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          spacing: 8,
          children: [
            for (final (i, tab) in tabs.indexed) _pill(context, i, tab),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, int i, _TabSpec tab) {
    final isSelected = i == selected;
    return GestureDetector(
      onTap: () => onSelect(i),
      onLongPress: editing && tab.custom != null
          ? () => onDeleteCustom(tab.custom!)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: Ambient.pill(selected: isSelected),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon,
                size: 16,
                color:
                    Colors.white.withValues(alpha: isSelected ? 0.95 : 0.6)),
            const SizedBox(width: 6),
            Text(
              tab.title,
              style: TextStyle(
                color:
                    Colors.white.withValues(alpha: isSelected ? 0.95 : 0.65),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (editing && tab.custom != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.close, size: 13, color: Colors.white54),
            ],
          ],
        ),
      ),
    );
  }
}

/// Echo Hub-style left rail (wall-mount / tablet landscape).
class _SideRail extends StatelessWidget {
  final List<_TabSpec> tabs;
  final int selected;
  final bool editing;
  final ValueChanged<int> onSelect;
  final ValueChanged<CustomTab> onDeleteCustom;

  const _SideRail({
    required this.tabs,
    required this.selected,
    required this.editing,
    required this.onSelect,
    required this.onDeleteCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      margin: const EdgeInsets.fromLTRB(16, 20, 4, 20),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListView(
        children: [
          for (final (i, tab) in tabs.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: GestureDetector(
                onLongPress: editing && tab.custom != null
                    ? () => onDeleteCustom(tab.custom!)
                    : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onSelect(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: i == selected
                          ? Ambient.pill(selected: true)
                          : null,
                      child: Row(
                        children: [
                          Icon(tab.icon,
                              size: 20,
                              color: Colors.white.withValues(
                                  alpha: i == selected ? 0.95 : 0.55)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tab.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(
                                    alpha: i == selected ? 0.95 : 0.65),
                                fontWeight: i == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (editing && tab.custom != null)
                            const Icon(Icons.close,
                                size: 14, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
    final statuses = [
      ref.watch(haConnectionProvider).status,
      ref.watch(mqttConnectionProvider).status,
      ref.watch(bridgeConnectionProvider).status,
    ];
    final anyConnected = statuses.contains(HaStatus.connected);
    final anyTrouble = statuses.any(
        (s) => s == HaStatus.error || s == HaStatus.reconnecting);
    final (icon, color, tip) = anyTrouble
        ? (Icons.cloud_off, Colors.orangeAccent, 'Connection trouble')
        : anyConnected
            ? (Icons.cloud_done, Ambient.accent, 'Connected')
            : (Icons.cloud_off, Colors.white38, 'Offline');
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, right: 4),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _DeviceGrid extends ConsumerWidget {
  final String? room; // null = all
  final CustomTab? custom;
  const _DeviceGrid({required this.room, this.custom});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(devicesProvider);
    final layoutNotifier = ref.watch(layoutProvider.notifier);
    ref.watch(layoutProvider); // rebuild on order/span changes
    final editing = ref.watch(editModeProvider);

    final filtered = all.where((d) {
      if (custom != null) return custom!.deviceIds.contains(d.id);
      if (room != null) return d.roomId == room;
      return true;
    }).toList();

    final orderedIds = layoutNotifier.sorted([for (final d in filtered) d.id]);
    final byId = {for (final d in filtered) d.id: d};
    final devices = [for (final id in orderedIds) byId[id]!];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 230).floor().clamp(2, 6);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: StaggeredGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            children: [
              for (final device in devices)
                StaggeredGridTile.count(
                  crossAxisCellCount:
                      min(layoutNotifier.spanOf(device.id), columns),
                  mainAxisCellCount: 0.78,
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
