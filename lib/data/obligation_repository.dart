import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/obligation.dart';

typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now().toUtc();

/// The only place that talks SQL about bills. The rest of the app asks this
/// class for [Obligation] objects and never sees a table.
class ObligationRepository {
  ObligationRepository(this._db, {Clock clock = systemClock, this._uuid = const Uuid()}) : _now = clock;

  final Database _db;
  final Clock _now;
  final Uuid _uuid;

  Future<Obligation> create({
    required String name,
    required int amountSen,
    required Frequency frequency,
    required DateTime startDate,
    bool isEstimate = false,
    int intervalCount = 1,
    DateTime? endDate,
    int payByBufferDays = 0,
    String? note,
  }) async {
    final now = _now();
    final obligation = Obligation(
      id: _uuid.v4(),
      name: name.trim(),
      amountSen: amountSen,
      isEstimate: isEstimate,
      frequency: frequency,
      intervalCount: intervalCount,
      startDate: startDate,
      endDate: endDate,
      payByBufferDays: payByBufferDays,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    _validate(obligation);
    await _db.insert('obligations', obligation.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
    return obligation;
  }

  /// Saves changes and stamps a new `updated_at` (sync uses it to know what changed).
  Future<Obligation> update(Obligation obligation) async {
    final updated = obligation.copyWith(name: obligation.name.trim(), updatedAt: _now());
    _validate(updated);
    final rows = await _db.update(
      'obligations',
      updated.toMap(),
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [updated.id],
    );
    if (rows == 0) throw StateError('Bill ${updated.id} does not exist or was deleted');
    return updated;
  }

  /// Soft delete: hides the bill and its payments, but keeps the rows.
  Future<void> delete(String id) async {
    final stamp = _now().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update(
        'payments',
        {'deleted_at': stamp, 'updated_at': stamp},
        where: 'obligation_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      await txn.update(
        'obligations',
        {'deleted_at': stamp, 'updated_at': stamp},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  Future<Obligation?> byId(String id) async {
    final rows = await _db.query('obligations', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Obligation.fromMap(rows.first);
  }

  Future<List<Obligation>> all() async {
    final rows = await _db.query('obligations', where: 'deleted_at IS NULL', orderBy: 'name COLLATE NOCASE');
    return rows.map(Obligation.fromMap).toList();
  }

  void _validate(Obligation o) {
    if (o.name.isEmpty) throw ArgumentError.value(o.name, 'name', 'must not be empty');
    if (o.amountSen < 0) throw ArgumentError.value(o.amountSen, 'amountSen', 'must not be negative');
    if (o.intervalCount < 1) throw ArgumentError.value(o.intervalCount, 'intervalCount', 'must be at least 1');
    if (o.payByBufferDays < 0) throw ArgumentError.value(o.payByBufferDays, 'payByBufferDays', 'must not be negative');
    if (o.endDate != null && o.endDate!.isBefore(o.startDate)) {
      throw ArgumentError.value(o.endDate, 'endDate', 'must not be before the start date');
    }
  }
}
