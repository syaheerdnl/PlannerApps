import 'package:bayar/core/dates.dart';
import 'package:bayar/core/theme.dart';
import 'package:bayar/screens/envelopes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;

  // "Today" is Thu 12 Nov 2026. Fuel has RM 132.00 left, Food RM 278.50, Other RM 340.00.
  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async => env = await TestEnv.create(planSetUp: true));
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

  /// Opens the sheet from the Nth envelope card (0 = Fuel, 1 = Food, 2 = Other).
  Future<void> openSheetFrom(WidgetTester tester, int card) async {
    await tester.tap(find.text('Add spending').at(card));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amount')), findsOneWidget);
  }

  /// Taps keypad keys, e.g. press(tester, '1 2 . 5'). Only matches the keypad's 22 pt digits.
  Future<void> press(WidgetTester tester, String keys) async {
    for (final k in keys.split(' ')) {
      final finder = k == 'del'
          ? find.byIcon(Icons.backspace_outlined)
          : find.byWidgetPredicate((w) => w is Text && w.data == k && w.style?.fontSize == 22);
      await tester.tap(finder);
      await tester.pump();
    }
  }

  String shownAmount(WidgetTester tester) => (tester.widget(find.byKey(const ValueKey('amount'))) as Text).data!;

  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  testWidgets('opens on the envelope whose button you pressed, with nothing typed', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 1); // Food

    expect(shownAmount(tester), '0');
    expect(find.text('Enter an amount'), findsOneWidget);
    await press(tester, '5');
    expect(find.text('Save to Food'), findsOneWidget);
  });

  testWidgets('typing builds the amount and previews what will be left', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0); // Fuel

    await press(tester, '1 2 . 5');

    expect(shownAmount(tester), '12.5');
    expect(find.text('Fuel will have RM 119.50 left.'), findsOneWidget); // 132.00 - 12.50
    expect(find.text('Save to Fuel'), findsOneWidget);
  });

  testWidgets('delete takes back the last key', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0);

    await press(tester, '1 2 del');
    expect(shownAmount(tester), '1');
    await press(tester, 'del del');
    expect(shownAmount(tester), '0');
  });

  testWidgets('saving records the spending against today and tells you what is left', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0);
    await press(tester, '1 2 . 5');

    await tester.tap(find.text('Save to Fuel'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('amount')), findsNothing); // the sheet closed
    expect(find.text('Fuel: RM 119.50 left.'), findsOneWidget);
    final fuel = env.budget.envelopeViews.first;
    expect(fuel.leftSen, 13200 - 1250);
    expect(fuel.spendings.first.amountSen, 1250);
    expect(fuel.spendings.first.spentOn, dateOf(2026, 11, 12));
    expect(fuel.spendings.first.note, isNull);
    expect(find.text('RM 119.50'), findsOneWidget); // the card behind updated too
  });

  testWidgets('you can switch envelope inside the sheet', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0);
    await press(tester, '5');

    await tester.tap(inSheet(find.text('Other')));
    await tester.pump();
    expect(find.text('Other will have RM 335.00 left.'), findsOneWidget);
    expect(find.text('Save to Other'), findsOneWidget);
  });

  testWidgets('"Yesterday" dates the spending a day earlier', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 1);
    await press(tester, '9');
    await tester.tap(find.text('Yesterday'));
    await tester.pump();

    await tester.tap(find.text('Save to Food'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    final newest = env.budget.envelopeViews[1].spendings.first; // sorted newest first, but today has Lunch
    expect(
      env.budget.envelopeViews[1].spendings.any((s) => s.amountSen == 900 && s.spentOn == dateOf(2026, 11, 11)),
      isTrue,
    );
    expect(newest, isNotNull);
  });

  testWidgets('recent notes are offered as one-tap chips', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0); // Fuel's only note so far is "Petrol"

    await tester.tap(find.widgetWithText(ActionChip, 'Petrol'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Petrol'), findsOneWidget);

    await press(tester, '4 0');
    await tester.tap(find.text('Save to Fuel'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(env.budget.envelopeViews.first.spendings.first.note, 'Petrol');
  });

  testWidgets('a typed note is saved', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 2);
    await tester.enterText(find.byType(TextField), 'Movie');
    await press(tester, '2 5');

    await tester.tap(find.text('Save to Other'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(env.budget.envelopeViews[2].spendings.first.note, 'Movie');
  });

  testWidgets('spending more than is left warns, offers "Save anyway", and still saves', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0); // Fuel has RM 132.00
    await press(tester, '2 0 0');

    expect(find.text('This is RM 68.00 over your Fuel envelope.'), findsOneWidget);
    expect(find.text('Save anyway'), findsOneWidget);

    await tester.tap(find.text('Save anyway'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Fuel is over budget by RM 68.00.'), findsOneWidget);
    expect(env.budget.envelopeViews.first.leftSen, -6800);
  });

  testWidgets('the button stays disabled until an amount is typed', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0);

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enter an amount'));
    expect(button.onPressed, isNull);

    await press(tester, '0'); // zero is still no amount
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('close leaves everything unchanged', (tester) async {
    await boot(tester);
    await openSheetFrom(tester, 0);
    await press(tester, '9 9');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('amount')), findsNothing);
    expect(env.budget.envelopeViews.first.leftSen, 13200);
  });

  testWidgets('two sheets in a row both work', (tester) async {
    await boot(tester);

    for (final keys in ['1', '2']) {
      await openSheetFrom(tester, 1);
      await press(tester, keys);
      await tester.tap(find.text('Save to Food'));
      await settle(tester);
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.pumpAndSettle();
    }

    expect(env.budget.envelopeViews[1].leftSen, 27850 - 100 - 200);
  });
}
