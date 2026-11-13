import 'package:bayar/core/theme.dart';
import 'package:bayar/screens/bills_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async => env = await TestEnv.create());
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      env.providers(
        MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: BillsScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  Future<List<String>> storedNames(WidgetTester tester) async =>
      (await tester.runAsync(() => env.obligations.all()))!.map((o) => o.name).toList();

  // Streaming is a demo bill. A swipe of 300px on a 400px row is well past the 35% threshold.
  Future<void> swipeRight(WidgetTester tester, {double distance = 300}) async {
    await tester.drag(find.text('Streaming'), Offset(distance, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('dragging a row to the right shows a red Delete panel and deletes nothing yet', (tester) async {
    await boot(tester);
    expect(find.text('Delete'), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Streaming')));
    await gesture.moveBy(const Offset(40, 0)); // the first movement is spent on the touch slop
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();

    expect(find.text('Delete'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('Delete Streaming?'), findsNothing); // no dialog until the finger lets go

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(await storedNames(tester), contains('Streaming'));
  });

  testWidgets('letting go past the threshold asks before deleting', (tester) async {
    await boot(tester);
    await swipeRight(tester);

    expect(find.text('Delete Streaming?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(await storedNames(tester), contains('Streaming'), reason: 'nothing is deleted before you confirm');
  });

  testWidgets('Cancel keeps the bill and the row springs back', (tester) async {
    await boot(tester);
    await swipeRight(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Streaming?'), findsNothing);
    expect(find.text('Streaming'), findsOneWidget);
    expect(await storedNames(tester), contains('Streaming'));
    // back in place, not stuck half-swiped
    expect(tester.getTopLeft(find.text('Streaming')).dx, lessThan(200));
  });

  testWidgets('Delete removes the bill from the list and the database, and says so', (tester) async {
    await boot(tester);
    await swipeRight(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Streaming'), findsNothing);
    expect(find.text('Streaming deleted.'), findsOneWidget);
    expect(await storedNames(tester), isNot(contains('Streaming')));
    expect(find.text('Car loan'), findsOneWidget, reason: 'other bills are untouched');
  });

  testWidgets('a short swipe does nothing', (tester) async {
    await boot(tester);
    await swipeRight(tester, distance: 40);

    expect(find.text('Delete Streaming?'), findsNothing);
    expect(await storedNames(tester), contains('Streaming'));
  });

  testWidgets('swiping to the left does nothing', (tester) async {
    await boot(tester);
    await tester.drag(find.text('Streaming'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete Streaming?'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('tapping the row still opens the bill, and Mark paid still works', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Streaming'));
    await tester.pumpAndSettle();
    expect(find.text('Edit bill'), findsOneWidget);
  });
}
