import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:home_nexus/main.dart';
import 'package:home_nexus/screens/settings_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dashboard renders room tabs and mock devices after bootstrap',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HomeNexusApp()));
    await tester.pumpAndSettle();

    expect(find.text('All Devices'), findsOneWidget);
    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('Hue Go'), findsOneWidget);
    expect(find.text('Thermostat'), findsOneWidget);
  });

  testWidgets('settings screen opens and validates input', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HomeNexusApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // empty token -> validation error, no connect attempt
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Token required'), findsOneWidget);
  });
}
