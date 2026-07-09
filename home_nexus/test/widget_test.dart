import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_nexus/main.dart';

void main() {
  testWidgets('dashboard renders room tabs and mock devices', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HomeNexusApp()));

    expect(find.text('All Devices'), findsOneWidget);
    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('Hue Go'), findsOneWidget);
    expect(find.text('Thermostat'), findsOneWidget);
  });
}
