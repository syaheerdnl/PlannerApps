import '../core/dates.dart';
import 'pay_cycle.dart';

const _keep = Object();

/// A named pot of money for one kind of spending: Fuel, Food, Savings...
class Envelope {
  const Envelope({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Envelope copyWith({String? name, int? sortOrder, DateTime? updatedAt, Object? deletedAt = _keep}) => Envelope(
    id: id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory Envelope.fromMap(Map<String, Object?> m) => Envelope(
    id: m['id'] as String,
    name: m['name'] as String,
    sortOrder: m['sort_order'] as int,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );
}

/// How much money an envelope gets in one pay cycle.
///
/// Only cycles where you changed something have a row. A cycle with no row
/// inherits the latest earlier one (see [allocationFor]), so a plan carries
/// over month after month without you re-entering it.
class Allocation {
  const Allocation({
    required this.id,
    required this.envelopeId,
    required this.cycleStart,
    required this.amountSen,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String envelopeId;

  /// The first day of the pay cycle this applies to.
  final DateTime cycleStart;
  final int amountSen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'envelope_id': envelopeId,
    'cycle_start': toIsoDate(cycleStart),
    'amount_sen': amountSen,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory Allocation.fromMap(Map<String, Object?> m) => Allocation(
    id: m['id'] as String,
    envelopeId: m['envelope_id'] as String,
    cycleStart: fromIsoDate(m['cycle_start'] as String),
    amountSen: m['amount_sen'] as int,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );
}

/// Money you spent out of an envelope.
class Spending {
  const Spending({
    required this.id,
    required this.envelopeId,
    required this.amountSen,
    required this.spentOn,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String envelopeId;
  final int amountSen;
  final String? note;
  final DateTime spentOn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'envelope_id': envelopeId,
    'amount_sen': amountSen,
    'note': note,
    'spent_on': toIsoDate(spentOn),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory Spending.fromMap(Map<String, Object?> m) => Spending(
    id: m['id'] as String,
    envelopeId: m['envelope_id'] as String,
    amountSen: m['amount_sen'] as int,
    note: m['note'] as String?,
    spentOn: fromIsoDate(m['spent_on'] as String),
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );
}

/// Your salary and the day of the month it arrives.
class PlanSettings {
  const PlanSettings({required this.paydayDay, required this.salarySen});

  final int paydayDay;
  final int salarySen;

  @override
  bool operator ==(Object other) =>
      other is PlanSettings && other.paydayDay == paydayDay && other.salarySen == salarySen;

  @override
  int get hashCode => Object.hash(paydayDay, salarySen);
}

/// The budget for [envelopeId] in the cycle starting [cycleStart]: that exact
/// cycle's row if there is one, otherwise the most recent earlier row, else 0.
int allocationFor(Iterable<Allocation> all, String envelopeId, DateTime cycleStart) {
  Allocation? best;
  for (final a in all) {
    if (a.envelopeId != envelopeId || a.cycleStart.isAfter(cycleStart)) continue;
    if (best == null || a.cycleStart.isAfter(best.cycleStart)) best = a;
  }
  return best?.amountSen ?? 0;
}

/// How an envelope is doing against the clock.
enum Pace {
  /// No budget set, so there is nothing to compare with.
  none,

  /// Well ahead: much more left than the calendar suggests.
  underPace,
  onTrack,

  /// Spending a little quicker than the cycle allows.
  fast,

  /// More spent than the budget.
  over,
}

/// Everything the Envelopes screen shows for one envelope in one cycle.
class EnvelopeView {
  const EnvelopeView({
    required this.envelope,
    required this.budgetSen,
    required this.spentSen,
    required this.spendings,
    required this.dailySafeSen,
    required this.pace,
    required this.expectedLeftFraction,
  });

  final Envelope envelope;
  final int budgetSen;
  final int spentSen;

  /// Spendings in this cycle, newest first.
  final List<Spending> spendings;

  /// What you can spend each remaining day (today included) without running out.
  final int dailySafeSen;
  final Pace pace;

  /// Where the bar "should" be today, from 1.0 (cycle start) down to 0.0 (last day).
  final double expectedLeftFraction;

  int get leftSen => budgetSen - spentSen;

  /// 0..1 for drawing the bar.
  double get leftFraction => budgetSen <= 0 ? 0 : (leftSen / budgetSen).clamp(0.0, 1.0);
}

/// Works out an [EnvelopeView]. Pure: give it the data and the date.
EnvelopeView buildEnvelopeView({
  required Envelope envelope,
  required Iterable<Allocation> allocations,
  required Iterable<Spending> spendings,
  required PayCycle cycle,
  required DateTime today,
}) {
  final budget = allocationFor(allocations, envelope.id, cycle.start);
  final inCycle = spendings.where((s) => s.envelopeId == envelope.id && cycle.contains(s.spentOn)).toList()
    ..sort((a, b) {
      final byDate = b.spentOn.compareTo(a.spentOn);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
  final spent = inCycle.fold<int>(0, (sum, s) => sum + s.amountSen);
  final left = budget - spent;

  final daysLeft = cycle.daysLeft(today);
  final daily = left > 0 ? (left / daysLeft).round() : 0;
  final expected = 1 - cycle.dayNumber(today) / cycle.lengthDays;

  final Pace pace;
  if (budget <= 0) {
    pace = Pace.none;
  } else if (left < 0) {
    pace = Pace.over;
  } else {
    final diff = left / budget - expected;
    pace = diff < -0.01
        ? Pace.fast
        : diff > 0.08
        ? Pace.underPace
        : Pace.onTrack;
  }

  return EnvelopeView(
    envelope: envelope,
    budgetSen: budget,
    spentSen: spent,
    spendings: inCycle,
    dailySafeSen: daily,
    pace: pace,
    expectedLeftFraction: expected,
  );
}
