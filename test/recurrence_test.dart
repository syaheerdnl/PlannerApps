import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/domain/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

Obligation bill({
  String name = 'Bill',
  Frequency frequency = Frequency.monthly,
  int interval = 1,
  required DateTime start,
  DateTime? end,
  int buffer = 0,
}) {
  final t = DateTime.utc(2026, 1, 1);
  return Obligation(
    id: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    amountSen: 10000,
    frequency: frequency,
    intervalCount: interval,
    startDate: start,
    endDate: end,
    payByBufferDays: buffer,
    createdAt: t,
    updatedAt: t,
  );
}

List<String> iso(List<DateTime> dates) => dates.map(toIsoDate).toList();

void main() {
  group('monthly', () {
    test('the 17th of every month', () {
      final o = bill(start: dateOf(2026, 11, 17));
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 1), dateOf(2027, 1, 31))), [
        '2026-11-17',
        '2026-12-17',
        '2027-01-17',
      ]);
    });

    test('the 31st does not drift: it snaps to month end, then returns to 31', () {
      final o = bill(start: dateOf(2026, 1, 31));
      expect(iso(dueDatesBetween(o, dateOf(2026, 1, 1), dateOf(2026, 5, 31))), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
        '2026-05-31',
      ]);
    });

    test('February in a leap year', () {
      final o = bill(start: dateOf(2028, 1, 31));
      expect(iso(dueDatesBetween(o, dateOf(2028, 2, 1), dateOf(2028, 2, 29))), ['2028-02-29']);
    });

    test('the 29th and 30th clamp in February only', () {
      final o29 = bill(start: dateOf(2026, 1, 29));
      expect(iso(dueDatesBetween(o29, dateOf(2026, 2, 1), dateOf(2026, 3, 31))), ['2026-02-28', '2026-03-29']);
      final o30 = bill(start: dateOf(2026, 1, 30));
      expect(iso(dueDatesBetween(o30, dateOf(2026, 2, 1), dateOf(2026, 4, 30))), [
        '2026-02-28',
        '2026-03-30',
        '2026-04-30',
      ]);
    });

    test('every 3 months (quarterly)', () {
      final o = bill(start: dateOf(2026, 10, 28), interval: 3);
      expect(iso(dueDatesBetween(o, dateOf(2026, 10, 1), dateOf(2027, 8, 1))), [
        '2026-10-28',
        '2027-01-28',
        '2027-04-28',
        '2027-07-28',
      ]);
    });

    test('crosses a year boundary', () {
      final o = bill(start: dateOf(2026, 11, 15));
      expect(iso(dueDatesBetween(o, dateOf(2026, 12, 20), dateOf(2027, 1, 20))), ['2027-01-15']);
    });

    test('a range long after the start jumps ahead correctly', () {
      final o = bill(start: dateOf(2020, 3, 17));
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 1), dateOf(2026, 11, 30))), ['2026-11-17']);
      final q = bill(start: dateOf(2020, 3, 17), interval: 3);
      // 2020-03 + 3k months: ... 2026-09, 2026-12
      expect(iso(dueDatesBetween(q, dateOf(2026, 10, 1), dateOf(2026, 12, 31))), ['2026-12-17']);
    });

    test('nothing before the start date', () {
      final o = bill(start: dateOf(2026, 11, 17));
      expect(dueDatesBetween(o, dateOf(2026, 1, 1), dateOf(2026, 11, 16)), isEmpty);
    });

    test('both ends of the range are included', () {
      final o = bill(start: dateOf(2026, 11, 17));
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 17), dateOf(2026, 11, 17))), ['2026-11-17']);
    });

    test('end date is included, nothing after it', () {
      final o = bill(start: dateOf(2026, 11, 17), end: dateOf(2026, 12, 17));
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 1), dateOf(2027, 6, 1))), ['2026-11-17', '2026-12-17']);
    });

    test('an inverted range is empty', () {
      final o = bill(start: dateOf(2026, 11, 17));
      expect(dueDatesBetween(o, dateOf(2026, 12, 1), dateOf(2026, 11, 1)), isEmpty);
    });
  });

  group('yearly', () {
    test('every year on the same day', () {
      final o = bill(frequency: Frequency.yearly, start: dateOf(2025, 10, 28));
      expect(iso(dueDatesBetween(o, dateOf(2026, 1, 1), dateOf(2028, 12, 31))), [
        '2026-10-28',
        '2027-10-28',
        '2028-10-28',
      ]);
    });

    test('29 Feb lands on 28 Feb in normal years and 29 Feb in leap years', () {
      final o = bill(frequency: Frequency.yearly, start: dateOf(2028, 2, 29));
      expect(iso(dueDatesBetween(o, dateOf(2028, 1, 1), dateOf(2032, 12, 31))), [
        '2028-02-29',
        '2029-02-28',
        '2030-02-28',
        '2031-02-28',
        '2032-02-29',
      ]);
    });

    test('every 2 years', () {
      final o = bill(frequency: Frequency.yearly, interval: 2, start: dateOf(2026, 6, 1));
      expect(iso(dueDatesBetween(o, dateOf(2026, 1, 1), dateOf(2031, 1, 1))), [
        '2026-06-01',
        '2028-06-01',
        '2030-06-01',
      ]);
    });
  });

  group('weekly', () {
    test('every 7 days from the start', () {
      final o = bill(frequency: Frequency.weekly, start: dateOf(2026, 11, 2)); // a Monday
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 1), dateOf(2026, 11, 30))), [
        '2026-11-02',
        '2026-11-09',
        '2026-11-16',
        '2026-11-23',
        '2026-11-30',
      ]);
    });

    test('fortnightly keeps its alignment when the range starts later', () {
      final o = bill(frequency: Frequency.weekly, interval: 2, start: dateOf(2026, 11, 2));
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 10), dateOf(2026, 12, 31))), [
        '2026-11-16',
        '2026-11-30',
        '2026-12-14',
        '2026-12-28',
      ]);
    });

    test('rolls over month ends', () {
      final o = bill(frequency: Frequency.weekly, start: dateOf(2026, 12, 28));
      expect(iso(dueDatesBetween(o, dateOf(2026, 12, 28), dateOf(2027, 1, 11))), [
        '2026-12-28',
        '2027-01-04',
        '2027-01-11',
      ]);
    });
  });

  group('once', () {
    test('appears only if inside the range', () {
      final o = bill(frequency: Frequency.once, start: dateOf(2026, 12, 2));
      expect(iso(dueDatesBetween(o, dateOf(2026, 11, 1), dateOf(2026, 12, 31))), ['2026-12-02']);
      expect(dueDatesBetween(o, dateOf(2027, 1, 1), dateOf(2027, 12, 31)), isEmpty);
    });
  });

  group('nextDueOnOrAfter', () {
    final loan = bill(start: dateOf(2026, 11, 17));

    test('the same day counts', () {
      expect(nextDueOnOrAfter(loan, dateOf(2026, 11, 17)), dateOf(2026, 11, 17));
    });

    test('the day after rolls to next month', () {
      expect(nextDueOnOrAfter(loan, dateOf(2026, 11, 18)), dateOf(2026, 12, 17));
    });

    test('null once the bill has ended', () {
      final ended = bill(start: dateOf(2026, 11, 17), end: dateOf(2026, 12, 17));
      expect(nextDueOnOrAfter(ended, dateOf(2026, 12, 18)), isNull);
    });

    test('null for a one-off in the past', () {
      final once = bill(frequency: Frequency.once, start: dateOf(2026, 10, 1));
      expect(nextDueOnOrAfter(once, dateOf(2026, 11, 1)), isNull);
    });

    test('works for yearly and quarterly bills', () {
      final yearly = bill(frequency: Frequency.yearly, start: dateOf(2026, 10, 28));
      expect(nextDueOnOrAfter(yearly, dateOf(2026, 11, 1)), dateOf(2027, 10, 28));
      final quarterly = bill(start: dateOf(2026, 10, 28), interval: 3);
      expect(nextDueOnOrAfter(quarterly, dateOf(2026, 11, 1)), dateOf(2027, 1, 28));
    });
  });

  group('Occurrence', () {
    final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);
    final occ = Occurrence(car, dateOf(2026, 11, 17));

    test('pay-by is the due date minus the buffer', () {
      expect(occ.payBy, dateOf(2026, 11, 15));
    });

    test('pay-by can cross a month boundary', () {
      final rent = bill(start: dateOf(2026, 12, 2), buffer: 5);
      expect(Occurrence(rent, dateOf(2026, 12, 2)).payBy, dateOf(2026, 11, 27));
    });

    test('daysUntilDue', () {
      expect(occ.daysUntilDue(dateOf(2026, 11, 11)), 6);
      expect(occ.daysUntilDue(dateOf(2026, 11, 17)), 0);
      expect(occ.daysUntilDue(dateOf(2026, 11, 19)), -2);
    });

    test('status moves upcoming -> payNow -> overdue as days pass', () {
      expect(occ.statusOn(dateOf(2026, 11, 11), paid: false), DueStatus.upcoming);
      expect(occ.statusOn(dateOf(2026, 11, 14), paid: false), DueStatus.upcoming);
      expect(occ.statusOn(dateOf(2026, 11, 15), paid: false), DueStatus.payNow);
      expect(occ.statusOn(dateOf(2026, 11, 17), paid: false), DueStatus.payNow);
      expect(occ.statusOn(dateOf(2026, 11, 18), paid: false), DueStatus.overdue);
    });

    test('paid wins over everything', () {
      expect(occ.statusOn(dateOf(2026, 11, 30), paid: true), DueStatus.paid);
      expect(occ.statusOn(dateOf(2026, 11, 11), paid: true), DueStatus.paid);
    });

    test('key matches the payment key format', () {
      expect(occ.key, 'car-loan|2026-11-17');
    });

    test('time of day on "today" is ignored', () {
      expect(occ.statusOn(DateTime(2026, 11, 17, 23, 59), paid: false), DueStatus.payNow);
    });
  });

  group('occurrencesBetween', () {
    test('merges bills, soonest first, ties broken by name', () {
      final bills = [
        bill(name: 'Phone plan', start: dateOf(2026, 11, 12)),
        bill(name: 'Car loan', start: dateOf(2026, 11, 17)),
        bill(name: 'TNB', start: dateOf(2026, 11, 12)),
        bill(name: 'Insurance', frequency: Frequency.yearly, start: dateOf(2026, 10, 28)),
      ];

      final list = occurrencesBetween(bills, dateOf(2026, 11, 1), dateOf(2026, 11, 30));

      expect(list.map((o) => '${toIsoDate(o.dueDate)} ${o.obligation.name}').toList(), [
        '2026-11-12 Phone plan',
        '2026-11-12 TNB',
        '2026-11-17 Car loan',
      ]);
    });

    test('empty input gives an empty list', () {
      expect(occurrencesBetween(const [], dateOf(2026, 11, 1), dateOf(2026, 11, 30)), isEmpty);
    });
  });
}
