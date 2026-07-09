import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/settings_screen.dart';
import 'state/device_providers.dart';
import 'state/ha_connection.dart';
import 'widgets/device_card.dart';

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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider);
    final tabs = ['All Devices', ...rooms];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Home Nexus'),
          actions: [
            const _ConnectionIndicator(),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Home Assistant connection',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final t in tabs) Tab(text: t)],
          ),
        ),
        body: TabBarView(
          children: [
            const _DeviceGrid(room: null),
            for (final room in rooms) _DeviceGrid(room: room),
          ],
        ),
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
  /// null = all devices
  final String? room;
  const _DeviceGrid({required this.room});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref
        .watch(devicesProvider)
        .where((d) => room == null || d.roomId == room)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 210).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: devices.length,
          itemBuilder: (context, i) => DeviceCard(device: devices[i]),
        );
      },
    );
  }
}
