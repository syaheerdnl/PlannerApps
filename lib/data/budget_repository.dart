import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/dates.dart';
import '../domain/budget.dart';
import 'obligation_repository.dart' show Clock, systemClock;
import 'settings_repository.dart';

/// Envelopes, their per-cycle budgets, and the spending taken out of them.
/// Like the bills repositories, it is the only code that writes SQL for these tables.
class BudgetRepository {
  BudgetRepository(this._db, this._settings, {Clock clock = systemClock, this._uuid = const Uuid()}) : _now = clock;

  final Database _db;
  final SettingsRepository _settings;
  final Clock _now;
  final Uuid _uuid;

  static const defaultEnvelopeNames = ['Fuel', 'Food', 'Other'];
  static const _seededKey = 'default_envelopes_created';

  // ── Envelopes ─────────────────────────────────────────────────────────────

  Future<List<Envelope>> envelopes() async {
    final rows = await _db.query('envelopes', where: 'deleted_at IS NULL', orderBy: 'sort_order, created_at');
    return rows.map(Envelope.fromMap).toList();
  }

  Future<Envelope> createEnvelope(String name) async {
    final clean = _cleanName(name);
    final now = _now();
    final existing = await envelopes();
    if (existing.any((e) => e.name.toLowerCase() == clean.toLowerCase())) {
      throw ArgumentError.value(name, 'name', 'an envelope with this name already exists');
    }
    final next = existing.isEmpty ? 0 : existing.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final envelope = Envelope(id: _uuid.v4(), name: clean, sortOrder: next, createdAt: now, updatedAt: now);
    await _db.insert('envelopes', envelope.toMap());
    return envelope;
  }

  Future<Envelope> renameEnvelope(String id, String name) async {
    final clean = _cleanName(name);
    final all = await envelopes();
    final current = all.firstWhere((e) => e.id == id, orElse: () => throw StateError('Envelope $id not found'));
    if (all.any((e) => e.id != id && e.name.toLowerCase() == clean.toLowerCase())) {
      throw ArgumentError.value(name, 'name', 'an envelope with this name already exists');
    }
    final renamed = current.copyWith(name: clean, updatedAt: _now());
    await _db.update('envelopes', renamed.toMap(), where: 'id = ?', whereArgs: [id]);
    return renamed;
  }

  /// Soft delete: hides the envelope with its budgets and spending, keeps the rows.
  Future<void> deleteEnvelope(String id) async {
    final stamp = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      for (final table in ['spendings', 'allocations']) {
        await txn.update(
          table,
          {'deleted_at': stamp, 'updated_at': stamp},
          where: 'envelope_id = ? AND deleted_at IS NULL',
          whereArgs: [id],
        );
      }
      await txn.update(
        'envelopes',
        {'deleted_at': stamp, 'updated_at': stamp},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  /// Creates Fuel, Food and Other the very first time, and never again. Without
  /// the flag, deleting an envelope would bring it back on the next launch.
  ///
  /// Each default has a FIXED id (the same on every phone). Two phones that both
  /// create "Fuel" on first launch then create the very same envelope, so syncing
  /// merges them into one instead of leaving two "Fuel" envelopes.
  Future<void> createDefaultEnvelopesOnce() async {
    if (await _settings.get(_seededKey) != null) return;
    if ((await envelopes()).isEmpty) {
      final now = _now();
      for (var i = 0; i < defaultEnvelopeNames.length; i++) {
        final name = defaultEnvelopeNames[i];
        await _db.insert(
          'envelopes',
          Envelope(id: defaultEnvelopeId(name), name: name, sortOrder: i, createdAt: now, updatedAt: now).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await _settings.set(_seededKey, '1');
  }

  /// The same id on every device for a given default name.
  static String defaultEnvelopeId(String name) =>
      const Uuid().v5(Namespace.url.value, 'bayar:default-envelope:${name.toLowerCase()}');

  // ── Allocations (the budget per cycle) ────────────────────────────────────

  Future<List<Allocation>> allocations() async {
    final rows = await _db.query('allocations', where: 'deleted_at IS NULL');
    return rows.map(Allocation.fromMap).toList();
  }

  /// Sets how much [envelopeId] gets in the cycle starting [cycleStart].
  Future<void> setAllocation({required String envelopeId, required DateTime cycleStart, required int amountSen}) async {
    if (amountSen < 0) throw ArgumentError.value(amountSen, 'amountSen', 'must not be negative');
    final now = _now();
    final stamp = now.toUtc().toIso8601String();
    final day = toIsoDate(cycleStart);

    final updated = await _db.update(
      'allocations',
      {'amount_sen': amountSen, 'updated_at': stamp},
      where: 'envelope_id = ? AND cycle_start = ? AND deleted_at IS NULL',
      whereArgs: [envelopeId, day],
    );
    if (updated > 0) return;

    await _db.insert(
      'allocations',
      Allocation(
        id: _uuid.v4(),
        envelopeId: envelopeId,
        cycleStart: dateOnly(cycleStart),
        amountSen: amountSen,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
  }

  // ── Spending ──────────────────────────────────────────────────────────────

  Future<Spending> addSpending({
    required String envelopeId,
    required int amountSen,
    required DateTime spentOn,
    String? note,
  }) async {
    if (amountSen <= 0) throw ArgumentError.value(amountSen, 'amountSen', 'must be more than 0');
    final now = _now();
    final trimmed = note?.trim();
    final spending = Spending(
      id: _uuid.v4(),
      envelopeId: envelopeId,
      amountSen: amountSen,
      note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      spentOn: dateOnly(spentOn),
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('spendings', spending.toMap());
    return spending;
  }

  Future<void> deleteSpending(String id) async {
    final stamp = _now().toUtc().toIso8601String();
    await _db.update(
      'spendings',
      {'deleted_at': stamp, 'updated_at': stamp},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  /// Spending dated from [from] to [to], both included, for envelopes that still exist.
  Future<List<Spending>> spendingsBetween(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
      '''
      SELECT s.* FROM spendings s
      JOIN envelopes e ON e.id = s.envelope_id AND e.deleted_at IS NULL
      WHERE s.deleted_at IS NULL AND s.spent_on BETWEEN ? AND ?
      ORDER BY s.spent_on DESC, s.created_at DESC
      ''',
      [toIsoDate(from), toIsoDate(to)],
    );
    return rows.map(Spending.fromMap).toList();
  }

  String _cleanName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    return clean;
  }
}
