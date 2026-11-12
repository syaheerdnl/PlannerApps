import 'package:bayar/core/theme.dart';
import 'package:bayar/screens/plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;

  // "Today" is Thu 12 Nov 2026, in the cycle 25 Oct .. 24 Nov.
  Future<void> boot(WidgetTester tester, {bool planSetUp = true}) async {
    await tester.runAsync(() async => env = await TestEnv.create(planSetUp: planSetUp));
    await tester.binding.setSurfaceSize(const Size(400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      env.providers(
        MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: PlanScreen()),
        ),
      ),
    );
  }

  Finder budgetOf(String name) => find.byKey(ValueKey('budget-$name'));

  group('first-time setup', () {
    testWidgets('asks for salary and payday', (tester) async {
      await boot(tester, planSetUp: false);

      expect(find.text('Set up your salary'), findsOneWidget);
      expect(find.text('Monthly take-home salary'), findsOneWidget);
      expect(find.text('Payday is on day'), findsOneWidget);
      expect(find.text('25'), findsOneWidget); // the default payday
      expect(find.text('Every month, on the 25th.'), findsOneWidget);
    });

    testWidgets('an empty or zero salary is rejected', (tester) async {
      await boot(tester, planSetUp: false);

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter an amount like 3800 or 3800.50'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('The salary must be more than 0'), findsOneWidget);
      expect(env.budget.isSetUp, isFalse);
    });

    testWidgets('the payday stepper moves, and explains short months', (tester) async {
      await boot(tester, planSetUp: false);

      await tester.tap(find.byTooltip('Later payday'));
      await tester.pump();
      expect(find.text('26'), findsOneWidget);
      expect(find.text('Every month, on the 26th.'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Later payday'));
      }
      await tester.pump();
      expect(find.text('29'), findsOneWidget);
      expect(find.text('In shorter months it falls on the last day of the month.'), findsOneWidget);

      await tester.tap(find.byTooltip('Earlier payday'));
      await tester.pump();
      expect(find.text('28'), findsOneWidget);
    });

    testWidgets('saving sets up the plan and shows the cycle', (tester) async {
      await boot(tester, planSetUp: false);

      await tester.enterText(find.byType(TextFormField), '3,800');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(env.budget.isSetUp, isTrue);
      expect(find.text('Pay cycle 25 Oct to 24 Nov · 31 days'), findsOneWidget);
      expect(find.text('RM 3,800.00'), findsOneWidget);
      expect(find.text('RM 1,064.00'), findsOneWidget); // all six bills due in the cycle
      // Nothing is allocated yet, so 3,800 - 1,064 is unassigned.
      expect(find.text('RM 2,736.00 is not assigned yet.'), findsOneWidget);
    });
  });

  group('planning', () {
    testWidgets('shows the cycle, the salary and each envelope budget', (tester) async {
      await boot(tester);

      expect(find.text('Pay cycle 25 Oct to 24 Nov · 31 days'), findsOneWidget);
      expect(find.text('Salary arrived Sun 25 Oct'), findsOneWidget);
      expect(find.text('Bills and subscriptions'), findsOneWidget);
      expect(budgetOf('Fuel'), findsOneWidget);
      expect(find.descendant(of: budgetOf('Fuel'), matching: find.byType(Text)), findsNothing); // it IS the Text
      expect((tester.widget(budgetOf('Fuel')) as Text).data, '300');
      expect((tester.widget(budgetOf('Food')) as Text).data, '700');
      expect((tester.widget(budgetOf('Other')) as Text).data, '500');
      // 3800 - 1064 - 1500 = 1236
      expect(find.text('RM 1,236.00 is not assigned yet.'), findsOneWidget);
    });

    testWidgets('+ and - move a budget by RM 50 and update what is unassigned', (tester) async {
      await boot(tester);

      await tester.tap(find.byTooltip('Increase Fuel by RM 50'));
      await settle(tester);
      expect((tester.widget(budgetOf('Fuel')) as Text).data, '350');
      expect(find.text('RM 1,186.00 is not assigned yet.'), findsOneWidget);

      await tester.tap(find.byTooltip('Decrease Fuel by RM 50'));
      await tester.tap(find.byTooltip('Decrease Fuel by RM 50'));
      await settle(tester);
      expect((tester.widget(budgetOf('Fuel')) as Text).data, '250');
    });

    testWidgets('a budget cannot go below zero', (tester) async {
      await boot(tester);
      await tester.runAsync(() => env.budget.setBudget(env.budget.envelopes.first.id, 0));
      await settle(tester);

      final minus = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove).first);
      expect(minus.onPressed, isNull);
    });

    testWidgets('tapping an amount lets you type an exact budget', (tester) async {
      await boot(tester);

      await tester.tap(budgetOf('Fuel'));
      await tester.pumpAndSettle();
      expect(find.text('Fuel budget'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1250.50');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(
        (tester.widget(budgetOf('Fuel')) as Text).data,
        '1,250',
      ); // shown without cents (cents are kept, just not displayed)
      expect(env.budget.planRows.first.budgetSen, 125050);
    });

    testWidgets('"Give the rest to..." puts all unassigned money into one envelope', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Give RM 1,236.00 to...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(find.text('Every ringgit has a job.'), findsOneWidget);
      expect(env.budget.unassignedSen, 0);
      expect(env.budget.planRows.last.budgetSen, 50000 + 123600);
      expect(find.textContaining('Give RM'), findsNothing); // nothing left to give
    });

    testWidgets('giving out more than the salary is called out', (tester) async {
      await boot(tester);

      await tester.tap(budgetOf('Food'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '5000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      // 3800 - 1064 - (300 + 5000 + 500) = -3064
      expect(find.text('You have given out RM 3,064.00 more than your salary.'), findsOneWidget);
    });

    testWidgets('the next cycle has its own bills and carries the plan over', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Next cycle'));
      await tester.pumpAndSettle();

      expect(find.text('Pay cycle 25 Nov to 24 Dec · 30 days'), findsOneWidget);
      expect(find.text('Salary arrives Wed 25 Nov'), findsOneWidget);
      expect(find.text('RM 914.00'), findsOneWidget); // bills in the next cycle
      expect((tester.widget(budgetOf('Fuel')) as Text).data, '300'); // inherited
    });

    testWidgets('changing the next cycle does not touch this one', (tester) async {
      await boot(tester);
      await tester.tap(find.text('Next cycle'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Increase Food by RM 50'));
      await settle(tester);
      expect((tester.widget(budgetOf('Food')) as Text).data, '750');

      await tester.tap(find.text('This cycle'));
      await tester.pumpAndSettle();
      expect((tester.widget(budgetOf('Food')) as Text).data, '700');
    });
  });

  group('envelopes', () {
    testWidgets('add an envelope', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Add envelope'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Savings');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(budgetOf('Savings'), findsOneWidget);
      expect((tester.widget(budgetOf('Savings')) as Text).data, '0');
      expect(find.text('Savings added. Give it a budget above.'), findsOneWidget);
    });

    testWidgets('a duplicate name is refused with a message', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Add envelope'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'food');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not add "food"'), findsOneWidget);
      expect(env.budget.envelopes, hasLength(3));
    });

    testWidgets('rename an envelope', (tester) async {
      await boot(tester);

      await tester.tap(find.byTooltip('Options for Fuel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Petrol');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(budgetOf('Petrol'), findsOneWidget);
      expect(budgetOf('Fuel'), findsNothing);
      expect(find.text('Renamed to Petrol.'), findsOneWidget);
    });

    testWidgets('delete an envelope after confirming', (tester) async {
      await boot(tester);

      await tester.tap(find.byTooltip('Options for Other'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Other?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(budgetOf('Other'), findsNothing);
      expect(find.text('Other deleted.'), findsOneWidget);
    });

    testWidgets('cancelling a delete keeps the envelope', (tester) async {
      await boot(tester);

      await tester.tap(find.byTooltip('Options for Other'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(budgetOf('Other'), findsOneWidget);
    });
  });

  group('changing salary and payday', () {
    testWidgets('the form opens filled in, and cancel goes back', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Change salary or payday'));
      await tester.pumpAndSettle();
      expect(find.text('Salary and payday'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '3,800.00'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Pay cycle 25 Oct to 24 Nov · 31 days'), findsOneWidget);
    });

    testWidgets('saving a new payday moves the cycle', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Change salary or payday'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 24; i++) {
        await tester.tap(find.byTooltip('Earlier payday')); // 25 -> 1
      }
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(); // let the dialog close
      await settle(tester); // then the database work it triggered
      await tester.pumpAndSettle();

      expect(find.text('Pay cycle 1 Nov to 30 Nov · 30 days'), findsOneWidget);
    });
  });
}
