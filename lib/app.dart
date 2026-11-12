import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'providers/bills_controller.dart';
import 'providers/budget_controller.dart';
import 'providers/sync_controller.dart';
import 'screens/shell.dart';
import 'services/bill_scanner.dart';
import 'services/reminder_coordinator.dart';

class BayarApp extends StatefulWidget {
  const BayarApp({
    super.key,
    required this.billsController,
    required this.budgetController,
    required this.syncController,
    required this.reminders,
    required this.selectedTab,
    this.scanner,
  });

  final BillsController billsController;
  final BudgetController budgetController;
  final SyncController syncController;
  final ReminderCoordinator reminders;

  /// Reads photographed bills. Tests pass a fake; the real app uses on-device ML Kit.
  final BillScanner? scanner;

  /// Which tab is showing. Lives here so a tapped reminder can switch to Bills.
  final ValueNotifier<int> selectedTab;

  @override
  State<BayarApp> createState() => _BayarAppState();
}

class _BayarAppState extends State<BayarApp> with WidgetsBindingObserver {
  final BillScanner _defaultScanner = MlKitBillScanner();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app: the date may have changed overnight, and the user
  /// may have switched notifications on or off in Settings. Reload both.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.reminders.refreshPermission();
      widget.billsController.load(); // also reloads the budget, through its onLoaded hook
      widget.syncController.requestSync(immediately: true); // pick up changes from other phones
    }
  }

  @override
  Widget build(BuildContext context) {
    // Providers sit above MaterialApp so every screen, including ones pushed
    // later with Navigator, can find them.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BillsController>.value(value: widget.billsController),
        ChangeNotifierProvider<BudgetController>.value(value: widget.budgetController),
        ChangeNotifierProvider<SyncController>.value(value: widget.syncController),
        ChangeNotifierProvider<ReminderCoordinator>.value(value: widget.reminders),
        Provider<BillScanner>.value(value: widget.scanner ?? _defaultScanner),
      ],
      child: MaterialApp(
        title: 'Bayar',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AppShell(selectedTab: widget.selectedTab),
      ),
    );
  }
}
