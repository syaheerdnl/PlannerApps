import 'package:bayar/services/time_zone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const eightHours = Duration(hours: 8);

void main() {
  // The same database the app loads. Using the smaller latest.dart here would
  // make the Kuala Lumpur tests fail, which is the bug these tests guard against.
  setUpAll(tzdata.initializeTimeZones);

  test('Asia/Kuala_Lumpur exists in the database', () {
    expect(() => tz.getLocation('Asia/Kuala_Lumpur'), returnsNormally);
  });

  test('a known name resolves to that zone', () {
    final location = resolveLocation(identifier: 'Asia/Kuala_Lumpur', deviceOffset: eightHours);
    expect(location.currentTimeZone.offset, eightHours);
  });

  test('09:00 in Kuala Lumpur is 01:00 UTC, so reminders fire in the morning', () {
    final kl = resolveLocation(identifier: 'Asia/Kuala_Lumpur', deviceOffset: eightHours);

    final nineAm = tz.TZDateTime(kl, 2026, 11, 14, 9);

    expect(nineAm.toUtc(), DateTime.utc(2026, 11, 14, 1));
  });

  test('a zone with daylight saving uses the offset in force on that date', () {
    final ny = resolveLocation(identifier: 'America/New_York', deviceOffset: const Duration(hours: -5));
    expect(tz.TZDateTime(ny, 2026, 1, 15, 9).toUtc(), DateTime.utc(2026, 1, 15, 14)); // winter, UTC-5
    expect(tz.TZDateTime(ny, 2026, 7, 15, 9).toUtc(), DateTime.utc(2026, 7, 15, 13)); // summer, UTC-4
  });

  test('an unknown name falls back to a zone with the phone\'s UTC offset', () {
    final location = resolveLocation(identifier: 'Mars/Olympus_Mons', deviceOffset: eightHours);
    expect(location.currentTimeZone.offset, eightHours);
  });

  test('no name at all also falls back by offset', () {
    final location = resolveLocation(identifier: null, deviceOffset: eightHours);
    expect(location.currentTimeZone.offset, eightHours);
  });

  test('if nothing matches, UTC is the last resort', () {
    final location = resolveLocation(
      identifier: 'Mars/Olympus_Mons',
      deviceOffset: const Duration(hours: 8, minutes: 13),
    );
    expect(location, tz.UTC);
  });
}
