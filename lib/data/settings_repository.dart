import 'package:sqflite/sqflite.dart';

import '../domain/budget.dart';
import 'obligation_repository.dart' show Clock, systemClock;

/// Small named values: your payday, your salary, and flags such as "the default
/// envelopes were already created".
class SettingsRepository {
  SettingsRepository(this._db, {Clock clock = systemClock}) : _now = clock;

  final Database _db;
  final Clock _now;

  static const _paydayKey = 'payday_day';
  static const _salaryKey = 'salary_sen';

  Future<String?> get(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String value) {
    return _db.insert('settings', {
      'key': key,
      'value': value,
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Null until you have set up your payday and salary.
  Future<PlanSettings?> loadPlan() async {
    final payday = int.tryParse(await get(_paydayKey) ?? '');
    final salary = int.tryParse(await get(_salaryKey) ?? '');
    if (payday == null || salary == null) return null;
    return PlanSettings(paydayDay: payday, salarySen: salary);
  }

  Future<void> savePlan(PlanSettings plan) async {
    if (plan.paydayDay < 1 || plan.paydayDay > 31) {
      throw ArgumentError.value(plan.paydayDay, 'paydayDay', 'must be 1 to 31');
    }
    if (plan.salarySen < 0) throw ArgumentError.value(plan.salarySen, 'salarySen', 'must not be negative');
    await _db.transaction((txn) async {
      final stamp = _now().toUtc().toIso8601String();
      for (final entry in {_paydayKey: '${plan.paydayDay}', _salaryKey: '${plan.salarySen}'}.entries) {
        await txn.insert('settings', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': stamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
