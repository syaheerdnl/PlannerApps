import 'package:bayar/app.dart';
import 'package:bayar/widgets/floating_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;

  Future<void> boot(WidgetTester tester, {bool planSetUp = false}) async {
    await tester.runAsync(() async => env = await TestEnv.create(planSetUp: planSetUp));
    await tester.pumpWidget(
      BayarApp(
        billsController: env.controller,
        budgetController: env.budget,
        syncController: env.sync,
        reminders: env.reminders,
        selectedTab: env.selectedTab,
      ),
    );
  }

  testWidgets('shows the floating bar and switches tabs', (tester) async {
    await boot(tester);

    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets);

    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();
    expect(find.text('Due in the next month'), findsOneWidget);

    await tester.tap(find.text('Envelopes'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your salary first'), findsOneWidget);
  });

  testWidgets('tapping a reminder notification opens the Bills tab', (tester) async {
    await boot(tester);
    expect(find.text('Due in the next month'), findsNothing); // starts on Home

    env.scheduler.tapNotification('bills');
    await tester.pumpAndSettle();

    expect(find.text('Due in the next month'), findsOneWidget);
  });

  group('the add-spending button', () {
    testWidgets('is hidden until a salary is set up', (tester) async {
      await boot(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows on Home only', (tester) async {
      await boot(tester, planSetUp: true);
      expect(find.byType(FloatingActionButton), findsOneWidget); // Home

      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.text('Envelopes'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing); // its cards have their own buttons

      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('opens the spending sheet', (tester) async {
      await boot(tester, planSetUp: true);

      await tester.tap(find.byTooltip('Add spending'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('amount')), findsOneWidget);
      expect(find.text('Enter an amount'), findsOneWidget);
    });
  });
}
