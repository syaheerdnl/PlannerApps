import 'dart:io';

import 'package:bayar/core/dates.dart';
import 'package:bayar/data/budget_repository.dart';
import 'package:bayar/data/db.dart';
import 'package:bayar/data/obligation_repository.dart';
import 'package:bayar/data/payment_repository.dart';
import 'package:bayar/data/settings_repository.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late SettingsRepository settings;
  late BudgetRepository budget;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 11, 12, 9);
    appDb = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    settings = SettingsRepository(appDb.db, clock: () => now);
    budget = BudgetRepository(appDb.db, settings, clock: () => now);
  });

  tearDown(() => appDb.close());

  group('settings', () {
    test('nothing is set up on a new install', () async {
      expect(await settings.loadPlan(), isNull);
    });

    test('payday and salary are saved and read back', () async {
      await settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      expect(await settings.loadPlan(), const PlanSettings(paydayDay: 25, salarySen: 380000));
    });

    test('saving again overwrites', () async {
      await settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      await settings.savePlan(const PlanSettings(paydayDay: 1, salarySen: 400000));
      expect(await settings.loadPlan(), const PlanSettings(paydayDay: 1, salarySen: 400000));
      expect(await appDb.db.query('settings'), hasLength(2)); // still two keys, not four
    });

    test('invalid values are refused', () {
      expect(() => settings.savePlan(const PlanSettings(paydayDay: 0, salarySen: 1)), throwsArgumentError);
      expect(() => settings.savePlan(const PlanSettings(paydayDay: 32, salarySen: 1)), throwsArgumentError);
      expect(() => settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: -1)), throwsArgumentError);
    });
  });

  group('envelopes', () {
    test('create keeps order and trims the name', () async {
      await budget.createEnvelope('  Fuel ');
      await budget.createEnvelope('Food');

      final list = await budget.envelopes();
      expect(list.map((e) => e.name), ['Fuel', 'Food']);
      expect(list.map((e) => e.sortOrder), [0, 1]);
    });

    test('names must be unique, ignoring case', () async {
      await budget.createEnvelope('Food');
      expect(() => budget.createEnvelope('food'), throwsArgumentError);
      expect(() => budget.createEnvelope('   '), throwsArgumentError);
    });

    test('rename works, and cannot collide with another envelope', () async {
      final fuel = await budget.createEnvelope('Fuel');
      await budget.createEnvelope('Food');

      now = DateTime.utc(2026, 11, 13);
      final renamed = await budget.renameEnvelope(fuel.id, 'Petrol');

      expect(renamed.updatedAt, now);
      expect((await budget.envelopes()).map((e) => e.name), ['Petrol', 'Food']);
      expect(() => budget.renameEnvelope(fuel.id, 'FOOD'), throwsArgumentError);
    });

    test('a name freed by deleting can be used again', () async {
      final food = await budget.createEnvelope('Food');
      await budget.deleteEnvelope(food.id);
      await budget.createEnvelope('Food');
      expect((await budget.envelopes()).map((e) => e.name), ['Food']);
    });

    test('deleting is soft and hides its budgets and spending too', () async {
      final food = await budget.createEnvelope('Food');
      await budget.setAllocation(envelopeId: food.id, cycleStart: dateOf(2026, 10, 25), amountSen: 70000);
      await budget.addSpending(envelopeId: food.id, amountSen: 1200, spentOn: dateOf(2026, 11, 12));

      await budget.deleteEnvelope(food.id);

      expect(await budget.envelopes(), isEmpty);
      expect(await budget.allocations(), isEmpty);
      expect(await budget.spendingsBetween(dateOf(2026, 1, 1), dateOf(2026, 12, 31)), isEmpty);
      expect(await appDb.db.query('envelopes'), hasLength(1)); // the row is still there
      expect((await appDb.db.query('envelopes')).first['deleted_at'], isNotNull);
    });

    test('default envelopes are created once, then never again', () async {
      await budget.createDefaultEnvelopesOnce();
      expect((await budget.envelopes()).map((e) => e.name), ['Fuel', 'Food', 'Other']);

      final food = (await budget.envelopes()).firstWhere((e) => e.name == 'Food');
      await budget.deleteEnvelope(food.id);
      await budget.createDefaultEnvelopesOnce(); // next launch

      expect((await budget.envelopes()).map((e) => e.name), ['Fuel', 'Other']);
    });

    test('defaults are not added on top of envelopes you already made', () async {
      await budget.createEnvelope('Savings');
      await budget.createDefaultEnvelopesOnce();
      expect((await budget.envelopes()).map((e) => e.name), ['Savings']);
    });
  });

  group('allocations', () {
    test('setAllocation inserts, then updates the same row', () async {
      final food = await budget.createEnvelope('Food');
      final cycle = dateOf(2026, 10, 25);

      await budget.setAllocation(envelopeId: food.id, cycleStart: cycle, amountSen: 70000);
      await budget.setAllocation(envelopeId: food.id, cycleStart: cycle, amountSen: 75000);

      final rows = await budget.allocations();
      expect(rows, hasLength(1));
      expect(rows.single.amountSen, 75000);
    });

    test('different cycles keep separate rows, and carry over when read', () async {
      final food = await budget.createEnvelope('Food');
      await budget.setAllocation(envelopeId: food.id, cycleStart: dateOf(2026, 10, 25), amountSen: 70000);
      await budget.setAllocation(envelopeId: food.id, cycleStart: dateOf(2026, 11, 25), amountSen: 80000);

      final all = await budget.allocations();
      expect(all, hasLength(2));
      expect(allocationFor(all, food.id, dateOf(2026, 12, 25)), 80000);
      expect(allocationFor(all, food.id, dateOf(2026, 10, 25)), 70000);
    });

    test('negative amounts and unknown envelopes are refused', () async {
      final food = await budget.createEnvelope('Food');
      expect(
        () => budget.setAllocation(envelopeId: food.id, cycleStart: dateOf(2026, 10, 25), amountSen: -1),
        throwsArgumentError,
      );
      expect(
        () => budget.setAllocation(envelopeId: 'nope', cycleStart: dateOf(2026, 10, 25), amountSen: 100),
        throwsA(anything),
      );
    });
  });

  group('spending', () {
    late Envelope food;
    setUp(() async => food = await budget.createEnvelope('Food'));

    test('add and read back', () async {
      final s = await budget.addSpending(
        envelopeId: food.id,
        amountSen: 1250,
        spentOn: dateOf(2026, 11, 12),
        note: ' Lunch ',
      );

      final list = await budget.spendingsBetween(dateOf(2026, 11, 1), dateOf(2026, 11, 30));
      expect(list, hasLength(1));
      expect(list.single.id, s.id);
      expect(list.single.amountSen, 1250);
      expect(list.single.note, 'Lunch');
      expect(list.single.spentOn, dateOf(2026, 11, 12));
    });

    test('a blank note is stored as no note', () async {
      final s = await budget.addSpending(
        envelopeId: food.id,
        amountSen: 100,
        spentOn: dateOf(2026, 11, 12),
        note: '   ',
      );
      expect(s.note, isNull);
    });

    test('amount must be more than zero', () {
      expect(
        () => budget.addSpending(envelopeId: food.id, amountSen: 0, spentOn: dateOf(2026, 11, 12)),
        throwsArgumentError,
      );
      expect(
        () => budget.addSpending(envelopeId: food.id, amountSen: -5, spentOn: dateOf(2026, 11, 12)),
        throwsArgumentError,
      );
    });

    test('an unknown envelope is refused by the database', () {
      expect(
        () => budget.addSpending(envelopeId: 'nope', amountSen: 100, spentOn: dateOf(2026, 11, 12)),
        throwsA(anything),
      );
    });

    test('the date range includes both ends and nothing outside', () async {
      for (final d in [dateOf(2026, 10, 24), dateOf(2026, 10, 25), dateOf(2026, 11, 24), dateOf(2026, 11, 25)]) {
        await budget.addSpending(envelopeId: food.id, amountSen: 100, spentOn: d);
      }

      final list = await budget.spendingsBetween(dateOf(2026, 10, 25), dateOf(2026, 11, 24));

      expect(list.map((s) => toIsoDate(s.spentOn)), ['2026-11-24', '2026-10-25']); // newest first
    });

    test('deleting a spending hides it but keeps the row', () async {
      final s = await budget.addSpending(envelopeId: food.id, amountSen: 100, spentOn: dateOf(2026, 11, 12));

      await budget.deleteSpending(s.id);

      expect(await budget.spendingsBetween(dateOf(2026, 1, 1), dateOf(2026, 12, 31)), isEmpty);
      expect(await appDb.db.query('spendings'), hasLength(1));
    });
  });

  group('upgrading a phone that has the Phase 1 database', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bayar_migration_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps every bill and payment, and adds the new tables', () async {
      final path = '${dir.path}/old_phone.db';

      // 1. Build exactly what a Phase 1 install has: schema version 1, with data.
      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => AppDatabase.createV1Schema(db),
        ),
      );
      final oldBills = ObligationRepository(v1, clock: () => now);
      final oldPayments = PaymentRepository(v1, clock: () => now);
      final rent = await oldBills.create(
        name: 'Rent',
        amountSen: 80000,
        frequency: Frequency.monthly,
        startDate: dateOf(2026, 11, 12),
      );
      await oldPayments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 12), amountSen: 80000);
      expect((await v1.rawQuery('PRAGMA user_version')).single.values.single, 1);
      await v1.close();

      // 2. The new app opens the same file.
      final upgraded = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      addTearDown(upgraded.close);

      // 3. Old data is intact.
      final bills = await ObligationRepository(upgraded.db).all();
      expect(bills.map((b) => b.name), ['Rent']);
      expect(bills.single.amountSen, 80000);
      final paid = await PaymentRepository(upgraded.db).paidBetween(dateOf(2026, 11, 1), dateOf(2026, 11, 30));
      expect(paid, hasLength(1));

      // 4. The new tables exist, are empty, and work.
      expect((await upgraded.db.rawQuery('PRAGMA user_version')).single.values.single, AppDatabase.schemaVersion);
      final newSettings = SettingsRepository(upgraded.db);
      final newBudget = BudgetRepository(upgraded.db, newSettings);
      expect(await newBudget.envelopes(), isEmpty);
      await newBudget.createDefaultEnvelopesOnce();
      expect(await newBudget.envelopes(), hasLength(3));
      await newSettings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      expect(await newSettings.loadPlan(), isNotNull);
    });

    test('a version 2 database gains settings.synced_at and keeps its settings', () async {
      final path = '${dir.path}/v2_phone.db';
      final v2 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await AppDatabase.createV1Schema(db);
            await AppDatabase.createV2Schema(db);
          },
        ),
      );
      await v2.insert('settings', {'key': 'payday_day', 'value': '25', 'updated_at': '2026-11-01T00:00:00.000Z'});
      expect((await v2.rawQuery('PRAGMA table_info(settings)')).map((c) => c['name']), isNot(contains('synced_at')));
      await v2.close();

      final upgraded = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      addTearDown(upgraded.close);

      final columns = (await upgraded.db.rawQuery('PRAGMA table_info(settings)')).map((c) => c['name']);
      expect(columns, contains('synced_at'));
      final row = (await upgraded.db.query('settings')).single;
      expect(row['value'], '25');
      expect(row['synced_at'], isNull); // so it counts as "not yet synced" and will be uploaded
      expect((await upgraded.db.rawQuery('PRAGMA user_version')).single.values.single, AppDatabase.schemaVersion);
    });

    test('opening an already-upgraded database again changes nothing', () async {
      final path = '${dir.path}/twice.db';
      final first = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      await BudgetRepository(first.db, SettingsRepository(first.db)).createEnvelope('Fuel');
      await first.close();

      final second = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      addTearDown(second.close);

      expect((await BudgetRepository(second.db, SettingsRepository(second.db)).envelopes()).map((e) => e.name), [
        'Fuel',
      ]);
    });

    test('a fresh install gets every table', () async {
      final tables = (await appDb.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((r) => r['name']).toSet();
      expect(tables, containsAll(['obligations', 'payments', 'envelopes', 'allocations', 'spendings', 'settings']));
    });
  });
}
