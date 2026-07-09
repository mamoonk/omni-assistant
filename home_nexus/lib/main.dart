import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/device_providers.dart';
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
      home: const DashboardScreen(),
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
