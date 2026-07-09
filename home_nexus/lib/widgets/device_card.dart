import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/bridge_connection.dart';
import '../state/ha_connection.dart';
import '../state/history_provider.dart';
import '../state/mqtt_connection.dart';
import '../theme/ambient.dart';
import 'color_wheel.dart';
import 'sparkline.dart';

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: Ambient.tile(active: active),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _Header extends ConsumerWidget {
  final UniversalDevice device;
  final IconData icon;
  final Widget? trailing;
  final bool active;
  const _Header({
    required this.device,
    required this.icon,
    this.trailing,
    this.active = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // device shown while its source connection is down = stale data
    final status = switch (device.origin.type) {
      OriginType.homeAssistant => ref.watch(haConnectionProvider).status,
      OriginType.mqtt => ref.watch(mqttConnectionProvider).status,
      OriginType.nexusBridge => ref.watch(bridgeConnectionProvider).status,
      _ => HaStatus.connected,
    };
    final stale = device.origin.connectionId != 'mock' &&
        status != HaStatus.connected;

    return Row(
      children: [
        Icon(
          icon,
          size: 26,
          color: active
              ? Ambient.accent
              : Colors.white.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            device.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (stale)
          Tooltip(
            message: 'Offline — showing last known state',
            child: Icon(
              Icons.cloud_off,
              size: 16,
              color: Colors.white.withValues(alpha: 0.4),
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
            active: power.on,
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
            active: on,
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
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromARGB(255, rgb.r, rgb.g, rgb.b),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.palette_outlined, size: 20),
                  tooltip: 'Pick color',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final color = await showColorWheelDialog(
                      context,
                      Color.fromARGB(255, rgb.r, rgb.g, rgb.b),
                    );
                    if (color != null) {
                      await rgb.executeCommand(controller, device, [
                        (color.r * 255).round(),
                        (color.g * 255).round(),
                        (color.b * 255).round(),
                      ]);
                    }
                  },
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
            active: on,
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
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: !on
                    ? null
                    : () => target.executeCommand(
                        controller, device, target.target - 0.5),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    children: [
                      Text('${target.target}°',
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (current?.value != null)
                        Text('now ${current!.value}${current.unit}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
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
            active: sensor.active,
          ),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SensorCard extends ConsumerWidget {
  final UniversalDevice device;
  const _SensorCard({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensors = device.capabilities.whereType<SensorCapability>();
    final history = ref.watch(historyProvider)[device.id] ?? const <num>[];

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
          if (history.length >= 2)
            Sparkline(
              values: history,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }
}
