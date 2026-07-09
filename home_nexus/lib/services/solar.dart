import 'dart:math';

/// Sunrise/sunset in minutes since local midnight for [date] at [lat]/[lon],
/// using the NOAA-style approximation (equation of time + declination).
/// Accuracy is a few minutes — plenty for automations.
/// Returns null during polar day/night.
({int sunrise, int sunset})? solarTimes(
  DateTime date,
  double latDeg,
  double lonDeg,
) {
  final n = date.difference(DateTime(date.year)).inDays + 1; // day of year
  final b = 2 * pi * (n - 81) / 364;

  // equation of time, minutes
  final eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b);
  // solar declination, radians
  final decl = 23.45 * pi / 180 * sin(2 * pi * (284 + n) / 365);
  final lat = latDeg * pi / 180;

  final cosOmega = -tan(lat) * tan(decl);
  if (cosOmega < -1 || cosOmega > 1) return null; // polar day/night

  final halfDayHours = acos(cosOmega) * 180 / pi / 15;
  final tzHours = date.timeZoneOffset.inMinutes / 60.0;
  final solarNoon = 12 - lonDeg / 15 + tzHours - eot / 60;

  final sunrise = ((solarNoon - halfDayHours) * 60).round();
  final sunset = ((solarNoon + halfDayHours) * 60).round();
  return (sunrise: _wrapDay(sunrise), sunset: _wrapDay(sunset));
}

int _wrapDay(int minutes) => ((minutes % 1440) + 1440) % 1440;
