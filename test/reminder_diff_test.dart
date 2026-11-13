import 'package:bayar/domain/reminder_planner.dart';
import 'package:bayar/services/reminder_diff.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedReminder reminder(DateTime at, [String key = 'k']) =>
    PlannedReminder(at: at, kind: ReminderKind.payDay, title: 't', body: 'b', occurrenceKey: key);

void main() {
  final nineAm = DateTime(2026, 11, 13, 9);

  group('ids encode the due time', () {
    test('an id decodes back to its minute', () {
      final id = reminderIdFor(DateTime(2026, 11, 13, 9, 0, 42), 7); // seconds are ignored
      expect(reminderTimeOfId(id), DateTime.utc(2026, 11, 13, 9));
    });

    test('later reminders get bigger ids, and many in one minute stay distinct', () {
      expect(reminderIdFor(nineAm.add(const Duration(minutes: 1)), 0), greaterThan(reminderIdFor(nineAm, 99)));
      final ids = {for (var i = 0; i < 100; i++) reminderIdFor(nineAm, i)};
      expect(ids, hasLength(100));
    });

    test('ids fit in 32 bits for years to come', () {
      expect(reminderIdFor(DateTime(2035, 12, 31, 23, 59), 99), lessThan(2147483647));
    });
  });

  group('re-planning while a reminder is due but not yet delivered (the real incident)', () {
    test('the 9:00 reminder survives the app opening at 9:00:33', () {
      final pending = reminderIdFor(nineAm, 0);
      final plan = planReplacement(
        pendingIds: [pending],
        desired: [reminder(DateTime(2026, 12, 12, 9))], // only future reminders are planned
        now: DateTime(2026, 11, 13, 9, 0, 33),
      );
      expect(plan.cancel, isNot(contains(pending)), reason: 'it is due and still on its way: do not cancel');
      expect(plan.schedule, hasLength(1));
    });

    test('a reminder 5 minutes late is still protected', () {
      final pending = reminderIdFor(nineAm, 0);
      final plan = planReplacement(pendingIds: [pending], desired: [], now: DateTime(2026, 11, 13, 9, 5));
      expect(plan.cancel, isEmpty);
    });

    test('once it is stale (over 2 hours) it is cleared', () {
      final pending = reminderIdFor(nineAm, 0);
      final plan = planReplacement(pendingIds: [pending], desired: [], now: DateTime(2026, 11, 13, 11, 1));
      expect(plan.cancel, [pending]);
    });
  });

  group('everything else is replaced as before', () {
    test('future pending reminders are cancelled and the plan is scheduled fresh', () {
      final future = reminderIdFor(DateTime(2026, 11, 14, 9), 0);
      final plan = planReplacement(
        pendingIds: [future],
        desired: [reminder(DateTime(2026, 11, 14, 9)), reminder(DateTime(2026, 11, 15, 9))],
        now: DateTime(2026, 11, 13, 8),
      );
      expect(plan.cancel, [future]);
      expect(plan.schedule, hasLength(2));
    });

    test('old-style ids (1, 2, 3...) from before this fix are cleared', () {
      final plan = planReplacement(pendingIds: [1, 2, 3, 60], desired: [], now: DateTime(2026, 11, 13, 8));
      expect(plan.cancel, [1, 2, 3, 60]);
    });

    test('reminders in the same minute get different ids', () {
      final plan = planReplacement(
        pendingIds: [],
        desired: [reminder(DateTime(2026, 11, 14, 9), 'a'), reminder(DateTime(2026, 11, 14, 9), 'b')],
        now: DateTime(2026, 11, 13, 8),
      );
      expect(plan.schedule.map((s) => s.id).toSet(), hasLength(2));
    });

    test('with nothing pending and nothing planned, nothing happens', () {
      final plan = planReplacement(pendingIds: [], desired: [], now: DateTime(2026, 11, 13, 8));
      expect(plan.cancel, isEmpty);
      expect(plan.schedule, isEmpty);
    });
  });
}
