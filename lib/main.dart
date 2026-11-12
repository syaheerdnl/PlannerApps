import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/budget_repository.dart';
import 'data/db.dart';
import 'data/obligation_repository.dart';
import 'data/payment_repository.dart';
import 'data/sample_data.dart';
import 'data/settings_repository.dart';
import 'providers/bills_controller.dart';
import 'providers/budget_controller.dart';
import 'providers/sync_controller.dart';
import 'services/local_notification_scheduler.dart';
import 'services/reminder_coordinator.dart';
import 'sync/cloud_backend.dart';
import 'sync/supabase_backend.dart';

Future<void> main() async {
  // Needed because we use plugins (SQLite, notifications) before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  final appDb = await AppDatabase.open();
  final obligations = ObligationRepository(appDb.db);
  final payments = PaymentRepository(appDb.db);
  final settings = SettingsRepository(appDb.db);
  final budgetRepo = BudgetRepository(appDb.db, settings);

  // Demo bills in debug builds only. A release install starts empty.
  if (kDebugMode) {
    await seedSampleBills(obligations, payments);
    await seedSampleBudget(budgetRepo, settings);
  }

  final selectedTab = ValueNotifier<int>(0);
  const billsTab = 1;

  final reminders = ReminderCoordinator(
    obligations: obligations,
    payments: payments,
    scheduler: LocalNotificationScheduler(),
    onOpenBills: () => selectedTab.value = billsTab,
  );
  await reminders.init();

  // The cloud is optional: without SUPABASE_URL / SUPABASE_ANON_KEY the app runs
  // fully offline and the Sync screen says so.
  final CloudBackend cloud = CloudConfig.isConfigured ? await SupabaseBackend.connect() : const NoCloud();

  // The three controllers need each other (a change asks sync to run; a sync
  // reloads the screens), so `sync` is created last and referenced lazily.
  late final SyncController sync;

  final budget = BudgetController(
    budget: budgetRepo,
    settings: settings,
    obligations: obligations,
    onChanged: () => sync.requestSync(),
  );
  await budget.load();

  // Every load of the bills (start-up, a payment, an edit, coming back to the
  // app) also refreshes the reminders, and the budget, because the money set
  // aside for bills depends on which bills exist.
  final bills = BillsController(
    obligations: obligations,
    payments: payments,
    onLoaded: () async {
      await reminders.sync();
      await budget.load();
      sync.requestSync();
    },
  );

  sync = SyncController(
    cloud: cloud,
    db: appDb.db,
    onSynced: () async {
      await bills.load();
      await budget.load();
    },
  );
  await bills.load();
  await sync.init();

  runApp(
    BayarApp(
      billsController: bills,
      budgetController: budget,
      syncController: sync,
      reminders: reminders,
      selectedTab: selectedTab,
    ),
  );
}
