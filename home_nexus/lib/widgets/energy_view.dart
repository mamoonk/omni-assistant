import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/device_providers.dart';

/// Energy tab (§7 polish): total live draw + per-device power/energy.
class EnergyView extends ConsumerWidget {
  const EnergyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref
        .watch(devicesProvider)
        .where((d) =>
            d.has(CapabilityType.power) || d.has(CapabilityType.energy))
        .toList()
      ..sort((a, b) =>
          (_power(b) ?? 0).compareTo(_power(a) ?? 0)); // biggest draw first

    final totalW = devices.fold<num>(0, (sum, d) => sum + (_power(d) ?? 0));
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('Current draw',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${totalW.toStringAsFixed(totalW < 10 ? 1 : 0)} W',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text('${devices.length} metered device(s)',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final device in devices)
          ListTile(
            leading: const Icon(Icons.bolt),
            title: Text(device.name),
            subtitle: Text(device.roomId),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_power(device) != null) Text('${_power(device)} W'),
                if (_energy(device) != null)
                  Text('${_energy(device)} kWh',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }

  num? _power(UniversalDevice d) => d.capabilities
      .whereType<SensorCapability>()
      .where((c) => c.type == CapabilityType.power)
      .firstOrNull
      ?.value;

  num? _energy(UniversalDevice d) => d.capabilities
      .whereType<SensorCapability>()
      .where((c) => c.type == CapabilityType.energy)
      .firstOrNull
      ?.value;
}
