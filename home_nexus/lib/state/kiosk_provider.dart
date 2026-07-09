import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

/// Kiosk (centerpiece) mode: fullscreen, screen kept awake, idle
/// screensaver armed.
final kioskProvider = StateProvider<bool>((ref) => false);

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

Future<void> setKioskMode(WidgetRef ref, bool on) async {
  ref.read(kioskProvider.notifier).state = on;

  // every platform effect is best-effort; kiosk state itself always applies
  try {
    if (_isDesktop) {
      await windowManager.setFullScreen(on);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  } catch (_) {}
  try {
    on ? await WakelockPlus.enable() : await WakelockPlus.disable();
  } catch (_) {}
}

/// Call once from main() before runApp.
Future<void> initKioskSupport() async {
  if (!_isDesktop) return;
  try {
    await windowManager.ensureInitialized();
  } catch (_) {}
}
