import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/dates.dart';
import '../domain/payment.dart';
import 'obligation_repository.dart' show Clock, systemClock;

class PaymentRepository {
  PaymentRepository(this._db, {Clock clock = systemClock, this._uuid = const Uuid()}) : _now = clock;

  final Database _db;
  final Clock _now;
  final Uuid _uuid;

  /// Records that the occurrence due on [dueDate] was paid.
  /// Safe to call twice: if it is already marked paid, the existing record is returned.
  Future<Payment> markPaid({required String obligationId, required DateTime dueDate, required int amountSen}) async {
    final existing = await _active(obligationId, dueDate);
    if (existing != null) return existing;

    final now = _now();
    final payment = Payment(
      id: _uuid.v4(),
      obligationId: obligationId,
      dueDate: dateOnly(dueDate),
      amountSen: amountSen,
      paidAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('payments', payment.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
    return payment;
  }

  /// Undo: soft-deletes the payment. Returns false if there was nothing to undo.
  Future<bool> undoPaid({required String obligationId, required DateTime dueDate}) async {
    final stamp = _now().toIso8601String();
    final rows = await _db.update(
      'payments',
      {'deleted_at': stamp, 'updated_at': stamp},
      where: 'obligation_id = ? AND due_date = ? AND deleted_at IS NULL',
      whereArgs: [obligationId, toIsoDate(dueDate)],
    );
    return rows > 0;
  }

  Future<List<Payment>> forObligation(String obligationId) async {
    final rows = await _db.query(
      'payments',
      where: 'obligation_id = ? AND deleted_at IS NULL',
      whereArgs: [obligationId],
      orderBy: 'due_date DESC',
    );
    return rows.map(Payment.fromMap).toList();
  }

  /// Payments whose due date falls in [from]..[to] inclusive, keyed by
  /// [Payment.key] so a screen can ask "is this occurrence paid?" in O(1).
  Future<Map<String, Payment>> paidBetween(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'payments',
      where: 'deleted_at IS NULL AND due_date BETWEEN ? AND ?',
      whereArgs: [toIsoDate(from), toIsoDate(to)],
    );
    return {for (final r in rows) Payment.fromMap(r).key: Payment.fromMap(r)};
  }

  Future<Payment?> _active(String obligationId, DateTime dueDate) async {
    final rows = await _db.query(
      'payments',
      where: 'obligation_id = ? AND due_date = ? AND deleted_at IS NULL',
      whereArgs: [obligationId, toIsoDate(dueDate)],
      limit: 1,
    );
    return rows.isEmpty ? null : Payment.fromMap(rows.first);
  }
}
