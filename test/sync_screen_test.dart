import 'package:bayar/core/theme.dart';
import 'package:bayar/screens/plan_screen.dart';
import 'package:bayar/screens/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud.dart';
import 'support/test_env.dart';

void main() {
  late TestEnv env;

  Future<void> boot(WidgetTester tester, {FakeCloud? cloud, Widget? home}) async {
    await tester.runAsync(() async => env = await TestEnv.create(cloud: cloud, planSetUp: true));
    await tester.binding.setSurfaceSize(const Size(400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(env.providers(MaterialApp(theme: buildTheme(), home: home ?? const SyncScreen())));
  }

  testWidgets('a build with no cloud explains how to turn sync on', (tester) async {
    await boot(tester, cloud: FakeCloud(configured: false));

    expect(find.text('Sync is not set up in this build'), findsOneWidget);
    expect(find.textContaining('supabase/README.md'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('signed out: a wrong password shows a message and stays on the form', (tester) async {
    await boot(tester, cloud: FakeCloud());

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'me@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });

  testWidgets('signing in shows the account and a Sync now button', (tester) async {
    await boot(tester, cloud: FakeCloud());

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'me@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    expect(find.text('Signed in as me@example.com'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(env.cloud.remote.rows('obligations'), isNotEmpty);
  });

  testWidgets('creating an account works from the same form', (tester) async {
    await boot(tester, cloud: FakeCloud());

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'new@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'longenough');
    await tester.tap(find.text('Create account'));
    await settle(tester);

    expect(find.text('Signed in as new@example.com'), findsOneWidget);
  });

  testWidgets('Sync now runs a sync', (tester) async {
    await boot(tester, cloud: FakeCloud(signedIn: true));
    await tester.pump();
    final before = env.cloud.remote.pullCalls;

    await tester.tap(find.text('Sync now'));
    await settle(tester);

    expect(env.cloud.remote.pullCalls, greaterThan(before));
  });

  testWidgets('signing out asks first, and keeps the data', (tester) async {
    await boot(tester, cloud: FakeCloud(signedIn: true));

    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as me@example.com'), findsNothing); // cloud stub has no email until sign-in

    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out').last);
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(env.controller.all, isNotEmpty);
  });

  group('the entry on the Plan tab', () {
    testWidgets('shows the state and opens the sync screen', (tester) async {
      await boot(tester, home: const Scaffold(body: PlanScreen()));

      expect(find.text('Sync across devices'), findsOneWidget);
      expect(find.text('Not set up in this build'), findsOneWidget);

      await tester.tap(find.text('Sync across devices'));
      await tester.pumpAndSettle();
      expect(find.text('Sync is not set up in this build'), findsOneWidget);
    });

    testWidgets('invites you to sign in when a cloud is configured', (tester) async {
      await boot(
        tester,
        cloud: FakeCloud(),
        home: const Scaffold(body: PlanScreen()),
      );
      expect(find.text('Sign in to share data between phones'), findsOneWidget);
    });
  });
}
