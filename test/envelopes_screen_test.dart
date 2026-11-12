import 'package:bayar/core/theme.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/screens/envelopes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;

  // "Today" is Thu 12 Nov 2026: day 19 of 31 in the cycle 25 Oct .. 24 Nov, 13 days left.
  Future<void> boot(WidgetTester tester, {bool planSetUp = true}) async {
    await tester.runAsync(() async => env = await TestEnv.create(planSetUp: planSetUp));
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      env.providers(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: EnvelopesScreen(selectedTab: env.selectedTab)),
        ),
      ),
    );
  }

  group('before setting up', () {
    testWidgets('asks you to set up the salary first', (tester) async {
      await boot(tester, planSetUp: false);

      expect(find.text('Set up your salary first'), findsOneWidget);
      expect(find.text('Fuel'), findsNothing);

      await tester.tap(find.text('Set up salary'));
      await tester.pump();
      expect(env.selectedTab.value, 3);
    });

    testWidgets('after the salary is saved but no budgets exist, it points to Plan', (tester) async {
      await boot(tester, planSetUp: false);
      await tester.runAsync(() => env.budget.savePlan(paydayDay: 25, salarySen: 380000));
      await settle(tester);

      expect(find.text('No budgets yet'), findsOneWidget);
      expect(find.text('No budget set for this cycle'), findsNWidgets(3));

      await tester.tap(find.text('Plan budgets'));
      await tester.pump();
      expect(env.selectedTab.value, 3);
    });
  });

  group('with a budget', () {
    testWidgets('summary line and one card per envelope', (tester) async {
      await boot(tester);

      expect(find.text('RM 750.50 left · 13 days to payday'), findsOneWidget);
      for (final name in ['Fuel', 'Food', 'Other']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('RM 132.00'), findsOneWidget);
      expect(find.text('RM 278.50'), findsOneWidget);
      expect(find.text('RM 340.00'), findsOneWidget);
    });

    testWidgets('each card shows its budget and a safe amount per day', (tester) async {
      await boot(tester);

      expect(find.text('of RM 300.00 · RM 10.15 a day for 13 days'), findsOneWidget);
      expect(find.text('of RM 700.00 · RM 21.42 a day for 13 days'), findsOneWidget);
      expect(find.text('of RM 500.00 · RM 26.15 a day for 13 days'), findsOneWidget);
    });

    testWidgets('pace chips compare each envelope with the calendar', (tester) async {
      await boot(tester);

      expect(find.text('On track'), findsNWidgets(2)); // Fuel and Food
      expect(find.text('Well under'), findsOneWidget); // Other
    });

    testWidgets('history opens and closes', (tester) async {
      await boot(tester);

      expect(find.text('History (2)'), findsOneWidget); // Fuel
      expect(find.text('History (4)'), findsOneWidget); // Food
      expect(find.text('History (3)'), findsOneWidget); // Other

      await tester.tap(find.text('History (2)'));
      await tester.pump();
      expect(find.text('Petrol'), findsNWidgets(2));
      expect(find.text('Mon 9 Nov'), findsOneWidget);
      expect(find.text('Wed 28 Oct'), findsOneWidget);
      expect(find.text('-RM 60.00'), findsOneWidget);
      expect(find.text('-RM 108.00'), findsOneWidget);

      await tester.tap(find.text('Hide history'));
      await tester.pump();
      expect(find.text('Petrol'), findsNothing);
    });

    testWidgets('an empty history says so', (tester) async {
      await boot(tester);
      await tester.runAsync(() => env.budget.deleteEnvelope(env.budget.envelopes.last.id)); // drop Other
      await tester.runAsync(() => env.budget.addEnvelope('Savings'));
      await settle(tester);

      await tester.tap(find.text('History (0)'));
      await tester.pump();
      expect(find.text('Nothing spent yet this cycle.'), findsOneWidget);
    });

    testWidgets('deleting a spending asks first and gives the money back', (tester) async {
      await boot(tester);
      await tester.tap(find.text('History (2)'));
      await tester.pump();

      await tester.tap(find.byTooltip('Delete Petrol, RM 60.00'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this spending?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('RM 192.00'), findsOneWidget); // 132.00 + 60.00
      expect(find.text('Deleted. RM 60.00 is back.'), findsOneWidget);
    });

    testWidgets('cancelling a delete keeps the spending', (tester) async {
      await boot(tester);
      await tester.tap(find.text('History (2)'));
      await tester.pump();

      await tester.tap(find.byTooltip('Delete Petrol, RM 60.00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('RM 132.00'), findsOneWidget);
    });

    testWidgets('overspending turns the card red and says by how much', (tester) async {
      await boot(tester);
      await tester.runAsync(
        () => env.budget.addSpending(
          envelopeId: env.budget.envelopes.first.id,
          amountSen: 20000,
          spentOn: env.budget.today,
        ),
      );
      await settle(tester);

      expect(find.text('-RM 68.00'), findsOneWidget);
      expect(find.text('Over budget'), findsOneWidget);
      expect(find.text('Over by RM 68.00 · budget RM 300.00'), findsOneWidget);
      expect(env.budget.envelopeViews.first.pace, Pace.over);
    });

    testWidgets('an envelope with no budget says so and shows no pace tick', (tester) async {
      await boot(tester);
      await tester.runAsync(() => env.budget.addEnvelope('Savings'));
      await settle(tester);

      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('No budget set for this cycle'), findsOneWidget);
      expect(find.text('No budget'), findsOneWidget); // the chip
    });
  });
}
