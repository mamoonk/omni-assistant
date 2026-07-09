import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/device_providers.dart';

/// Picks a widget by the device's primary capability (§3.3).
class DeviceCard extends ConsumerWidget {
  final UniversalDevice device;
  const DeviceCard({super.key, required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(controllerProvider);
    return switch (device.primaryCapability) {
      CapabilityType.colorRgb ||
      CapabilityType.brightness =>
        _LightCard(device: device, controller: controller),
      CapabilityType.targetTemperature =>
        _ClimateCard(device: device, controller: controller),
      CapabilityType.powerSwitch =>
        _SwitchCard(device: device, controller: controller),
      CapabilityType.motion ||
      CapabilityType.contact =>
        _BinarySensorCard(device: device),
      _ => _SensorCard(device: device),
    };
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  final bool active;
  const _CardShell({required this.child, this.active = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  final UniversalDevice device;
  final IconData icon;
  final Widget? trailing;
  const _Header({required this.device, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            device.name,
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final UniversalDevice device;
  final DeviceController controller;
  const _SwitchCard({required this.device, required this.controller});

  @override
  Widget build(BuildContext context) {
    final power = device.capability<PowerSwitchCapability>()!;
    return _CardShell(
      active: power.on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Header(
            device: device,
            icon: Icons.power_settings_new,
            trailing: Switch(
              value: power.on,
              onChanged: (v) => power.executeCommand(controller, device, v),
            ),
          ),
          Text(power.on ? 'On' : 'Off',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LightCard extends StatelessWidget {
  final UniversalDevice device;
  final DeviceController controller;
  const _LightCard({required this.device, required this.controller});

  @override
  Widget build(BuildContext context) {
    final power = device.capability<PowerSwitchCapability>();
    final brightness = device.capability<BrightnessCapability>();
    final rgb = device.capability<ColorRgbCapability>();
    final on = power?.on ?? false;

    return _CardShell(
      active: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Header(
            device: device,
            icon: Icons.lightbulb,
            trailing: Switch(
              value: on,
              onChanged: power == null
                  ? null
                  : (v) => power.executeCommand(controller, device, v),
            ),
          ),
          if (rgb != null && on)
            Row(
              children: [
                for (final color in const [
                  (255, 180, 90),
                  (255, 255, 255),
                  (120, 190, 255),
                  (190, 120, 255),
                  (120, 255, 150),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => rgb.executeCommand(controller, device,
                          [color.$1, color.$2, color.$3]),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: Color.fromARGB(
                            255, color.$1, color.$2, color.$3),
                        child: (rgb.r, rgb.g, rgb.b) == color
                            ? const Icon(Icons.check, size: 14)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          if (brightness != null)
            Slider(
              value: brightness.level.toDouble(),
              max: 100,
              divisions: 20,
              label: '${brightness.level}%',
              onChanged: !on
                  ? null
                  : (v) => brightness.executeCommand(
                      controller, device, v.round()),
            ),
        ],
      ),
    );
  }
}

class _ClimateCard extends StatelessWidget {
  final UniversalDevice device;
  final DeviceController controller;
  const _ClimateCard({required this.device, required this.controller});

  @override
  Widget build(BuildContext context) {
    final target = device.capability<TargetTemperatureCapability>()!;
    final current = device.capabilities
        .whereType<SensorCapability>()
        .where((c) => c.type == CapabilityType.currentTemperature)
        .firstOrNull;
    final power = device.capability<PowerSwitchCapability>();
    final on = power?.on ?? true;

    return _CardShell(
      active: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Header(
            device: device,
            icon: Icons.thermostat,
            trailing: power == null
                ? null
                : Switch(
                    value: on,
                    onChanged: (v) =>
                        power.executeCommand(controller, device, v),
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: !on
                    ? null
                    : () => target.executeCommand(
                        controller, device, target.target - 0.5),
              ),
              Column(
                children: [
                  Text('${target.target}°',
                      style: Theme.of(context).textTheme.headlineSmall),
                  if (current?.value != null)
                    Text('now ${current!.value}${current.unit}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: !on
                    ? null
                    : () => target.executeCommand(
                        controller, device, target.target + 0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BinarySensorCard extends StatelessWidget {
  final UniversalDevice device;
  const _BinarySensorCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final sensor = device.capabilities
        .whereType<BinarySensorCapability>()
        .first;
    final isMotion = sensor.type == CapabilityType.motion;
    final label = isMotion
        ? (sensor.active ? 'Motion detected' : 'Clear')
        : (sensor.active ? 'Open' : 'Closed');
    return _CardShell(
      active: sensor.active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Header(
            device: device,
            icon: isMotion ? Icons.directions_run : Icons.sensor_door,
          ),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final UniversalDevice device;
  const _SensorCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final sensors = device.capabilities.whereType<SensorCapability>();
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Header(device: device, icon: Icons.sensors),
          Wrap(
            spacing: 12,
            children: [
              for (final s in sensors)
                Text('${s.value ?? '—'}${s.unit}',
                    style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}
