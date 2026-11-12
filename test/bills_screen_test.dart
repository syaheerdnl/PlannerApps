import 'package:bayar/screens/bills_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

Widget host(TestEnv env) => env.providers(const MaterialApp(home: Scaffold(body: BillsScreen())));

void main() {
  late TestEnv env;

  setUp(() {}); // each test creates its own env inside runAsync

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async => env = await TestEnv.create());
    await tester.binding.setSurfaceSize(const Size(400, 1400)); // tall enough for the list
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(env));
  }

  testWidgets('shows the summary and the upcoming bills', (tester) async {
    await boot(tester);

    expect(find.text('Due in the next month'), findsOneWidget);
    expect(find.text('RM 914.00'), findsOneWidget);
    expect(find.text('Phone plan'), findsWidgets);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('Mark paid'), findsWidgets);
    // Paid bills are not in the Upcoming list.
    expect(find.text('Insurance'), findsNothing);
  });

  testWidgets('status lines and tags are worded for the date', (tester) async {
    await boot(tester);

    // Phone plan's pay-by date (11 Nov) has passed, so only the due date shows.
    expect(find.text('Due Thu 12 Nov'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Due Tue 17 Nov, pay by Sun 15 Nov'), findsOneWidget);
    expect(find.text('Time to pay'), findsNothing); // 15 Nov has not arrived yet
    expect(find.text('Due Sun 22 Nov, pay by Fri 20 Nov, estimate'), findsOneWidget);
    expect(find.text('~RM 180.00'), findsWidgets);
  });

  testWidgets('the day before: "pay by today" and a "Due tomorrow" tag', (tester) async {
    await tester.runAsync(() async => env = await TestEnv.create(today: DateTime.utc(2026, 11, 11)));
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(env));

    expect(find.text('Due Thu 12 Nov, pay by today'), findsOneWidget);
    expect(find.text('Due tomorrow'), findsOneWidget);
  });

  testWidgets('overdue bills are called out', (tester) async {
    await tester.runAsync(() async => env = await TestEnv.create(today: DateTime.utc(2026, 11, 20)));
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(env));

    expect(find.text('Overdue by 8 days'), findsOneWidget); // phone, due 12 Nov
    expect(find.text('Overdue by 3 days'), findsOneWidget); // car loan, due 17 Nov
    expect(find.text('2 overdue. Pay those first.'), findsOneWidget);
  });

  testWidgets('Paid and All switch the list', (tester) async {
    await boot(tester);

    await tester.tap(find.text('Paid'));
    await tester.pump();
    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('Car loan'), findsNothing);
    expect(find.text('Undo'), findsNWidgets(3));

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Car loan'), findsOneWidget);
  });

  testWidgets('Mark paid updates the total and offers Undo', (tester) async {
    await boot(tester);

    // First "Mark paid" button belongs to the Phone plan due on 12 Nov.
    await tester.tap(find.text('Mark paid').first);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400)); // let the snackbar animate in

    expect(find.text('RM 846.00'), findsOneWidget); // 914.00 - 68.00
    expect(find.textContaining('Phone plan marked paid'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.text('RM 914.00'), findsOneWidget);
  });

  testWidgets('an empty database shows a friendly message', (tester) async {
    await tester.runAsync(() async => env = await TestEnv.create(seed: false));
    await tester.pumpWidget(host(env));

    expect(find.textContaining('No bills yet'), findsOneWidget);
    expect(find.text('RM 0.00'), findsOneWidget);
  });
}
