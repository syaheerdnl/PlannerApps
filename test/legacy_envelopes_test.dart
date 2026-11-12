import 'dart:io';

import 'package:bayar/core/dates.dart';
import 'package:bayar/data/budget_repository.dart';
import 'package:bayar/data/db.dart';
import 'package:bayar/data/settings_repository.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/domain/pay_cycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/in_memory_remote.dart';
import 'support/phone.dart';

String fixed(String name) => BudgetRepository.defaultEnvelopeId(name);

const _t = '2026-11-01T00:00:00.000Z';

Future<void> legacyEnvelope(Database db, String id, String name, int order) => db.insert('envelopes', {
  'id': id,
  'name': name,
  'sort_order': order,
  'created_at': _t,
  'updated_at': _t,
  'deleted_at': null,
  'synced_at': _t, // it had already been synced before
});

Future<void> allocation(
  Database db,
  String id,
  String envelopeId,
  int sen, {
  String cycle = '2026-10-25',
  String at = _t,
}) => db.insert('allocations', {
  'id': id,
  'envelope_id': envelopeId,
  'cycle_start': cycle,
  'amount_sen': sen,
  'created_at': at,
  'updated_at': at,
  'deleted_at': null,
  'synced_at': at,
});

Future<void> spending(Database db, String id, String envelopeId, int sen) => db.insert('spendings', {
  'id': id,
  'envelope_id': envelopeId,
  'amount_sen': sen,
  'note': 'Petrol',
  'spent_on': '2026-11-09',
  'created_at': _t,
  'updated_at': _t,
  'deleted_at': null,
  'synced_at': _t,
});

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bayar_legacy_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A phone that last ran the previous version (database v3), with envelopes
  /// that have random ids.
  Future<AppDatabase> upgradedFromV3(Future<void> Function(Database db) fill) async {
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await AppDatabase.createV1Schema(db);
          await AppDatabase.createV2Schema(db);
          await AppDatabase.createV3Schema(db);
        },
      ),
    );
    await fill(old);
    await old.close();
    final upgraded = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    addTearDown(upgraded.close);
    return upgraded;
  }

  Future<List<Map<String, Object?>>> activeEnvelopes(Database db) =>
      db.query('envelopes', where: 'deleted_at IS NULL', orderBy: 'sort_order');

  group('upgrading a phone whose default envelopes have random ids', () {
    test('they get the fixed ids, and the budget and spending move with them', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await legacyEnvelope(db, 'rand-food', 'Food', 1);
        await legacyEnvelope(db, 'rand-other', 'Other', 2);
        await allocation(db, 'a1', 'rand-fuel', 30000);
        await allocation(db, 'a2', 'rand-food', 70000);
        await spending(db, 's1', 'rand-fuel', 6000);
      });

      final active = await activeEnvelopes(upgraded.db);
      expect(active.map((e) => e['name']), ['Fuel', 'Food', 'Other']);
      expect(active.map((e) => e['id']), [fixed('Fuel'), fixed('Food'), fixed('Other')]);

      expect(
        (await upgraded.db.query('allocations', where: 'id = ?', whereArgs: ['a1'])).single['envelope_id'],
        fixed('Fuel'),
      );
      expect((await upgraded.db.query('spendings')).single['envelope_id'], fixed('Fuel'));
    });

    test('the numbers the user sees do not change', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await allocation(db, 'a1', 'rand-fuel', 30000);
        await spending(db, 's1', 'rand-fuel', 6000);
      });
      final budget = BudgetRepository(upgraded.db, SettingsRepository(upgraded.db));
      final cycle = PayCycle.containing(dateOf(2026, 11, 12), paydayDay: 25);

      final view = buildEnvelopeView(
        envelope: (await budget.envelopes()).firstWhere((e) => e.name == 'Fuel'),
        allocations: await budget.allocations(),
        spendings: await budget.spendingsBetween(cycle.start, cycle.end),
        cycle: cycle,
        today: dateOf(2026, 11, 12),
      );

      expect(view.budgetSen, 30000);
      expect(view.spentSen, 6000);
      expect(view.leftSen, 24000);
    });

    test('the old rows are retired (soft deleted) and everything touched is marked for syncing', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await allocation(db, 'a1', 'rand-fuel', 30000);
        await spending(db, 's1', 'rand-fuel', 6000);
      });

      final old = (await upgraded.db.query('envelopes', where: 'id = ?', whereArgs: ['rand-fuel'])).single;
      expect(old['deleted_at'], isNotNull);
      expect(old['synced_at'], isNull);
      final created = (await upgraded.db.query('envelopes', where: 'id = ?', whereArgs: [fixed('Fuel')])).single;
      expect(created['synced_at'], isNull);
      expect((await upgraded.db.query('allocations')).single['synced_at'], isNull);
      expect((await upgraded.db.query('spendings')).single['synced_at'], isNull);
    });

    test('envelopes the user made themselves are not touched', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await legacyEnvelope(db, 'my-savings', 'Savings', 3);
      });

      final names = (await activeEnvelopes(upgraded.db)).map((e) => '${e['name']}:${e['id']}');
      expect(names, containsAll(['Fuel:${fixed('Fuel')}', 'Savings:my-savings']));
    });

    test('a default the user renamed is left alone', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Petrol', 0); // was Fuel, renamed
      });

      expect((await activeEnvelopes(upgraded.db)).single['id'], 'rand-fuel');
    });

    test('if both versions already have a budget for the same cycle, the more recent one wins', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await db.insert('envelopes', {
          'id': fixed('Fuel'),
          'name': 'Fuel',
          'sort_order': 0,
          'created_at': _t,
          'updated_at': _t,
          'deleted_at': null,
          'synced_at': _t,
        });
        await allocation(db, 'old-one', 'rand-fuel', 30000, at: '2026-11-10T00:00:00.000Z'); // newer
        await allocation(db, 'fixed-one', fixed('Fuel'), 20000, at: '2026-11-05T00:00:00.000Z');
      });

      final active = await upgraded.db.query('allocations', where: 'deleted_at IS NULL');
      expect(active, hasLength(1));
      expect(active.single['amount_sen'], 30000);
      expect(active.single['envelope_id'], fixed('Fuel'));
    });

    test('and the older one wins when it is the fixed envelope\'s', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await db.insert('envelopes', {
          'id': fixed('Fuel'),
          'name': 'Fuel',
          'sort_order': 0,
          'created_at': _t,
          'updated_at': _t,
          'deleted_at': null,
          'synced_at': _t,
        });
        await allocation(db, 'old-one', 'rand-fuel', 30000, at: '2026-11-05T00:00:00.000Z');
        await allocation(db, 'fixed-one', fixed('Fuel'), 20000, at: '2026-11-10T00:00:00.000Z'); // newer
      });

      final active = await upgraded.db.query('allocations', where: 'deleted_at IS NULL');
      expect(active.single['amount_sen'], 20000);
    });

    test('a fixed-id envelope that was deleted on purpose is not brought back', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await db.insert('envelopes', {
          'id': fixed('Fuel'),
          'name': 'Fuel',
          'sort_order': 0,
          'created_at': _t,
          'updated_at': _t,
          'deleted_at': _t,
          'synced_at': _t,
        });
      });

      // Nothing was migrated: the old row is still the live one.
      expect((await activeEnvelopes(upgraded.db)).single['id'], 'rand-fuel');
    });

    test('running it again changes nothing', () async {
      final upgraded = await upgradedFromV3((db) async {
        await legacyEnvelope(db, 'rand-fuel', 'Fuel', 0);
        await spending(db, 's1', 'rand-fuel', 6000);
      });
      final before = await upgraded.db.query('envelopes', orderBy: 'id');

      await AppDatabase.migrateDefaultEnvelopeIds(upgraded.db, now: DateTime.utc(2030));

      expect(await upgraded.db.query('envelopes', orderBy: 'id'), before);
    });

    test('a brand-new install has nothing to migrate', () async {
      final fresh = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      addTearDown(fresh.close);
      await BudgetRepository(fresh.db, SettingsRepository(fresh.db)).createDefaultEnvelopesOnce();

      await AppDatabase.migrateDefaultEnvelopeIds(fresh.db);

      expect((await activeEnvelopes(fresh.db)).map((e) => e['id']), [fixed('Fuel'), fixed('Food'), fixed('Other')]);
      expect(await fresh.db.query('envelopes', where: 'deleted_at IS NOT NULL'), isEmpty);
    });
  });

  group('the scenario from the real devices: an old phone syncing with a new one', () {
    test('without the migration, two Fuel envelopes appear; with it, they merge into one', () async {
      final cloud = InMemoryRemote();
      final phones = <Phone>[];
      addTearDown(() async {
        for (final p in phones) {
          await p.close();
        }
      });

      // Phone A: made before the fix. Its envelopes have random ids, and it has already synced.
      final a = await Phone.create('A', cloud, firstLaunch: false);
      phones.add(a);
      for (final name in BudgetRepository.defaultEnvelopeNames) {
        await a.budget.createEnvelope(name); // random ids, as the old version did
      }
      final oldFuel = (await a.budget.envelopes()).firstWhere((e) => e.name == 'Fuel');
      await a.budget.setAllocation(envelopeId: oldFuel.id, cycleStart: dateOf(2026, 10, 25), amountSen: 30000);
      await a.budget.addSpending(envelopeId: oldFuel.id, amountSen: 6000, spentOn: dateOf(2026, 11, 9), note: 'Petrol');
      await a.sync();

      // Phone B: a new install, with the fixed ids.
      final b = await Phone.create('B', cloud);
      phones.add(b);
      await b.sync();
      await a.sync();

      // The bug: both phones now have two Fuel envelopes.
      expect((await a.budget.envelopes()).where((e) => e.name == 'Fuel'), hasLength(2));

      // Phone A upgrades to the new version (the migration), then everyone syncs.
      await AppDatabase.migrateDefaultEnvelopeIds(a.appDb.db, now: DateTime.utc(2030));
      for (final p in [a, b, a, b]) {
        expect((await p.sync()).ok, isTrue);
      }

      for (final p in [a, b]) {
        final envelopes = await p.budget.envelopes();
        expect(envelopes.map((e) => e.name), ['Fuel', 'Food', 'Other'], reason: p.name);
        expect(envelopes.map((e) => e.id), [fixed('Fuel'), fixed('Food'), fixed('Other')], reason: p.name);
        // The fuel budget and spending followed the merge.
        expect((await p.budget.allocations()).single.amountSen, 30000, reason: p.name);
        final spent = await p.budget.spendingsBetween(dateOf(2026, 10, 25), dateOf(2026, 11, 24));
        expect(spent.single.amountSen, 6000, reason: p.name);
        expect(spent.single.envelopeId, fixed('Fuel'), reason: p.name);
      }
    });
  });
}
