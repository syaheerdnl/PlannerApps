import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/budget_controller.dart';
import '../widgets/floating_nav.dart';
import '../widgets/spending_sheet.dart';
import 'bills_screen.dart';
import 'envelopes_screen.dart';
import 'home_screen.dart';
import 'plan_screen.dart';

/// The frame around the four main tabs.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.selectedTab});

  /// The tab showing now. Owned outside this widget so other code (a tapped
  /// reminder, a button on Home) can change it, and the bar and pages follow.
  final ValueNotifier<int> selectedTab;

  static const _items = [
    NavItem('Home', Icons.home_outlined),
    NavItem('Bills', Icons.receipt_long_outlined),
    NavItem('Envelopes', Icons.account_balance_wallet_outlined),
    NavItem('Plan', Icons.bar_chart_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: selectedTab,
      builder: (context, index, _) {
        // Home has a dark teal header under the status bar, so it needs light
        // icons. Every other tab is light, so it needs dark icons.
        final statusBar = index == 0 ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: statusBar.copyWith(statusBarColor: Colors.transparent),
          child: Scaffold(
            // Lets the page paint underneath the floating bar so the blur has
            // something to blur.
            extendBody: true,
            // IndexedStack keeps every tab alive, so scroll position and typed
            // text survive when you switch tabs.
            body: IndexedStack(
              index: index,
              children: [
                HomeScreen(selectedTab: selectedTab),
                const BillsScreen(),
                EnvelopesScreen(selectedTab: selectedTab),
                const PlanScreen(),
              ],
            ),
            // "Add spending" is only useful once there is a budget. It lives on Home
            // only: each envelope card has its own "Add spending" button, and a
            // floating button there would cover the last card's.
            floatingActionButton: (context.watch<BudgetController>().isSetUp && index == 0)
                ? FloatingActionButton(
                    onPressed: () => showSpendingSheet(context),
                    tooltip: 'Add spending',
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.add),
                  )
                : null,
            bottomNavigationBar: FloatingNavBar(
              items: _items,
              currentIndex: index,
              onSelected: (i) => selectedTab.value = i,
            ),
          ),
        );
      },
    );
  }
}
