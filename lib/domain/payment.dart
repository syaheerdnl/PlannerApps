import '../core/dates.dart';

/// A record that ONE occurrence of a bill was paid.
///
/// The bill "Car loan, due 17th monthly" is a single [Obligation]. Each month
/// you pay it, one Payment row is added with that month's [dueDate].
/// "Is the 17 Nov car loan paid?" simply means "does a Payment exist for
/// (car loan, 2026-11-17)?". Undoing a payment soft-deletes the row.
class Payment {
  const Payment({
    required this.id,
    required this.obligationId,
    required this.dueDate,
    required this.amountSen,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String obligationId;

  /// Which occurrence this paid (a calendar date, not a time).
  final DateTime dueDate;

  /// What was actually paid. For an estimated bill this can differ from the
  /// obligation's amount.
  final int amountSen;
  final DateTime paidAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Handy lookup key: the obligation id, a pipe, then the date (`abc|2026-11-17`).
  String get key => paymentKey(obligationId, dueDate);

  Payment copyWith({DateTime? updatedAt, DateTime? deletedAt}) => Payment(
    id: id,
    obligationId: obligationId,
    dueDate: dueDate,
    amountSen: amountSen,
    paidAt: paidAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'obligation_id': obligationId,
    'due_date': toIsoDate(dueDate),
    'amount_sen': amountSen,
    'paid_at': paidAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory Payment.fromMap(Map<String, Object?> m) {
    return Payment(
      id: m['id'] as String,
      obligationId: m['obligation_id'] as String,
      dueDate: fromIsoDate(m['due_date'] as String),
      amountSen: m['amount_sen'] as int,
      paidAt: DateTime.parse(m['paid_at'] as String),
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
    );
  }
}

String paymentKey(String obligationId, DateTime dueDate) => '$obligationId|${toIsoDate(dueDate)}';
