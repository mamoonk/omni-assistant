import 'package:flutter_test/flutter_test.dart';

import 'package:home_nexus/services/solar.dart';
import 'package:home_nexus/state/automations_provider.dart';

void main() {
  group('solarTimes', () {
    // Note: results are in the *local* timezone of the DateTime passed in;
    // tests use UTC dates so expectations are timezone-independent.
    test('equator at equinox: roughly 6:00 / 18:00 UTC at lon 0', () {
      final t = solarTimes(DateTime.utc(2026, 3, 20), 0, 0)!;
      expect((t.sunrise - 360).abs(), lessThan(20),
          reason: 'sunrise ${t.sunrise}min should be ~06:00');
      expect((t.sunset - 1080).abs(), lessThan(20),
          reason: 'sunset ${t.sunset}min should be ~18:00');
    });

    test('London summer solstice: long day', () {
      final t = solarTimes(DateTime.utc(2026, 6, 21), 51.5, -0.12)!;
      final dayLength = t.sunset - t.sunrise;
      expect(dayLength, greaterThan(16 * 60));
      expect(dayLength, lessThan(17.5 * 60));
    });

    test('polar night returns null', () {
      expect(solarTimes(DateTime.utc(2026, 12, 21), 78.2, 15.6), isNull);
      expect(solarTimes(DateTime.utc(2026, 6, 21), 78.2, 15.6), isNull);
    });
  });

  test('sun trigger round-trips through JSON', () {
    final automation = Automation(
      id: 's1',
      name: 'Sunset lights',
      trigger: const SunTrigger(event: 'sunset', offsetMinutes: -30),
      actions: const [
        SetStateAction(
            deviceId: 'd', capabilityType: 'powerSwitch', value: true),
      ],
    );
    final restored = Automation.fromJson(automation.toJson());
    final trigger = restored.trigger as SunTrigger;
    expect(trigger.event, 'sunset');
    expect(trigger.offsetMinutes, -30);
  });
}
