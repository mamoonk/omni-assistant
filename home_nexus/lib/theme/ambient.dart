import 'package:flutter/material.dart';

/// Echo Show/Hub-style ambient styling: the dashboard is always dark,
/// tiles are frosted glass over a time-of-day gradient.
abstract final class Ambient {
  static const accent = Color(0xFF00A8E1); // Alexa cyan

  static ThemeData theme() => ThemeData(
        colorSchemeSeed: accent,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        splashFactory: InkSparkle.splashFactory,
      );

  /// Background gradient shifts with the hour, like Echo's ambient clock.
  static LinearGradient backgroundGradient(int hour) {
    final (top, bottom) = switch (hour) {
      >= 5 && < 9 => (const Color(0xFF1B2A4A), const Color(0xFF7A4A2B)), // dawn
      >= 9 && < 17 => (const Color(0xFF16263D), const Color(0xFF2B4A6F)), // day
      >= 17 && < 21 => (const Color(0xFF23204A), const Color(0xFF6F2B4A)), // dusk
      _ => (const Color(0xFF0B1020), const Color(0xFF1B2340)), // night
    };
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bottom],
    );
  }

  /// Frosted tile decoration; [active] gets the cyan glow.
  static BoxDecoration tile({bool active = false}) => BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: active
            ? accent.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.07),
        border: Border.all(
          color: active
              ? accent.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.10),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ]
            : null,
      );

  /// Small frosted circle for header action buttons.
  static BoxDecoration circleButton() => BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      );

  /// Navigation pill (tab chip / rail entry).
  static BoxDecoration pill({required bool selected}) => BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: selected
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.08),
        ),
      );
}
