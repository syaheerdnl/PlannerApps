import 'package:bayar/screens/bills_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_scheduler.dart';
import 'support/test_env.dart';

void main() {
  late TestEnv env;

  Future<void> boot(WidgetTester tester, {required FakeScheduler scheduler}) async {
    await tester.runAsync(() async => env = await TestEnv.create(scheduler: scheduler));
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(env.providers(const MaterialApp(home: Scaffold(body: BillsScreen()))));
  }

  testWidgets('no card when notifications are already allowed', (tester) async {
    await boot(tester, scheduler: FakeScheduler());

    expect(find.text('Get reminders'), findsNothing);
    expect(find.text('Allow notifications'), findsNothing);
    expect(find.text('Reminders are off'), findsNothing);
  });

  testWidgets('asks first, then the card disappears once allowed and reminders are scheduled', (tester) async {
    await boot(tester, scheduler: FakeScheduler(permissionGranted: false));

    expect(find.text('Get reminders'), findsOneWidget);
    expect(env.scheduler.scheduled, isEmpty);

    await tester.tap(find.text('Allow notifications'));
    await settle(tester);

    expect(find.text('Get reminders'), findsNothing);
    expect(env.scheduler.permissionRequests, 1);
    expect(env.scheduler.scheduled, isNotEmpty);
  });

  testWidgets('if the user refuses, the card explains how to turn it on and offers no button', (tester) async {
    await boot(tester, scheduler: FakeScheduler(permissionGranted: false, grantOnRequest: false));

    await tester.tap(find.text('Allow notifications'));
    await settle(tester);

    expect(find.text('Reminders are off'), findsOneWidget);
    expect(find.textContaining('phone Settings'), findsOneWidget);
    expect(find.text('Allow notifications'), findsNothing);
    expect(env.scheduler.scheduled, isEmpty);
  });
}
