import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'budget_repository.dart';

/// Opens (and on first launch, creates) the local SQLite database.
///
/// The phone's database is the source of truth. Sync to the cloud works from
/// the `updated_at`, `deleted_at` and `synced_at` columns that every table has.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  /// Bump this when the tables change, and add a step to [_onUpgrade].
  ///
  /// 1: bills and payments.
  /// 2: envelopes, allocations, spendings and settings (Phase 2).
  /// 3: settings can be synced too (Phase 3).
  /// 4: the default envelopes get the same fixed ids on every phone.
  static const schemaVersion = 4;

  /// [path] and [factory] exist so tests can open an in-memory database.
  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'bayar.db');

    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: false,
        // SQLite ignores FOREIGN KEY rules unless you switch them on per connection.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();

  /// A brand-new install: everything from version 1, then everything added since.
  static Future<void> _onCreate(Database db, int version) async {
    await createV1Schema(db);
    await createV2Schema(db);
    await createV3Schema(db);
  }

  /// A phone that already has an older database: add only what is missing.
  /// Existing bills and payments are never touched.
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await createV2Schema(db);
    if (oldVersion < 3) await createV3Schema(db);
    if (oldVersion < 4) await migrateDefaultEnvelopeIds(db);
    // Future versions: add `if (oldVersion < 3) { ... }` here, one block each.
  }

  /// Version 1: bills and payments. Public so tests can build an "old phone".
  @visibleForTesting
  static Future<void> createV1Schema(Database db) async {
    await db.execute('''
      CREATE TABLE obligations (
        id                 TEXT PRIMARY KEY,
        name               TEXT NOT NULL,
        amount_sen         INTEGER NOT NULL CHECK (amount_sen >= 0),
        is_estimate        INTEGER NOT NULL DEFAULT 0,
        frequency          TEXT NOT NULL,
        interval_count     INTEGER NOT NULL DEFAULT 1 CHECK (interval_count >= 1),
        start_date         TEXT NOT NULL,
        end_date           TEXT,
        pay_by_buffer_days INTEGER NOT NULL DEFAULT 0 CHECK (pay_by_buffer_days >= 0),
        note               TEXT,
        created_at         TEXT NOT NULL,
        updated_at         TEXT NOT NULL,
        deleted_at         TEXT,
        synced_at          TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id            TEXT PRIMARY KEY,
        obligation_id TEXT NOT NULL REFERENCES obligations(id),
        due_date      TEXT NOT NULL,
        amount_sen    INTEGER NOT NULL CHECK (amount_sen >= 0),
        paid_at       TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL,
        deleted_at    TEXT,
        synced_at     TEXT
      )
    ''');

    // One ACTIVE payment per bill per due date. Soft-deleted (undone) rows are
    // ignored, so you can mark paid, undo, and mark paid again.
    await db.execute('''
      CREATE UNIQUE INDEX idx_payments_one_active
      ON payments (obligation_id, due_date)
      WHERE deleted_at IS NULL
    ''');

    await db.execute('CREATE INDEX idx_payments_due ON payments (due_date)');
  }

  /// Version 2: the budget. Envelopes hold money, allocations say how much each
  /// gets per pay cycle, spendings are what you took out, settings hold the
  /// payday and salary.
  @visibleForTesting
  static Future<void> createV2Schema(Database db) async {
    await db.execute('''
      CREATE TABLE envelopes (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        synced_at   TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE allocations (
        id          TEXT PRIMARY KEY,
        envelope_id TEXT NOT NULL REFERENCES envelopes(id),
        cycle_start TEXT NOT NULL,
        amount_sen  INTEGER NOT NULL CHECK (amount_sen >= 0),
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        synced_at   TEXT
      )
    ''');

    // One active budget row per envelope per cycle.
    await db.execute('''
      CREATE UNIQUE INDEX idx_allocations_one_active
      ON allocations (envelope_id, cycle_start)
      WHERE deleted_at IS NULL
    ''');

    await db.execute('''
      CREATE TABLE spendings (
        id          TEXT PRIMARY KEY,
        envelope_id TEXT NOT NULL REFERENCES envelopes(id),
        amount_sen  INTEGER NOT NULL CHECK (amount_sen > 0),
        note        TEXT,
        spent_on    TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        synced_at   TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_spendings_date ON spendings (spent_on)');

    await db.execute('''
      CREATE TABLE settings (
        key        TEXT PRIMARY KEY,
        value      TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Version 3: lets settings (payday, salary) sync like every other table.
  /// Every other table already had `synced_at` from the start.
  @visibleForTesting
  static Future<void> createV3Schema(Database db) async {
    await db.execute('ALTER TABLE settings ADD COLUMN synced_at TEXT');
  }

  /// Version 4. Before this, the default envelopes (Fuel, Food, Other) were made
  /// with RANDOM ids, so a second phone's "Fuel" was a different envelope and
  /// syncing produced two. They now have the same fixed id everywhere.
  ///
  /// For each default name this phone has under a random id: create the fixed-id
  /// envelope, move the budgets and spending onto it, and retire the old one with
  /// a soft delete, which syncs like any other change. Every touched row is
  /// marked "not yet synced" so it travels to the cloud.
  @visibleForTesting
  static Future<void> migrateDefaultEnvelopeIds(Database db, {DateTime? now}) async {
    final stamp = (now ?? DateTime.now()).toUtc().toIso8601String();

    await db.transaction((txn) async {
      for (final name in BudgetRepository.defaultEnvelopeNames) {
        final fixedId = BudgetRepository.defaultEnvelopeId(name);

        final legacy = await txn.query(
          'envelopes',
          where: 'lower(name) = ? AND deleted_at IS NULL AND id <> ?',
          whereArgs: [name.toLowerCase(), fixedId],
        );
        if (legacy.isEmpty) continue;

        final fixed = await txn.query('envelopes', where: 'id = ?', whereArgs: [fixedId]);
        // If the fixed envelope was deleted on purpose (on another phone), leave things alone.
        if (fixed.isNotEmpty && fixed.first['deleted_at'] != null) continue;

        if (fixed.isEmpty) {
          final first = legacy.first;
          await txn.insert('envelopes', {
            'id': fixedId,
            'name': first['name'],
            'sort_order': first['sort_order'],
            'created_at': first['created_at'],
            'updated_at': stamp,
            'deleted_at': null,
            'synced_at': null,
          });
        }

        for (final old in legacy) {
          final oldId = old['id'];

          // Budgets: at most one active row per envelope and cycle. If the fixed
          // envelope already has one for that cycle, the more recent edit wins.
          final allocations = await txn.query(
            'allocations',
            where: 'envelope_id = ? AND deleted_at IS NULL',
            whereArgs: [oldId],
          );
          for (final a in allocations) {
            final clash = await txn.query(
              'allocations',
              where: 'envelope_id = ? AND cycle_start = ? AND deleted_at IS NULL',
              whereArgs: [fixedId, a['cycle_start']],
            );
            if (clash.isNotEmpty) {
              final legacyIsNewer = DateTime.parse(
                a['updated_at'] as String,
              ).isAfter(DateTime.parse(clash.first['updated_at'] as String));
              final loser = legacyIsNewer ? clash.first['id'] : a['id'];
              await txn.update(
                'allocations',
                {'deleted_at': stamp, 'updated_at': stamp, 'synced_at': null},
                where: 'id = ?',
                whereArgs: [loser],
              );
              if (!legacyIsNewer) continue;
            }
            await txn.update(
              'allocations',
              {'envelope_id': fixedId, 'updated_at': stamp, 'synced_at': null},
              where: 'id = ?',
              whereArgs: [a['id']],
            );
          }

          await txn.update(
            'spendings',
            {'envelope_id': fixedId, 'updated_at': stamp, 'synced_at': null},
            where: 'envelope_id = ? AND deleted_at IS NULL',
            whereArgs: [oldId],
          );

          await txn.update(
            'envelopes',
            {'deleted_at': stamp, 'updated_at': stamp, 'synced_at': null},
            where: 'id = ?',
            whereArgs: [oldId],
          );
        }
      }
    });
  }
}
