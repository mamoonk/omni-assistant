import 'dart:math';

import 'package:flutter/material.dart';

/// Hue ring picker. Returns the chosen color via [onChanged].
class ColorWheel extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;
  const ColorWheel({super.key, required this.initial, required this.onChanged});

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  late double _hue = HSVColor.fromColor(widget.initial).hue;

  Color get _color => HSVColor.fromAHSV(1, _hue, 1, 1).toColor();

  void _update(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    setState(() => _hue = (atan2(v.dy, v.dx) * 180 / pi + 360) % 360);
    widget.onChanged(_color);
  }

  @override
  Widget build(BuildContext context) {
    const size = Size(220, 220);
    return GestureDetector(
      onPanDown: (d) => _update(d.localPosition, size),
      onPanUpdate: (d) => _update(d.localPosition, size),
      child: CustomPaint(
        size: size,
        painter: _WheelPainter(hue: _hue, selected: _color),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double hue;
  final Color selected;
  _WheelPainter({required this.hue, required this.selected});

  static const _ringWidth = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - _ringWidth / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth
        ..shader = SweepGradient(
          colors: [
            for (var h = 0; h <= 360; h += 30)
              HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor(),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // selector thumb on the ring
    final angle = hue * pi / 180;
    final thumb = center + Offset(cos(angle), sin(angle)) * radius;
    canvas.drawCircle(thumb, _ringWidth / 2 + 3,
        Paint()..color = Colors.white);
    canvas.drawCircle(thumb, _ringWidth / 2 - 1, Paint()..color = selected);

    // center preview
    canvas.drawCircle(center, radius - _ringWidth - 6,
        Paint()..color = selected);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hue != hue;
}

/// Opens the wheel in a dialog; resolves with the picked color or null.
Future<Color?> showColorWheelDialog(BuildContext context, Color initial) {
  var picked = initial;
  return showDialog<Color>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Color'),
      content: ColorWheel(initial: initial, onChanged: (c) => picked = c),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, picked),
          child: const Text('Apply'),
        ),
      ],
    ),
  );
}
