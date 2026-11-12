import 'package:bayar/core/dates.dart';
import 'package:bayar/core/theme.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/providers/bills_controller.dart';
import 'package:bayar/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_scheduler.dart';
import 'support/test_env.dart';

void main() {
  late TestEnv env;

  // "Today" is Thu 12 Nov 2026 unless a test says otherwise.
  Future<void> boot(
    WidgetTester tester, {
    DateTime? today,
    bool seed = true,
    bool planSetUp = false,
    FakeScheduler? scheduler,
  }) async {
    await tester.runAsync(
      () async => env = await TestEnv.create(today: today, seed: seed, planSetUp: planSetUp, scheduler: scheduler),
    );
    await tester.binding.setSurfaceSize(const Size(400, 1800)); // tall enough to build the whole list
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      env.providers(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: HomeScreen(selectedTab: env.selectedTab)),
        ),
      ),
    );
  }

  testWidgets('the header shows what is left to pay and what is next', (tester) async {
    await boot(tester);

    expect(find.text('Thu 12 Nov'), findsOneWidget);
    expect(find.text('Still to pay (next month)'), findsOneWidget);
    expect(find.text('RM 914.00'), findsOneWidget);
    expect(find.text('Phone plan is due today'), findsOneWidget);
  });

  // The seeded data has 5 unpaid bills in the window; this adds a 6th so there is more than "Pay next" shows.
  Future<void> addSixthBill(WidgetTester tester) async {
    await tester.runAsync(
      () => env.controller.createBill(
        name: 'Water',
        amountSen: 3000,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 13),
        payByBufferDays: 0,
      ),
    );
    await tester.pump();
  }

  testWidgets('"Pay next" lists the soonest five unpaid bills and points to the rest', (tester) async {
    await boot(tester);
    await addSixthBill(tester);

    expect(find.text('Pay next'), findsOneWidget);
    for (final name in ['Phone plan', 'Water', 'Car loan', 'TNB electricity', 'Streaming']) {
      expect(find.text(name), findsWidgets);
    }
    // 6 unpaid bills exist; only the soonest 5 are shown, so Water (13 Nov) is in and Internet (8 Dec) is out.
    expect(find.text('Mark paid'), findsNWidgets(5));
    expect(find.text('See all 6'), findsOneWidget);
  });

  testWidgets('"Recently paid" shows the latest payments first, each with Undo', (tester) async {
    await boot(tester);

    expect(find.text('Recently paid'), findsOneWidget);
    expect(find.text('Undo'), findsNWidgets(3));
    expect(find.text('Insurance'), findsOneWidget);
    // Internet (paid 8 Nov) sits above Streaming (3 Nov) above Insurance (28 Oct).
    final internetY = tester.getTopLeft(find.text('Due Sun 8 Nov, paid')).dy;
    final streamingY = tester.getTopLeft(find.text('Due Tue 3 Nov, paid')).dy;
    final insuranceY = tester.getTopLeft(find.text('Due Wed 28 Oct, paid')).dy;
    expect(internetY, lessThan(streamingY));
    expect(streamingY, lessThan(insuranceY));
  });

  testWidgets('marking a bill paid here updates the header and the list', (tester) async {
    await boot(tester);

    await tester.tap(find.text('Mark paid').first); // Phone plan, due today
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('RM 846.00'), findsOneWidget); // 914.00 - 68.00
    expect(find.text('Phone plan is due today'), findsNothing);
    expect(find.text('Next: Car loan, Tue 17 Nov'), findsOneWidget);
    expect(find.textContaining('Phone plan marked paid'), findsOneWidget);
    // It moved to "Recently paid".
    expect(find.text('Recently paid'), findsOneWidget);
    expect(find.text('Due Thu 12 Nov, paid'), findsOneWidget);
  });

  testWidgets('tapping a bill opens it for editing', (tester) async {
    await boot(tester);

    await tester.tap(find.text('Car loan'));
    await tester.pumpAndSettle();

    expect(find.text('Edit bill'), findsOneWidget);
  });

  group('quick actions', () {
    testWidgets('Add bill opens the form', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Add bill'));
      await tester.pumpAndSettle();

      expect(find.text('New bill'), findsOneWidget);
    });

    testWidgets('Pay bills jumps to the Bills tab on Upcoming', (tester) async {
      await boot(tester);
      env.controller.setFilter(BillFilter.paid);

      await tester.tap(find.text('Pay bills'));
      await tester.pump();

      expect(env.selectedTab.value, 1);
      expect(env.controller.filter, BillFilter.upcoming);
    });

    testWidgets('Paid jumps to the Bills tab on Paid', (tester) async {
      await boot(tester);

      await tester.tap(find.text('Paid'));
      await tester.pump();

      expect(env.selectedTab.value, 1);
      expect(env.controller.filter, BillFilter.paid);
    });

    testWidgets('"See all" opens the full upcoming list', (tester) async {
      await boot(tester);
      await addSixthBill(tester);

      await tester.tap(find.text('See all 6'));
      await tester.pump();

      expect(env.selectedTab.value, 1);
      expect(env.controller.filter, BillFilter.upcoming);
    });
  });

  group('other states', () {
    testWidgets('overdue bills are called out in the header', (tester) async {
      await boot(tester, today: dateOf(2026, 11, 20));

      expect(find.text('2 overdue. Pay those first.'), findsOneWidget);
      expect(find.text('Phone plan is due today'), findsNothing);
      expect(find.text('Overdue by 8 days'), findsOneWidget);
    });

    testWidgets('the next bill is described by how soon it is', (tester) async {
      await boot(tester, today: dateOf(2026, 11, 16)); // Car loan is due tomorrow
      // Phone plan (12 Nov) is overdue then, so look one step further on:
      await tester.runAsync(() async {
        final phone = env.controller.all.firstWhere((i) => i.occurrence.obligation.name == 'Phone plan');
        await env.controller.markPaid(phone);
      });
      await tester.pump();

      expect(find.text('Car loan is due tomorrow'), findsOneWidget);
    });

    testWidgets('with every bill paid, it says so', (tester) async {
      await boot(tester);

      await tester.runAsync(() async {
        for (final item in List.of(env.controller.all)) {
          if (!item.isPaid) await env.controller.markPaid(item);
        }
      });
      await tester.pump();

      expect(find.text('RM 0.00'), findsOneWidget);
      expect(find.text('Everything is paid. Nice.'), findsOneWidget);
      expect(find.text('Nothing left to pay in the next month.'), findsOneWidget);
    });

    testWidgets('a brand-new install invites you to add the first bill', (tester) async {
      await boot(tester, seed: false);

      expect(find.text('No bills yet'), findsOneWidget);
      expect(find.text('Welcome to Bayar'), findsOneWidget);
      expect(find.text('Recently paid'), findsNothing);

      await tester.tap(find.text('Add your first bill'));
      await tester.pumpAndSettle();
      expect(find.text('New bill'), findsOneWidget);
    });
  });

  group('reminders chip', () {
    testWidgets('says Reminders on when allowed', (tester) async {
      await boot(tester);
      expect(find.text('Reminders on'), findsOneWidget);
    });

    testWidgets('offers to turn them on when not asked yet, and does it', (tester) async {
      await boot(tester, scheduler: FakeScheduler(permissionGranted: false));
      expect(find.text('Turn on reminders'), findsOneWidget);

      await tester.tap(find.text('Turn on reminders'));
      await settle(tester);

      expect(find.text('Reminders on'), findsOneWidget);
      expect(env.scheduler.scheduled, isNotEmpty);
    });

    testWidgets('says Reminders off after a refusal', (tester) async {
      await boot(tester, scheduler: FakeScheduler(permissionGranted: false, grantOnRequest: false));

      await tester.tap(find.text('Turn on reminders'));
      await settle(tester);

      expect(find.text('Reminders off'), findsOneWidget);
    });
  });

  group('with a budget set up', () {
    // Cycle 25 Oct .. 24 Nov, 13 days left: Fuel RM 132.00, Food RM 278.50, Other RM 340.00.
    testWidgets('the header leads with what is left to spend', (tester) async {
      await boot(tester, planSetUp: true);

      expect(find.text('Left to spend'), findsOneWidget);
      expect(find.text('RM 750.50'), findsOneWidget);
      // 10.15 + 21.42 + 26.15 a day, over 13 days.
      expect(find.text('RM 57.72 a day for 13 days · payday Wed 25 Nov'), findsOneWidget);
      expect(find.text('Still to pay (next month)'), findsNothing);
    });

    testWidgets('bills still to pay sit alongside, and open the Bills tab', (tester) async {
      await boot(tester, planSetUp: true);

      expect(find.text('RM 914.00 in bills still to pay'), findsOneWidget);

      await tester.tap(find.text('RM 914.00 in bills still to pay'));
      await tester.pump();
      expect(env.selectedTab.value, 1);
    });

    testWidgets('overdue bills replace that line with a warning', (tester) async {
      await boot(tester, today: dateOf(2026, 11, 20), planSetUp: true);

      expect(find.text('2 overdue. Pay those first.'), findsOneWidget);
    });

    testWidgets('an Envelopes section shows each envelope with what is left', (tester) async {
      await boot(tester, planSetUp: true);

      expect(find.text('Envelopes'), findsOneWidget);
      for (final name in ['Fuel', 'Food', 'Other']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('RM 132.00'), findsOneWidget);
      expect(find.text('RM 278.50'), findsOneWidget);
      expect(find.text('RM 340.00'), findsOneWidget);
      expect(find.text('RM 10.15 a day · of RM 300'), findsOneWidget);
      expect(find.text('Set up your salary'), findsNothing);
    });

    testWidgets('"See all" opens the Envelopes tab', (tester) async {
      await boot(tester, planSetUp: true);

      await tester.tap(find.text('See all'));
      await tester.pump();

      expect(env.selectedTab.value, 2);
    });

    testWidgets('spending somewhere updates Home at once', (tester) async {
      await boot(tester, planSetUp: true);

      await tester.runAsync(
        () => env.budget.addSpending(
          envelopeId: env.budget.envelopes[1].id, // Food
          amountSen: 5000,
          spentOn: env.budget.today,
        ),
      );
      await settle(tester);

      expect(find.text('RM 700.50'), findsOneWidget); // 750.50 - 50.00
      expect(find.text('RM 228.50'), findsOneWidget); // Food
    });

    testWidgets('the bills section still works as before', (tester) async {
      await boot(tester, planSetUp: true);

      expect(find.text('Pay next'), findsOneWidget);
      expect(find.text('Mark paid'), findsWidgets);
    });
  });

  group('without a salary set up', () {
    testWidgets('Home invites you to set it up, and the bills header stays', (tester) async {
      await boot(tester);

      expect(find.text('Set up your salary'), findsOneWidget);
      expect(find.text('Still to pay (next month)'), findsOneWidget);
      expect(find.text('Left to spend'), findsNothing);

      await tester.tap(find.text('Set up salary'));
      await tester.pump();
      expect(env.selectedTab.value, 3);
    });
  });
}
