import 'package:bayar/core/theme.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/screens/bills_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;

  // "Today" is Thu 12 Nov 2026, which is the form's default first due date.
  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async => env = await TestEnv.create());
    await tester.binding.setSurfaceSize(const Size(400, 1600)); // tall enough to build every field
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The provider must sit ABOVE MaterialApp, as in the real app. A screen
    // pushed with Navigator is a sibling of the first screen, not its child, so a
    // provider placed inside the first screen would be invisible to it.
    await tester.pumpWidget(
      env.providers(
        MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: BillsScreen()),
        ),
      ),
    );
  }

  Future<void> openNewForm(WidgetTester tester) async {
    await tester.tap(find.text('Add bill'));
    await tester.pumpAndSettle();
  }

  Future<void> openEditForm(WidgetTester tester, String billName) async {
    await tester.tap(find.text(billName));
    await tester.pumpAndSettle();
  }

  Finder fieldWithHint(String hint) => find.widgetWithText(TextFormField, hint, skipOffstage: true);

  testWidgets('the new-bill form starts with monthly from today and a live preview', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    expect(find.text('New bill'), findsOneWidget);
    expect(find.text('First due date'), findsOneWidget);
    expect(find.text('Thu 12 Nov 2026'), findsOneWidget);
    expect(find.textContaining('Due Thu 12 Nov 2026, Sat 12 Dec 2026, Tue 12 Jan 2027'), findsOneWidget);
  });

  testWidgets('the preview follows the schedule you choose', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    // Every 2 months: 12 Nov, 12 Jan, 12 Mar.
    await tester.tap(find.byTooltip('Increase Every'));
    await tester.pump();
    expect(find.text('2 months'), findsOneWidget);
    expect(find.textContaining('Thu 12 Nov 2026, Tue 12 Jan 2027, Fri 12 Mar 2027'), findsOneWidget);

    // Once: a single date, and the repeat controls disappear.
    await tester.tap(find.text('Once'));
    await tester.pump();
    expect(find.text('Due date'), findsOneWidget);
    expect(find.text('Every'), findsNothing);
    expect(find.text('Last due date (optional)'), findsNothing);
    expect(find.text('Due Thu 12 Nov 2026'), findsOneWidget);
  });

  testWidgets('pay-early stepper explains the pay-by date', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    expect(find.text('You will be reminded on the due date.'), findsOneWidget);

    await tester.tap(find.byTooltip('Pay one day earlier'));
    await tester.tap(find.byTooltip('Pay one day earlier'));
    await tester.pump();

    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('Aim to pay by Tue 10 Nov for the first one.'), findsOneWidget);
  });

  testWidgets('saving an empty form shows what is missing and stays open', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add bill'));
    await tester.pump();

    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter an amount like 68 or 68.50'), findsOneWidget);
    expect(find.text('New bill'), findsOneWidget);
  });

  testWidgets('a zero amount is rejected', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    await tester.enterText(fieldWithHint('e.g. Car loan, Netflix, TNB'), 'Water');
    await tester.enterText(fieldWithHint('0.00'), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Add bill'));
    await tester.pump();

    expect(find.text('The amount must be more than 0'), findsOneWidget);
  });

  testWidgets('adding a bill saves it, returns to the list and says when it is next due', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    await tester.enterText(fieldWithHint('e.g. Car loan, Netflix, TNB'), '  Water ');
    await tester.enterText(fieldWithHint('0.00'), '35.50');
    await tester.tap(find.byType(Switch)); // the amount changes each month
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add bill'));
    await settle(tester);
    await tester.pumpAndSettle();

    // Back on the Bills screen, with a message and the new row.
    expect(find.text('New bill'), findsNothing);
    expect(find.text('Water added. Next due Thu 12 Nov.'), findsOneWidget);
    // Monthly from 12 Nov: only 12 Nov is inside the window (it ends 11 Dec).
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('~RM 35.50'), findsOneWidget);

    final saved = await tester.runAsync(() => env.obligations.all());
    final water = saved!.firstWhere((b) => b.name == 'Water');
    expect(water.amountSen, 3550);
    expect(water.isEstimate, isTrue);
    expect(water.frequency, Frequency.monthly);
  });

  testWidgets('tapping a bill opens it filled in; saving updates it', (tester) async {
    await boot(tester);
    await openEditForm(tester, 'Car loan');

    expect(find.text('Edit bill'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Car loan'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '520.00'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget); // its pay-early buffer

    await tester.enterText(find.widgetWithText(TextFormField, '520.00'), '550');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Car loan updated.'), findsOneWidget);
    expect(find.text('RM 550.00'), findsOneWidget);

    final saved = await tester.runAsync(() => env.obligations.all());
    expect(saved!.firstWhere((b) => b.name == 'Car loan').amountSen, 55000);
  });

  testWidgets('deleting asks first, then removes the bill', (tester) async {
    await boot(tester);
    await openEditForm(tester, 'Car loan');

    await tester.tap(find.text('Delete this bill'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Car loan?'), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit bill'), findsOneWidget);

    await tester.tap(find.text('Delete this bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Car loan deleted.'), findsOneWidget);
    expect(find.text('Edit bill'), findsNothing);

    final saved = await tester.runAsync(() => env.obligations.all());
    expect(saved!.map((b) => b.name), isNot(contains('Car loan')));
  });

  testWidgets('the date picker opens, and cancelling leaves the date alone', (tester) async {
    await boot(tester);
    await openNewForm(tester);

    await tester.tap(find.text('Thu 12 Nov 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('Thu 12 Nov 2026'), findsOneWidget);
  });
}
