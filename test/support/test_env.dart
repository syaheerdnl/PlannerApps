import 'package:bayar/core/dates.dart';
import 'package:bayar/data/budget_repository.dart';
import 'package:bayar/data/db.dart';
import 'package:bayar/data/obligation_repository.dart';
import 'package:bayar/data/payment_repository.dart';
import 'package:bayar/data/sample_data.dart';
import 'package:bayar/data/settings_repository.dart';
import 'package:bayar/providers/bills_controller.dart';
import 'package:bayar/providers/budget_controller.dart';
import 'package:bayar/providers/sync_controller.dart';
import 'package:bayar/services/reminder_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_cloud.dart';
import 'fake_scheduler.dart';

/// Real SQLite I/O does not finish inside a widget test's fake clock, so give
/// it a little real time, then let the UI catch up.
Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
  // A chain of database calls advances one step per (real wait + pump), so
  // alternate a few times instead of waiting once.
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// A throwaway app backend: empty in-memory SQLite, the real repositories, the
/// real controllers with a fixed "today", and a fake notification scheduler.
/// Tests never depend on the real date or a phone.
class TestEnv {
  TestEnv._(
    this.appDb,
    this.obligations,
    this.payments,
    this.settings,
    this.budgetRepo,
    this.controller,
    this.budget,
    this.reminders,
    this.scheduler,
    this.selectedTab,
    this.cloud,
    this.sync,
  );

  final AppDatabase appDb;
  final ObligationRepository obligations;
  final PaymentRepository payments;
  final SettingsRepository settings;
  final BudgetRepository budgetRepo;
  final BillsController controller;
  final BudgetController budget;
  final ReminderCoordinator reminders;
  final FakeScheduler scheduler;
  final ValueNotifier<int> selectedTab;
  final FakeCloud cloud;
  final SyncController sync;

  /// [today] is a calendar date; the "clock" in tests reads 08:00 that morning.
  /// [seed] adds the six demo bills. [planSetUp] adds the demo salary, envelopes and spending.
  static Future<TestEnv> create({
    DateTime? today,
    bool seed = true,
    bool planSetUp = false,
    bool notificationsAllowed = true,
    FakeScheduler? scheduler,
    FakeCloud? cloud,
  }) async {
    sqfliteFfiInit();
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final obligations = ObligationRepository(appDb.db);
    final payments = PaymentRepository(appDb.db);
    final settings = SettingsRepository(appDb.db);
    final budgetRepo = BudgetRepository(appDb.db, settings);
    if (seed) await seedSampleBills(obligations, payments);
    if (planSetUp) await seedSampleBudget(budgetRepo, settings);

    final fixedToday = today ?? dateOf(2026, 11, 12);
    final fakeScheduler = scheduler ?? FakeScheduler(permissionGranted: notificationsAllowed);
    final selectedTab = ValueNotifier<int>(0);
    final fakeCloud = cloud ?? FakeCloud(configured: false);
    late final SyncController sync;

    final reminders = ReminderCoordinator(
      obligations: obligations,
      payments: payments,
      scheduler: fakeScheduler,
      now: () => DateTime(fixedToday.year, fixedToday.month, fixedToday.day, 8),
      onOpenBills: () => selectedTab.value = 1,
    );
    await reminders.init();

    final budget = BudgetController(
      budget: budgetRepo,
      settings: settings,
      obligations: obligations,
      today: () => fixedToday,
      onChanged: () => sync.requestSync(),
    );
    await budget.load();

    final controller = BillsController(
      obligations: obligations,
      payments: payments,
      today: () => fixedToday,
      onLoaded: () async {
        await reminders.sync();
        await budget.load();
        sync.requestSync();
      },
    );
    sync = SyncController(
      cloud: fakeCloud,
      db: appDb.db,
      debounce: Duration.zero,
      onSynced: () async {
        await controller.load();
        await budget.load();
      },
    );
    await controller.load();

    return TestEnv._(
      appDb,
      obligations,
      payments,
      settings,
      budgetRepo,
      controller,
      budget,
      reminders,
      fakeScheduler,
      selectedTab,
      fakeCloud,
      sync,
    );
  }

  /// Wraps [child] in the same providers the real app uses. Put this ABOVE
  /// MaterialApp: a screen pushed with Navigator can only see providers above it.
  Widget providers(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BillsController>.value(value: controller),
        ChangeNotifierProvider<BudgetController>.value(value: budget),
        ChangeNotifierProvider<ReminderCoordinator>.value(value: reminders),
        ChangeNotifierProvider<SyncController>.value(value: sync),
      ],
      child: child,
    );
  }

  Future<void> dispose() => appDb.close();
}
