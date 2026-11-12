import '../core/dates.dart';

/// One pay period: from a payday up to the day before the next one.
///
/// With payday on the 25th, 12 Nov falls in the cycle 25 Oct to 24 Nov, and
/// 25 Nov starts the next one. Both ends are included.
class PayCycle {
  const PayCycle({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// The cycle that [date] belongs to, for a payday on [paydayDay] of every month.
  /// A payday of 31 lands on the last day of shorter months (28 or 29 Feb, 30 Apr...).
  factory PayCycle.containing(DateTime date, {required int paydayDay}) {
    final d = dateOnly(date);
    final thisMonth = _payday(d.year, d.month, paydayDay);

    if (!d.isBefore(thisMonth)) {
      return PayCycle(start: thisMonth, end: addDays(_payday(d.year, d.month + 1, paydayDay), -1));
    }
    return PayCycle(start: _payday(d.year, d.month - 1, paydayDay), end: addDays(thisMonth, -1));
  }

  /// The cycle that follows this one.
  PayCycle next({required int paydayDay}) => PayCycle.containing(addDays(end, 1), paydayDay: paydayDay);

  int get lengthDays => daysBetween(start, end) + 1;

  bool contains(DateTime date) {
    final d = dateOnly(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Which day of the cycle [today] is, starting from 1.
  int dayNumber(DateTime today) => (daysBetween(start, today) + 1).clamp(1, lengthDays);

  /// Days from [today] to the end of the cycle, counting today. Never below 1,
  /// so "left per day" never divides by zero.
  int daysLeft(DateTime today) => (daysBetween(today, end) + 1).clamp(1, lengthDays);

  /// The next payday, which is the day after this cycle ends.
  DateTime get nextPayday => addDays(end, 1);

  @override
  bool operator ==(Object other) => other is PayCycle && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'PayCycle(${toIsoDate(start)} .. ${toIsoDate(end)})';
}

/// Payday in the given month. Month 0 or 13 roll into the neighbouring year.
DateTime _payday(int year, int month, int paydayDay) {
  final first = DateTime.utc(year, month, 1);
  return clampedDate(first.year, first.month, paydayDay);
}
