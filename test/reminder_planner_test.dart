import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

Obligation bill({
  required String name,
  required DateTime start,
  int sen = 52000,
  int buffer = 0,
  bool estimate = false,
  Frequency frequency = Frequency.monthly,
  DateTime? end,
}) {
  final t = DateTime.utc(2026, 1, 1);
  return Obligation(
    id: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    amountSen: sen,
    isEstimate: estimate,
    frequency: frequency,
    startDate: start,
    endDate: end,
    payByBufferDays: buffer,
    createdAt: t,
    updatedAt: t,
  );
}

String show(PlannedReminder r) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${r.at.year}-${two(r.at.month)}-${two(r.at.day)} ${two(r.at.hour)}:${two(r.at.minute)} ${r.kind.name}';
}

void main() {
  const planner = ReminderPlanner();
  // Thursday 12 Nov 2026, 08:00 on the phone's clock.
  final morning = DateTime(2026, 11, 12, 8);

  group('what gets scheduled', () {
    test('a bill with a pay-early buffer gets three reminders per occurrence', () {
      final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2); // pay by 15 Nov

      final plan = planner.plan(obligations: [car], paidKeys: {}, now: morning);

      expect(plan.map(show).take(3).toList(), [
        '2026-11-14 09:00 dayBefore',
        '2026-11-15 09:00 payDay',
        '2026-11-17 09:00 dueDay',
      ]);
    });

    test('a bill with no buffer gets a day-before and a due-day reminder', () {
      final rent = bill(name: 'Rent', start: dateOf(2026, 11, 20));

      final plan = planner.plan(obligations: [rent], paidKeys: {}, now: morning);

      expect(plan.map(show).take(2).toList(), ['2026-11-19 09:00 dayBefore', '2026-11-20 09:00 payDay']);
    });

    test('later months are planned too, up to the horizon', () {
      final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);

      final plan = planner.plan(obligations: [car], paidKeys: {}, now: morning);

      // Nov: 14, 15, 17.  Dec: 14, 15, 17 (Dec 17 is inside 45 days). Jan is not.
      expect(plan, hasLength(6));
      expect(show(plan.last), '2026-12-17 09:00 dueDay');
    });

    test('nothing beyond the planning horizon', () {
      final yearly = bill(name: 'Insurance', start: dateOf(2027, 6, 1), frequency: Frequency.yearly);
      expect(planner.plan(obligations: [yearly], paidKeys: {}, now: morning), isEmpty);
    });

    test('times follow the configured hour and minute', () {
      const evening = ReminderPlanner(hour: 20, minute: 30);
      final rent = bill(name: 'Rent', start: dateOf(2026, 11, 20));

      final first = evening.plan(obligations: [rent], paidKeys: {}, now: morning).first;

      expect(first.at, DateTime(2026, 11, 19, 20, 30));
    });
  });

  group('paid and past', () {
    test('a paid occurrence gets no reminders, the next month still does', () {
      final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);
      final paid = {'car-loan|2026-11-17'};

      final plan = planner.plan(obligations: [car], paidKeys: paid, now: morning);

      expect(plan.map(show), ['2026-12-14 09:00 dayBefore', '2026-12-15 09:00 payDay', '2026-12-17 09:00 dueDay']);
    });

    test('reminder times that already passed today are skipped', () {
      final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);
      final afterNine = DateTime(2026, 11, 15, 10); // 15 Nov, 10:00

      final plan = planner.plan(obligations: [car], paidKeys: {}, now: afterNine);

      expect(plan.first.at, DateTime(2026, 11, 17, 9)); // 14th and 15th 09:00 are gone
    });

    test('exactly at the reminder time counts as already passed', () {
      final rent = bill(name: 'Rent', start: dateOf(2026, 11, 20));
      final plan = planner.plan(obligations: [rent], paidKeys: {}, now: DateTime(2026, 11, 19, 9));
      expect(plan.first.kind, ReminderKind.payDay);
    });
  });

  group('overdue', () {
    final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);

    test('an unpaid past bill gets one nudge at the next 9:00', () {
      final plan = planner.plan(obligations: [car], paidKeys: {}, now: DateTime(2026, 11, 20, 10));
      final overdue = plan.where((r) => r.kind == ReminderKind.overdue).toList();

      expect(overdue, hasLength(1));
      expect(overdue.single.at, DateTime(2026, 11, 21, 9)); // 10:00 is past today's 9:00
      expect(overdue.single.title, 'Car loan is overdue');
      expect(overdue.single.body, 'RM 520.00 was due Tue 17 Nov');
    });

    test('before 9:00 the nudge is still today', () {
      final plan = planner.plan(obligations: [car], paidKeys: {}, now: DateTime(2026, 11, 20, 7, 30));
      expect(plan.firstWhere((r) => r.kind == ReminderKind.overdue).at, DateTime(2026, 11, 20, 9));
    });

    test('paying it removes the nudge', () {
      final plan = planner.plan(obligations: [car], paidKeys: {'car-loan|2026-11-17'}, now: DateTime(2026, 11, 20, 10));
      expect(plan.where((r) => r.kind == ReminderKind.overdue), isEmpty);
    });

    test('bills overdue by more than the look-back window are forgotten', () {
      final old = bill(name: 'Old', start: dateOf(2026, 9, 1), frequency: Frequency.once);
      final plan = planner.plan(obligations: [old], paidKeys: {}, now: morning);
      expect(plan, isEmpty);
    });
  });

  group('wording', () {
    test('day before, pay day and due day', () {
      final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);

      final plan = planner.plan(obligations: [car], paidKeys: {}, now: morning);

      expect(plan[0].title, 'Car loan: pay by tomorrow');
      expect(plan[0].body, 'RM 520.00 · due Tue 17 Nov');
      expect(plan[1].title, 'Car loan: time to pay');
      expect(plan[1].body, 'RM 520.00 · due Tue 17 Nov');
      expect(plan[2].title, 'Car loan is due today');
      expect(plan[2].body, 'RM 520.00 is still unpaid');
    });

    test('with no buffer the pay day IS the due day', () {
      final rent = bill(name: 'Rent', start: dateOf(2026, 11, 20));

      final plan = planner.plan(obligations: [rent], paidKeys: {}, now: morning);

      expect(plan[1].title, 'Rent is due today');
      expect(plan[1].body, 'RM 520.00');
    });

    test('estimates are marked with ~', () {
      final tnb = bill(name: 'TNB electricity', start: dateOf(2026, 11, 22), sen: 18000, estimate: true);

      final plan = planner.plan(obligations: [tnb], paidKeys: {}, now: morning);

      expect(plan.first.body, '~RM 180.00 · due Sun 22 Nov');
    });

    test('each reminder remembers which occurrence it is about', () {
      final car = bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2);
      final plan = planner.plan(obligations: [car], paidKeys: {}, now: morning);
      expect(plan.first.occurrenceKey, 'car-loan|2026-11-17');
      expect(plan.last.occurrenceKey, 'car-loan|2026-12-17');
    });
  });

  group('ordering and limits', () {
    test('sorted by time across bills', () {
      final bills = [
        bill(name: 'Car loan', start: dateOf(2026, 11, 17), buffer: 2),
        bill(name: 'Phone plan', start: dateOf(2026, 11, 13)),
      ];

      final plan = planner.plan(obligations: bills, paidKeys: {}, now: morning);
      final times = plan.map((r) => r.at).toList();

      expect(times, [...times]..sort());
      expect(plan.first.title, 'Phone plan: pay by tomorrow'); // 12 Nov 09:00
    });

    test('never more than maxReminders, keeping the soonest', () {
      final weekly = bill(name: 'Gym', start: dateOf(2026, 11, 13), frequency: Frequency.weekly);
      const small = ReminderPlanner(maxReminders: 5);

      final plan = small.plan(obligations: [weekly], paidKeys: {}, now: morning);

      expect(plan, hasLength(5));
      expect(plan.first.at, DateTime(2026, 11, 12, 9));
    });

    test('the default cap is below the iOS limit of 64', () {
      final weekly = bill(name: 'Gym', start: dateOf(2026, 11, 13), frequency: Frequency.weekly);
      final plan = planner.plan(obligations: [weekly], paidKeys: {}, now: morning);
      expect(plan.length, lessThanOrEqualTo(60));
    });

    test('no bills, no reminders', () {
      expect(planner.plan(obligations: const [], paidKeys: {}, now: morning), isEmpty);
    });

    test('an ended bill stops reminding', () {
      final loan = bill(name: 'Loan', start: dateOf(2026, 10, 17), end: dateOf(2026, 11, 17));
      final plan = planner.plan(obligations: [loan], paidKeys: {'loan|2026-10-17'}, now: morning);
      expect(plan.every((r) => r.at.isBefore(DateTime(2026, 11, 18))), isTrue);
    });
  });
}
