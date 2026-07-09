import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/device_providers.dart';
import '../theme/ambient.dart';

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];

/// Echo Show-style header: oversized clock, date + greeting, average indoor
/// temperature, and a row of frosted action buttons.
class AmbientHeader extends ConsumerStatefulWidget {
  final List<Widget> actions;
  const AmbientHeader({super.key, this.actions = const []});

  @override
  ConsumerState<AmbientHeader> createState() => _AmbientHeaderState();
}

class _AmbientHeaderState extends ConsumerState<AmbientHeader> {
  late DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _greeting => switch (_now.hour) {
        >= 5 && < 12 => 'Good morning',
        >= 12 && < 17 => 'Good afternoon',
        _ => 'Good evening',
      };

  num? _indoorTemp() {
    final values = <num>[
      for (final device in ref.watch(devicesProvider))
        for (final cap in device.capabilities)
          if (cap is SensorCapability &&
              cap.type == CapabilityType.currentTemperature &&
              cap.value != null)
            cap.value!,
    ];
    if (values.isEmpty) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    return (mean * 10).round() / 10;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final time = '${_now.hour.toString().padLeft(2, '0')}'
        ':${_now.minute.toString().padLeft(2, '0')}';
    final date = '${_weekdays[_now.weekday - 1]}, '
        '${_months[_now.month - 1]} ${_now.day}';
    final temp = _indoorTemp();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: compact ? 48 : 64,
                        fontWeight: FontWeight.w200,
                        height: 1,
                        letterSpacing: -1,
                        color: Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (temp != null) ...[
                      const SizedBox(width: 20),
                      Icon(Icons.home_outlined,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        '$temp°',
                        style: TextStyle(
                          fontSize: compact ? 20 : 26,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_greeting  ·  $date',
                  style: TextStyle(
                    fontSize: compact ? 13 : 15,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          Wrap(spacing: 8, children: widget.actions),
        ],
      ),
    );
  }
}

/// Frosted circular icon button used in the header action row.
class AmbientIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool highlighted;

  const AmbientIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: highlighted
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: Ambient.accent.withValues(alpha: 0.30),
                border: Border.all(
                    color: Ambient.accent.withValues(alpha: 0.55)),
              )
            : Ambient.circleButton(),
        child: IconButton(
          icon: Icon(icon, size: 20),
          color: Colors.white.withValues(alpha: 0.9),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
