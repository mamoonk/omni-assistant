import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unification/unification.dart';

import 'package:home_nexus/main.dart';
import 'package:home_nexus/screens/settings_screen.dart';
import 'package:home_nexus/state/device_providers.dart';
import 'package:home_nexus/state/ha_connection.dart';
import 'package:home_nexus/state/layout_provider.dart';
import 'package:home_nexus/state/scenes_provider.dart';

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

  testWidgets('settings screen opens and validates HA input', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HomeNexusApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('MQTT broker (Zigbee2MQTT)'), findsOneWidget);

    // empty token -> validation error, no connect attempt
    await tester.tap(find.text('Connect').first);
    await tester.pumpAndSettle();
    expect(find.text('Token required'), findsOneWidget);
  });

  testWidgets('edit mode shows scene chip and new-tab action', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HomeNexusApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Scene'), findsOneWidget);
    expect(find.byIcon(Icons.tab), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsWidgets);
  });

  test('scene snapshot restores captured device state on activate', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // localStoreProvider needs prefs; warm it up
    await container.read(localStoreProvider.future);

    final devices = container.read(devicesProvider);
    final hueGo = devices.firstWhere((d) => d.id == 'mock:hue_go');
    expect(hueGo.capability<PowerSwitchCapability>()!.on, isTrue);

    await container
        .read(scenesProvider.notifier)
        .createFromCurrentState('Evening', {hueGo.id});
    final scene = container.read(scenesProvider).single;
    expect(scene.actions.map((a) => a.capabilityType),
        contains(CapabilityType.powerSwitch));

    // change state, then activate the scene to restore it
    hueGo.capability<PowerSwitchCapability>()!.on = false;
    await container.read(scenesProvider.notifier).activate(scene);
    expect(hueGo.capability<PowerSwitchCapability>()!.on, isTrue);
  });

  test('layout reorder moves device before target', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(localStoreProvider.future);

    final layout = container.read(layoutProvider.notifier);
    await layout.moveBefore('c', 'a', ['a', 'b', 'c']);
    expect(layout.sorted(['a', 'b', 'c']), ['c', 'a', 'b']);

    await layout.toggleSpan('a');
    expect(layout.spanOf('a'), 2);
    await layout.toggleSpan('a');
    expect(layout.spanOf('a'), 1);
  });
}
