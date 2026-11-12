import '../core/dates.dart';
import 'budget.dart';
import 'pay_cycle.dart';

/// Totals for the charts: how much was spent in this cycle, and on which days.
class CycleInsights {
  const CycleInsights({
    required this.totalSpentSen,
    required this.dailySen,
    required this.todayIndex,
    required this.averagePerDaySen,
    required this.bySpentSen,
  });

  final int totalSpentSen;

  /// One entry per day of the cycle (index 0 = payday), in sen.
  final List<int> dailySen;

  /// Index of today in [dailySen].
  final int todayIndex;

  /// Total spent divided by the days that have passed (today included).
  final int averagePerDaySen;

  /// Spent per envelope id.
  final Map<String, int> bySpentSen;

  int get biggestDaySen => dailySen.isEmpty ? 0 : dailySen.reduce((a, b) => a > b ? a : b);
}

/// Pure: give it the envelope views, the cycle and today.
CycleInsights buildInsights({required Iterable<EnvelopeView> views, required PayCycle cycle, required DateTime today}) {
  final daily = List<int>.filled(cycle.lengthDays, 0);
  final byEnvelope = <String, int>{};
  var total = 0;

  for (final v in views) {
    for (final s in v.spendings) {
      final index = daysBetween(cycle.start, s.spentOn);
      if (index < 0 || index >= daily.length) continue;
      daily[index] += s.amountSen;
      byEnvelope[v.envelope.id] = (byEnvelope[v.envelope.id] ?? 0) + s.amountSen;
      total += s.amountSen;
    }
  }

  final elapsed = cycle.dayNumber(today);
  return CycleInsights(
    totalSpentSen: total,
    dailySen: daily,
    todayIndex: elapsed - 1,
    averagePerDaySen: (total / elapsed).round(),
    bySpentSen: byEnvelope,
  );
}
