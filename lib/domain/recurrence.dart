import '../core/dates.dart';
import 'obligation.dart';
import 'payment.dart' show paymentKey;

// Safety net so a silly range (year 1 to year 9999 on a weekly bill) cannot
// freeze the app.
const _maxResults = 5000;

/// Every due date of [o] from [from] to [to], both ends included.
///
/// The rule is only: first due date + how often + every N. Each date is
/// worked out from the START date, never from the previous date. That matters
/// for "the 31st": counting from the previous date would go
/// 31 Jan -> 28 Feb -> 28 Mar (it drifts). Counting from the start gives
/// 31 Jan -> 28 Feb -> 31 Mar, which is what a bill due "on the 31st" means.
List<DateTime> dueDatesBetween(Obligation o, DateTime from, DateTime to) {
  final start = dateOnly(o.startDate);
  final lo = dateOnly(from);
  final hi = _earlier(dateOnly(to), o.endDate == null ? null : dateOnly(o.endDate!));
  if (hi.isBefore(lo)) return const [];

  final n = o.intervalCount < 1 ? 1 : o.intervalCount;

  switch (o.frequency) {
    case Frequency.once:
      return (start.isBefore(lo) || start.isAfter(hi)) ? const [] : [start];

    case Frequency.weekly:
      final step = 7 * n;
      // Jump straight to the first date at or after `lo` instead of walking
      // from the start date. (Round up the division.)
      var k = lo.isAfter(start) ? (daysBetween(start, lo) + step - 1) ~/ step : 0;
      final out = <DateTime>[];
      while (out.length < _maxResults) {
        final d = addDays(start, k * step);
        if (d.isAfter(hi)) break;
        out.add(d);
        k++;
      }
      return out;

    case Frequency.monthly:
      final monthsApart = (lo.year - start.year) * 12 + (lo.month - start.month);
      // Start one step early; the loop below skips anything before `lo`.
      var k = monthsApart > 0 ? (monthsApart ~/ n) - 1 : 0;
      if (k < 0) k = 0;
      final out = <DateTime>[];
      for (; ; k++) {
        final monthIndex = start.month - 1 + k * n; // months since January of start.year
        final d = clampedDate(start.year + monthIndex ~/ 12, monthIndex % 12 + 1, start.day);
        if (d.isAfter(hi) || out.length >= _maxResults) break;
        if (d.isBefore(lo)) continue;
        out.add(d);
      }
      return out;

    case Frequency.yearly:
      final yearsApart = lo.year - start.year;
      var k = yearsApart > 0 ? (yearsApart ~/ n) - 1 : 0;
      if (k < 0) k = 0;
      final out = <DateTime>[];
      for (; ; k++) {
        // A 29 Feb bill lands on 28 Feb in normal years and 29 Feb in leap years.
        final d = clampedDate(start.year + k * n, start.month, start.day);
        if (d.isAfter(hi) || out.length >= _maxResults) break;
        if (d.isBefore(lo)) continue;
        out.add(d);
      }
      return out;
  }
}

/// The first due date on or after [date], or null if the bill never comes due again.
DateTime? nextDueOnOrAfter(Obligation o, DateTime date) {
  final n = o.intervalCount < 1 ? 1 : o.intervalCount;
  // 370 days per step is always enough to contain at least one occurrence.
  final dates = dueDatesBetween(o, date, addDays(dateOnly(date), 370 * n));
  return dates.isEmpty ? null : dates.first;
}

/// Where a single occurrence stands, as of a given day.
enum DueStatus {
  /// A payment exists for it.
  paid,

  /// Due date has passed and it is not paid.
  overdue,

  /// Today is inside the window [pay-by date .. due date]: time to pay it.
  payNow,

  /// Pay-by date has not arrived yet.
  upcoming,
}

/// One real due date of one bill, e.g. "Car loan, 17 Nov 2026".
class Occurrence {
  const Occurrence(this.obligation, this.dueDate);

  final Obligation obligation;
  final DateTime dueDate;

  /// The date YOU aim to pay by: the due date minus the bill's buffer.
  DateTime get payBy => addDays(dueDate, -obligation.payByBufferDays);

  int get amountSen => obligation.amountSen;

  /// Matches [Payment.key], so `paidMap.containsKey(occurrence.key)` says if it is paid.
  String get key => paymentKey(obligation.id, dueDate);

  /// 0 = due today, 1 = due tomorrow, negative = already past.
  int daysUntilDue(DateTime today) => daysBetween(today, dueDate);

  DueStatus statusOn(DateTime today, {required bool paid}) {
    if (paid) return DueStatus.paid;
    final t = dateOnly(today);
    if (dueDate.isBefore(t)) return DueStatus.overdue;
    if (!payBy.isAfter(t)) return DueStatus.payNow;
    return DueStatus.upcoming;
  }
}

/// All occurrences of all [obligations] from [from] to [to], soonest first.
/// Same-day items are ordered by name so the list never reshuffles.
List<Occurrence> occurrencesBetween(Iterable<Obligation> obligations, DateTime from, DateTime to) {
  final out = <Occurrence>[
    for (final o in obligations)
      for (final d in dueDatesBetween(o, from, to)) Occurrence(o, d),
  ];
  out.sort((a, b) {
    final byDate = a.dueDate.compareTo(b.dueDate);
    return byDate != 0 ? byDate : a.obligation.name.toLowerCase().compareTo(b.obligation.name.toLowerCase());
  });
  return out;
}

DateTime _earlier(DateTime a, DateTime? b) => (b != null && b.isBefore(a)) ? b : a;
