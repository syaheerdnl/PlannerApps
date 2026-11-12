import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/obligation_repository.dart' show Clock, systemClock;
import 'remote_store.dart';

/// One table that is kept in step with the cloud.
class SyncTable {
  const SyncTable(this.name, {this.key = 'id'});

  final String name;

  /// The column that identifies a row (the same on every device).
  final String key;
}

/// Parents before children, so a payment never arrives before its bill.
const kSyncTables = [
  SyncTable('obligations'),
  SyncTable('envelopes'),
  SyncTable('payments'),
  SyncTable('allocations'),
  SyncTable('spendings'),
  SyncTable('settings', key: 'key'),
];

/// Settings that belong to THIS phone and must never be uploaded or overwritten.
bool isLocalOnlySetting(String key) => key.startsWith('sync_') || key == 'default_envelopes_created';

/// How far before the saved cursor each pull starts. See [SyncEngine._pull].
const kPullOverlap = Duration(seconds: 30);

class SyncResult {
  int pushed = 0;
  int pulled = 0;

  /// Two phones changed the same thing; one version was kept.
  int conflicts = 0;

  /// Rows that could not be applied yet (their parent has not arrived). Retried next time.
  int deferred = 0;

  String? error;

  bool get ok => error == null;

  @override
  String toString() =>
      'SyncResult(pushed: $pushed, pulled: $pulled, conflicts: $conflicts, deferred: $deferred, error: $error)';
}

enum _Outcome { applied, skipped, deferred }

/// Keeps the local database and the cloud in step, both ways.
///
/// One run is: PULL everything the cloud has that is new, then PUSH everything
/// that changed on this phone.
///
///  * "Dirty" (needs pushing) means `synced_at` is empty or different from
///    `updated_at`. Pushing sets `synced_at = updated_at`, so any later edit
///    (which changes `updated_at`) makes the row dirty again.
///  * Conflicts are settled per row, last write wins, using `updated_at`.
///  * Deleting is a soft delete (`deleted_at`), so a deletion is just another
///    change that travels to the other phone.
class SyncEngine {
  SyncEngine({required this.db, required this.remote, Clock clock = systemClock, this.pageSize = 200}) : _now = clock;

  final Database db;
  final RemoteStore remote;
  final Clock _now;

  /// Rows per upload.
  final int pageSize;

  final Map<String, List<String>> _columnCache = {};

  Future<SyncResult> sync() async {
    final result = SyncResult();
    try {
      for (final table in kSyncTables) {
        await _pull(table, result);
      }
      for (final table in kSyncTables) {
        await _push(table, result);
      }
      await _setSetting('sync_last_success', _now().toUtc().toIso8601String());
    } catch (e) {
      result.error = '$e';
      if (kDebugMode) debugPrint('Sync failed: $e');
    }
    return result;
  }

  // ── Pull ──────────────────────────────────────────────────────────────────

  Future<void> _pull(SyncTable table, SyncResult result) async {
    final cursorKey = 'sync_cursor_${table.name}';
    final cursor = DateTime.tryParse(await _setting(cursorKey) ?? '');
    // Look back a little before the cursor. A row is stamped when it is SAVED but only becomes
    // visible when its transaction COMMITS; a phone that pulled in between would move its cursor
    // past that row and never fetch it. Re-reading a short window is harmless: a row we already
    // have is identical, so applying it again changes nothing.
    final rows = await remote.pullChanges(table.name, since: cursor?.subtract(kPullOverlap));
    if (rows.isEmpty) return;

    final columns = await _columns(table.name);
    DateTime? newest;
    DateTime? firstDeferred;

    for (final row in rows) {
      final data = _fromRemote(row.data, columns);
      final outcome = await _apply(table, data, result);
      if (outcome == _Outcome.deferred) firstDeferred ??= row.serverUpdatedAt;
      if (newest == null || row.serverUpdatedAt.isAfter(newest)) newest = row.serverUpdatedAt;
    }

    // Move the cursor to the newest row seen, but stop just BEFORE any row we
    // could not apply yet, so it is fetched again next time.
    final next = firstDeferred == null ? newest! : firstDeferred.subtract(const Duration(microseconds: 1));
    if (cursor == null || next.isAfter(cursor)) {
      await _setSetting(cursorKey, next.toUtc().toIso8601String());
    }
  }

  Future<_Outcome> _apply(SyncTable table, Map<String, Object?> data, SyncResult result) async {
    final key = data[table.key];
    if (key == null) return _Outcome.skipped;
    if (table.name == 'settings' && isLocalOnlySetting(key as String)) return _Outcome.skipped;

    final existing = await db.query(table.name, where: '${table.key} = ?', whereArgs: [key], limit: 1);

    if (existing.isEmpty) {
      return _write(table, data, result, insert: true);
    }

    final local = existing.first;
    final order = _time(data['updated_at']).compareTo(_time(local['updated_at']));

    if (order > 0) {
      // The cloud's version is newer: it wins.
      return _write(table, data, result, insert: false);
    }
    if (order == 0 && local['synced_at'] != local['updated_at']) {
      // Same version on both sides: nothing to send, just remember that.
      await db.update(table.name, {'synced_at': local['updated_at']}, where: '${table.key} = ?', whereArgs: [key]);
    }
    // Local is newer (or identical): keep it. It is dirty and goes up in the push step.
    return _Outcome.skipped;
  }

  Future<_Outcome> _write(SyncTable table, Map<String, Object?> data, SyncResult result, {required bool insert}) async {
    final values = {...data, 'synced_at': data['updated_at']};
    try {
      if (insert) {
        await db.insert(table.name, values);
      } else {
        await db.update(table.name, values, where: '${table.key} = ?', whereArgs: [data[table.key]]);
      }
      result.pulled++;
      return _Outcome.applied;
    } on DatabaseException catch (e) {
      final message = e.toString();
      if (message.contains('FOREIGN KEY')) {
        result.deferred++;
        return _Outcome.deferred;
      }
      if (message.contains('UNIQUE') &&
          (table.name == 'payments' || table.name == 'allocations') &&
          data['deleted_at'] == null) {
        return _resolveUniqueConflict(table, data, result);
      }
      rethrow;
    }
  }

  /// Two phones created the same thing independently: both marked the same bill
  /// paid, or both set a budget for the same envelope and cycle. Only one active
  /// row may exist, so pick a winner by a rule BOTH phones apply the same way,
  /// and retire the other one everywhere.
  ///
  ///  * payments: the earlier one wins (either is fine, it just has to agree).
  ///  * allocations: the later edit wins (it is the most recent budget).
  Future<_Outcome> _resolveUniqueConflict(SyncTable table, Map<String, Object?> data, SyncResult result) async {
    final isPayment = table.name == 'payments';
    final rows = await db.query(
      table.name,
      where: isPayment
          ? 'obligation_id = ? AND due_date = ? AND deleted_at IS NULL'
          : 'envelope_id = ? AND cycle_start = ? AND deleted_at IS NULL',
      whereArgs: isPayment ? [data['obligation_id'], data['due_date']] : [data['envelope_id'], data['cycle_start']],
    );
    if (rows.isEmpty) {
      result.deferred++;
      return _Outcome.deferred;
    }
    final local = rows.first;

    int byId() => (data['id'] as String).compareTo(local['id'] as String);
    final bool remoteWins;
    if (isPayment) {
      final c = _time(data['created_at']).compareTo(_time(local['created_at']));
      remoteWins = c != 0 ? c < 0 : byId() < 0;
    } else {
      final c = _time(data['updated_at']).compareTo(_time(local['updated_at']));
      remoteWins = c != 0 ? c > 0 : byId() < 0;
    }

    final stamp = _now().toUtc().toIso8601String();
    if (remoteWins) {
      // Retire OUR copy, then take theirs.
      await db.update(
        table.name,
        {'deleted_at': stamp, 'updated_at': stamp, 'synced_at': null},
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      await db.insert(table.name, {...data, 'synced_at': data['updated_at']});
    } else {
      // Keep ours, and store theirs already retired so the deletion reaches the cloud.
      await db.insert(table.name, {...data, 'deleted_at': stamp, 'updated_at': stamp, 'synced_at': null});
    }
    result.conflicts++;
    result.pulled++;
    return _Outcome.applied;
  }

  // ── Push ──────────────────────────────────────────────────────────────────

  Future<void> _push(SyncTable table, SyncResult result) async {
    final dirty = await db.query(table.name, where: 'synced_at IS NULL OR synced_at <> updated_at');
    final rows = table.name == 'settings'
        ? dirty.where((r) => !isLocalOnlySetting(r['key'] as String)).toList()
        : dirty;

    for (var start = 0; start < rows.length; start += pageSize) {
      final chunk = rows.sublist(start, (start + pageSize).clamp(0, rows.length));
      await remote.push(table.name, [for (final r in chunk) _toRemote(r)]);

      // Mark them synced, but only if they were not edited again while uploading.
      await db.transaction((txn) async {
        for (final r in chunk) {
          await txn.update(
            table.name,
            {'synced_at': r['updated_at']},
            where: '${table.key} = ? AND updated_at = ?',
            whereArgs: [r[table.key], r['updated_at']],
          );
        }
      });
      result.pushed += chunk.length;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, Object?> _toRemote(Map<String, Object?> row) => {...row}..remove('synced_at');

  /// Keeps only columns that exist locally, and writes every timestamp in one format.
  Map<String, Object?> _fromRemote(Map<String, Object?> data, List<String> columns) {
    final out = <String, Object?>{};
    for (final column in columns) {
      if (column == 'synced_at' || !data.containsKey(column)) continue;
      final value = data[column];
      out[column] = (value is String && _isTimestampColumn(column)) ? _time(value).toUtc().toIso8601String() : value;
    }
    return out;
  }

  /// created_at, updated_at, deleted_at, paid_at. Calendar dates (due_date) stay as they are.
  bool _isTimestampColumn(String column) => column.endsWith('_at');

  DateTime _time(Object? value) => DateTime.parse(value as String).toUtc();

  Future<List<String>> _columns(String table) async {
    return _columnCache[table] ??= [
      for (final row in await db.rawQuery('PRAGMA table_info($table)')) row['name'] as String,
    ];
  }

  Future<String?> _setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Sync's own bookkeeping, stored without touching `updated_at` semantics:
  /// these keys are local-only, so they are never uploaded.
  Future<void> _setSetting(String key, String value) {
    return db.insert('settings', {
      'key': key,
      'value': value,
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
