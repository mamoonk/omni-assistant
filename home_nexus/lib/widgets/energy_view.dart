import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/device_providers.dart';
import '../theme/ambient.dart';

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          decoration: Ambient.tile(active: true),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Current draw',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75))),
              Text(
                '${totalW.toStringAsFixed(totalW < 10 ? 1 : 0)} W',
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                ),
              ),
              Text('${devices.length} metered device(s)',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final device in devices)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: Ambient.tile(),
            child: ListTile(
              leading: const Icon(Icons.bolt, color: Ambient.accent),
              title: Text(device.name,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(device.roomId,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55))),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_power(device) != null)
                    Text('${_power(device)} W',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16)),
                  if (_energy(device) != null)
                    Text('${_energy(device)} kWh',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6))),
                ],
              ),
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
