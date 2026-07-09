import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/kiosk_provider.dart';
import '../theme/ambient.dart';

const _idleTimeout = Duration(minutes: 3);

/// In kiosk mode, [_idleTimeout] without touches fades to an ambient clock
/// (Echo Show style). The clock drifts to a new position every minute to
/// avoid OLED burn-in. Any tap returns to the dashboard.
class IdleScreensaver extends ConsumerStatefulWidget {
  final Widget child;
  const IdleScreensaver({super.key, required this.child});

  @override
  ConsumerState<IdleScreensaver> createState() => _IdleScreensaverState();
}

class _IdleScreensaverState extends ConsumerState<IdleScreensaver> {
  DateTime _lastInteraction = DateTime.now();
  bool _saving = false;
  Timer? _checker;

  @override
  void initState() {
    super.initState();
    _checker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final kiosk = ref.read(kioskProvider);
      final idle = DateTime.now().difference(_lastInteraction) > _idleTimeout;
      if (kiosk && idle && !_saving) setState(() => _saving = true);
      if ((!kiosk || !idle) && _saving) setState(() => _saving = false);
    });
  }

  @override
  void dispose() {
    _checker?.cancel();
    super.dispose();
  }

  void _touch() {
    _lastInteraction = DateTime.now();
    if (_saving) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      onPointerMove: (_) => _touch(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: _saving
                ? _AmbientClock(key: const ValueKey('saver'), onTap: _touch)
                : const SizedBox.shrink(key: ValueKey('off')),
          ),
        ],
      ),
    );
  }
}

class _AmbientClock extends StatefulWidget {
  final VoidCallback onTap;
  const _AmbientClock({super.key, required this.onTap});

  @override
  State<_AmbientClock> createState() => _AmbientClockState();
}

class _AmbientClockState extends State<_AmbientClock> {
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

  @override
  Widget build(BuildContext context) {
    final time = '${_now.hour.toString().padLeft(2, '0')}'
        ':${_now.minute.toString().padLeft(2, '0')}';
    // deterministic per-minute drift keeps pixels moving (burn-in safety)
    final seed = _now.hour * 60 + _now.minute;
    final dx = ((seed * 37) % 100 - 50) / 100.0 * 0.5;
    final dy = ((seed * 53) % 100 - 50) / 100.0 * 0.5;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFF05070D)),
        child: AnimatedAlign(
          duration: const Duration(seconds: 2),
          curve: Curves.easeInOut,
          alignment: Alignment(dx, dy),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.w100,
                  color: Colors.white.withValues(alpha: 0.85),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '${_now.day}.${_now.month}.${_now.year}',
                style: TextStyle(
                  fontSize: 18,
                  color: Ambient.accent.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
