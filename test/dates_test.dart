import 'package:bayar/core/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lastDayOfMonth', () {
    test('handles 30 and 31 day months', () {
      expect(lastDayOfMonth(2026, 1), 31);
      expect(lastDayOfMonth(2026, 4), 30);
      expect(lastDayOfMonth(2026, 12), 31); // month + 1 rolls into next January
    });

    test('handles February in normal and leap years', () {
      expect(lastDayOfMonth(2026, 2), 28);
      expect(lastDayOfMonth(2028, 2), 29);
      expect(lastDayOfMonth(2100, 2), 28); // divisible by 100 but not 400
      expect(lastDayOfMonth(2000, 2), 29);
    });
  });

  group('clampedDate', () {
    test('keeps a day that exists', () {
      expect(clampedDate(2026, 11, 17), dateOf(2026, 11, 17));
    });

    test('a bill due on the 31st moves to the last day of shorter months', () {
      expect(clampedDate(2026, 4, 31), dateOf(2026, 4, 30));
      expect(clampedDate(2026, 2, 31), dateOf(2026, 2, 28));
      expect(clampedDate(2028, 2, 31), dateOf(2028, 2, 29));
      expect(clampedDate(2026, 12, 31), dateOf(2026, 12, 31));
    });
  });

  group('daysBetween', () {
    test('counts calendar days', () {
      expect(daysBetween(dateOf(2026, 11, 11), dateOf(2026, 11, 25)), 14);
      expect(daysBetween(dateOf(2026, 11, 25), dateOf(2026, 11, 11)), -14);
      expect(daysBetween(dateOf(2026, 11, 11), dateOf(2026, 11, 11)), 0);
    });

    test('works across month and year boundaries', () {
      expect(daysBetween(dateOf(2026, 12, 25), dateOf(2027, 1, 5)), 11);
      expect(daysBetween(dateOf(2028, 2, 28), dateOf(2028, 3, 1)), 2); // leap year
    });

    test('ignores the time of day', () {
      expect(daysBetween(DateTime(2026, 11, 11, 23, 59), DateTime(2026, 11, 12, 0, 1)), 1);
    });
  });

  group('ISO dates', () {
    test('round-trip', () {
      final d = dateOf(2026, 11, 5);
      expect(toIsoDate(d), '2026-11-05');
      expect(fromIsoDate('2026-11-05'), d);
    });

    test('sort correctly as plain text', () {
      final list = ['2026-11-17', '2026-02-03', '2027-01-01', '2026-11-05']..sort();
      expect(list, ['2026-02-03', '2026-11-05', '2026-11-17', '2027-01-01']);
    });
  });

  group('formatting', () {
    test('short date and month', () {
      expect(formatShortDate(dateOf(2026, 11, 12)), 'Thu 12 Nov');
      expect(formatShortDate(dateOf(2026, 11, 25)), 'Wed 25 Nov');
      expect(monthAbbr(dateOf(2026, 10, 28)), 'Oct');
    });
  });
}
