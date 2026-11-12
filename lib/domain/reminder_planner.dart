import '../core/dates.dart';
import '../core/money.dart';
import 'obligation.dart';
import 'recurrence.dart';

enum ReminderKind {
  /// The day before the pay-by date.
  dayBefore,

  /// On the pay-by date.
  payDay,

  /// On the real due date, when it is later than the pay-by date: last chance.
  dueDay,

  /// The due date passed and it is still unpaid.
  overdue,
}

/// One notification to show at a specific moment.
class PlannedReminder {
  const PlannedReminder({
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
    required this.occurrenceKey,
  });

  /// Local wall-clock time, e.g. 15 Nov 2026 09:00 on the phone's clock.
  final DateTime at;
  final ReminderKind kind;
  final String title;
  final String body;

  /// Which bill occurrence this is about ([Occurrence.key]).
  final String occurrenceKey;
}

/// Decides WHICH reminders should exist right now.
///
/// It is pure: bills, payments and the current time go in, a list comes out.
/// It never touches the notification plugin, a database or the clock, which is
/// what makes it easy to test thoroughly. Another class turns the list into
/// real scheduled notifications.
class ReminderPlanner {
  const ReminderPlanner({
    this.hour = 9,
    this.minute = 0,
    this.horizonDays = 45,
    this.lookBackDays = 30,
    this.maxReminders = 60,
  });

  /// Time of day reminders fire at.
  final int hour;
  final int minute;

  /// How far ahead to plan. Reminders further out are added when the app next opens.
  final int horizonDays;

  /// How far back to look for unpaid, overdue bills.
  final int lookBackDays;

  /// iOS keeps at most 64 pending notifications, so we stay safely under that.
  final int maxReminders;

  DateTime windowStart(DateTime now) => addDays(dateOnly(now), -lookBackDays);
  DateTime windowEnd(DateTime now) => addDays(dateOnly(now), horizonDays);

  /// [paidKeys] are the [Occurrence.key]s that already have a payment.
  /// [now] is the phone's local time.
  List<PlannedReminder> plan({
    required Iterable<Obligation> obligations,
    required Set<String> paidKeys,
    required DateTime now,
  }) {
    final today = dateOnly(now);
    final occurrences = occurrencesBetween(obligations, windowStart(now), windowEnd(now));
    final out = <PlannedReminder>[];

    for (final occ in occurrences) {
      if (paidKeys.contains(occ.key)) continue;

      if (occ.dueDate.isBefore(today)) {
        // One nudge at the next reminder time; it is refreshed each time the app opens.
        final todaySlot = _at(today);
        final slot = todaySlot.isAfter(now) ? todaySlot : _at(addDays(today, 1));
        out.add(_make(occ, ReminderKind.overdue, slot));
        continue;
      }

      final payBy = occ.payBy;
      _addIfFuture(out, occ, ReminderKind.dayBefore, _at(addDays(payBy, -1)), now);
      _addIfFuture(out, occ, ReminderKind.payDay, _at(payBy), now);
      if (payBy != occ.dueDate) {
        _addIfFuture(out, occ, ReminderKind.dueDay, _at(occ.dueDate), now);
      }
    }

    out.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.title.compareTo(b.title);
    });
    return out.length > maxReminders ? out.sublist(0, maxReminders) : out;
  }

  DateTime _at(DateTime date) => DateTime(date.year, date.month, date.day, hour, minute);

  void _addIfFuture(List<PlannedReminder> out, Occurrence occ, ReminderKind kind, DateTime at, DateTime now) {
    if (at.isAfter(now)) out.add(_make(occ, kind, at));
  }

  PlannedReminder _make(Occurrence occ, ReminderKind kind, DateTime at) {
    final bill = occ.obligation;
    final amount = '${bill.isEstimate ? '~' : ''}${formatSen(bill.amountSen)}';
    final due = formatShortDate(occ.dueDate);
    final sameDay = occ.payBy == occ.dueDate;

    final String title;
    final String body;
    switch (kind) {
      case ReminderKind.dayBefore:
        title = '${bill.name}: pay by tomorrow';
        body = '$amount · due $due';
      case ReminderKind.payDay:
        title = sameDay ? '${bill.name} is due today' : '${bill.name}: time to pay';
        body = sameDay ? amount : '$amount · due $due';
      case ReminderKind.dueDay:
        title = '${bill.name} is due today';
        body = '$amount is still unpaid';
      case ReminderKind.overdue:
        title = '${bill.name} is overdue';
        body = '$amount was due $due';
    }
    return PlannedReminder(at: at, kind: kind, title: title, body: body, occurrenceKey: occ.key);
  }
}
