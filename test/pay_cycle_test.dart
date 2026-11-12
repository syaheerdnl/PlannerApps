import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/pay_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

String span(PayCycle c) => '${toIsoDate(c.start)}..${toIsoDate(c.end)}';

void main() {
  group('PayCycle.containing, payday on the 25th', () {
    test('a date before this month\'s payday belongs to the cycle that started last month', () {
      final c = PayCycle.containing(dateOf(2026, 11, 12), paydayDay: 25);
      expect(span(c), '2026-10-25..2026-11-24');
      expect(c.lengthDays, 31);
    });

    test('payday itself starts a new cycle', () {
      expect(span(PayCycle.containing(dateOf(2026, 11, 25), paydayDay: 25)), '2026-11-25..2026-12-24');
    });

    test('the day before payday is the last day of the old cycle', () {
      expect(span(PayCycle.containing(dateOf(2026, 11, 24), paydayDay: 25)), '2026-10-25..2026-11-24');
    });

    test('crosses a year boundary in both directions', () {
      expect(span(PayCycle.containing(dateOf(2027, 1, 10), paydayDay: 25)), '2026-12-25..2027-01-24');
      expect(span(PayCycle.containing(dateOf(2026, 12, 30), paydayDay: 25)), '2026-12-25..2027-01-24');
    });
  });

  group('month-end paydays', () {
    test('payday 31 lands on the last day of shorter months', () {
      expect(span(PayCycle.containing(dateOf(2026, 2, 10), paydayDay: 31)), '2026-01-31..2026-02-27');
      expect(span(PayCycle.containing(dateOf(2026, 3, 15), paydayDay: 31)), '2026-02-28..2026-03-30');
      expect(span(PayCycle.containing(dateOf(2026, 4, 30), paydayDay: 31)), '2026-04-30..2026-05-30');
    });

    test('leap years are respected', () {
      expect(span(PayCycle.containing(dateOf(2028, 2, 29), paydayDay: 31)), '2028-02-29..2028-03-30');
    });

    test('payday 1 gives calendar months', () {
      expect(span(PayCycle.containing(dateOf(2026, 11, 12), paydayDay: 1)), '2026-11-01..2026-11-30');
      expect(span(PayCycle.containing(dateOf(2026, 12, 31), paydayDay: 1)), '2026-12-01..2026-12-31');
    });
  });

  group('every date belongs to exactly one cycle', () {
    test('cycles tile the calendar with no gaps or overlaps', () {
      for (final payday in [1, 15, 25, 28, 29, 30, 31]) {
        var cycle = PayCycle.containing(dateOf(2026, 1, 1), paydayDay: payday);
        for (var i = 0; i < 30; i++) {
          final following = cycle.next(paydayDay: payday);
          expect(following.start, addDays(cycle.end, 1), reason: 'payday $payday, after ${span(cycle)}');
          expect(following.end.isAfter(following.start) || following.end == following.start, isTrue);
          cycle = following;
        }
      }
    });

    test('containing() agrees with contains() for every day of two years', () {
      for (final payday in [5, 25, 31]) {
        for (var i = 0; i < 730; i++) {
          final day = addDays(dateOf(2026, 1, 1), i);
          expect(PayCycle.containing(day, paydayDay: payday).contains(day), isTrue, reason: '$day payday $payday');
        }
      }
    });
  });

  group('position inside a cycle', () {
    final cycle = PayCycle.containing(dateOf(2026, 11, 12), paydayDay: 25); // 25 Oct .. 24 Nov

    test('day number counts from 1', () {
      expect(cycle.dayNumber(dateOf(2026, 10, 25)), 1);
      expect(cycle.dayNumber(dateOf(2026, 11, 12)), 19);
      expect(cycle.dayNumber(dateOf(2026, 11, 24)), 31);
    });

    test('days left counts today and the last day', () {
      expect(cycle.daysLeft(dateOf(2026, 11, 12)), 13);
      expect(cycle.daysLeft(dateOf(2026, 11, 24)), 1);
    });

    test('days left is never below 1, even outside the cycle', () {
      expect(cycle.daysLeft(dateOf(2026, 12, 30)), 1);
    });

    test('the next payday is the day after the cycle ends', () {
      expect(cycle.nextPayday, dateOf(2026, 11, 25));
    });

    test('contains covers both ends and nothing beyond', () {
      expect(cycle.contains(dateOf(2026, 10, 25)), isTrue);
      expect(cycle.contains(dateOf(2026, 11, 24)), isTrue);
      expect(cycle.contains(dateOf(2026, 10, 24)), isFalse);
      expect(cycle.contains(dateOf(2026, 11, 25)), isFalse);
    });

    test('equal cycles compare equal', () {
      expect(PayCycle.containing(dateOf(2026, 11, 1), paydayDay: 25), cycle);
    });
  });
}
