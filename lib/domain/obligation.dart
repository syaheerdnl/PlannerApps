import '../core/dates.dart';

/// How often a bill repeats.
///
/// Together with [Obligation.startDate] and [Obligation.intervalCount] this is
/// the whole recurrence rule. "Monthly, every 1, starting 17 Nov" means the
/// 17th of every month. "Monthly, every 3, starting 28 Oct" is a quarterly bill.
enum Frequency { once, weekly, monthly, yearly }

const _keep = Object();

/// One thing you have to pay: a bill, a subscription, an instalment.
///
/// This stores the RULE, not a list of dates. The actual due dates are worked
/// out when needed (see the recurrence engine), so editing a bill never leaves
/// old generated rows behind.
class Obligation {
  const Obligation({
    required this.id,
    required this.name,
    required this.amountSen,
    required this.frequency,
    required this.startDate,
    required this.createdAt,
    required this.updatedAt,
    this.isEstimate = false,
    this.intervalCount = 1,
    this.endDate,
    this.payByBufferDays = 0,
    this.note,
    this.deletedAt,
  });

  /// A UUID made on the phone, so two devices can never pick the same id.
  final String id;
  final String name;

  /// Whole sen. For an estimate (like electricity) this is your best guess.
  final int amountSen;
  final bool isEstimate;

  final Frequency frequency;

  /// "Every [intervalCount] months/weeks/years". Always 1 or more.
  final int intervalCount;

  /// The first due date. Later due dates are derived from it.
  final DateTime startDate;

  /// Last day this bill applies (e.g. final loan instalment). Null = forever.
  final DateTime? endDate;

  /// You want to pay this many days BEFORE the real due date.
  final int payByBufferDays;
  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft delete: the row stays, but the app hides it. Sync needs this so a
  /// deletion on one phone can reach the other phone.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Obligation copyWith({
    String? name,
    int? amountSen,
    bool? isEstimate,
    Frequency? frequency,
    int? intervalCount,
    DateTime? startDate,
    Object? endDate = _keep,
    int? payByBufferDays,
    Object? note = _keep,
    DateTime? updatedAt,
    Object? deletedAt = _keep,
  }) {
    return Obligation(
      id: id,
      name: name ?? this.name,
      amountSen: amountSen ?? this.amountSen,
      isEstimate: isEstimate ?? this.isEstimate,
      frequency: frequency ?? this.frequency,
      intervalCount: intervalCount ?? this.intervalCount,
      startDate: startDate ?? this.startDate,
      endDate: identical(endDate, _keep) ? this.endDate : endDate as DateTime?,
      payByBufferDays: payByBufferDays ?? this.payByBufferDays,
      note: identical(note, _keep) ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'amount_sen': amountSen,
    'is_estimate': isEstimate ? 1 : 0,
    'frequency': frequency.name,
    'interval_count': intervalCount,
    'start_date': toIsoDate(startDate),
    'end_date': endDate == null ? null : toIsoDate(endDate!),
    'pay_by_buffer_days': payByBufferDays,
    'note': note,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory Obligation.fromMap(Map<String, Object?> m) {
    return Obligation(
      id: m['id'] as String,
      name: m['name'] as String,
      amountSen: m['amount_sen'] as int,
      isEstimate: (m['is_estimate'] as int) == 1,
      frequency: Frequency.values.byName(m['frequency'] as String),
      intervalCount: m['interval_count'] as int,
      startDate: fromIsoDate(m['start_date'] as String),
      endDate: m['end_date'] == null ? null : fromIsoDate(m['end_date'] as String),
      payByBufferDays: m['pay_by_buffer_days'] as int,
      note: m['note'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
    );
  }
}
