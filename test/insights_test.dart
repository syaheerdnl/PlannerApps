import 'package:bayar/core/dates.dart';
import 'package:bayar/core/theme.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/domain/insights.dart';
import 'package:bayar/domain/pay_cycle.dart';
import 'package:bayar/screens/envelopes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

final _t = DateTime.utc(2026, 1, 1);

Spending spend(String envelope, DateTime on, int sen) =>
    Spending(id: '$envelope$on$sen', envelopeId: envelope, amountSen: sen, spentOn: on, createdAt: _t, updatedAt: _t);

EnvelopeView view(String id, List<Spending> spendings, PayCycle cycle, DateTime today) => buildEnvelopeView(
  envelope: Envelope(id: id, name: id, sortOrder: 0, createdAt: _t, updatedAt: _t),
  allocations: const [],
  spendings: spendings,
  cycle: cycle,
  today: today,
);

void main() {
  // Day 19 of the cycle 25 Oct .. 24 Nov.
  final today = dateOf(2026, 11, 12);
  final cycle = PayCycle.containing(today, paydayDay: 25);

  group('buildInsights', () {
    test('one slot per day, with money placed on the day it was spent', () {
      final views = [
        view(
          'food',
          [spend('food', dateOf(2026, 10, 25), 1000), spend('food', dateOf(2026, 11, 12), 500)],
          cycle,
          today,
        ),
      ];

      final i = buildInsights(views: views, cycle: cycle, today: today);

      expect(i.dailySen, hasLength(31));
      expect(i.dailySen[0], 1000); // payday
      expect(i.dailySen[18], 500); // today, day 19
      expect(i.dailySen.fold<int>(0, (a, b) => a + b), 1500);
    });

    test('totals, average per day so far, and the biggest day', () {
      final views = [
        view(
          'food',
          [spend('food', dateOf(2026, 10, 30), 9000), spend('food', dateOf(2026, 11, 1), 1000)],
          cycle,
          today,
        ),
        view('fuel', [spend('fuel', dateOf(2026, 10, 30), 3000)], cycle, today),
      ];

      final i = buildInsights(views: views, cycle: cycle, today: today);

      expect(i.totalSpentSen, 13000);
      expect(i.biggestDaySen, 12000); // food 90 + fuel 30 on 30 Oct
      expect(i.averagePerDaySen, (13000 / 19).round());
      expect(i.todayIndex, 18);
      expect(i.bySpentSen, {'food': 10000, 'fuel': 3000});
    });

    test('nothing spent gives zeros, not errors', () {
      final i = buildInsights(views: [view('food', const [], cycle, today)], cycle: cycle, today: today);
      expect(i.totalSpentSen, 0);
      expect(i.averagePerDaySen, 0);
      expect(i.biggestDaySen, 0);
    });

    test('no envelopes at all is fine too', () {
      final i = buildInsights(views: const [], cycle: cycle, today: today);
      expect(i.dailySen, hasLength(31));
      expect(i.totalSpentSen, 0);
    });
  });

  group('on the Envelopes screen', () {
    late TestEnv env;

    Future<void> boot(WidgetTester tester) async {
      await tester.runAsync(() async => env = await TestEnv.create(planSetUp: true));
      await tester.binding.setSurfaceSize(const Size(400, 2600));
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

    testWidgets('shows the total spent, the daily average and one bar per day', (tester) async {
      await boot(tester);

      expect(find.text('Spent this cycle'), findsOneWidget);
      expect(find.text('RM 749.50'), findsOneWidget); // 168 + 421.50 + 160
      expect(find.text('About RM 39.45 a day · biggest day RM 336.70'), findsOneWidget);
      for (var day = 0; day < 31; day++) {
        expect(find.byKey(ValueKey('day-$day')), findsOneWidget, reason: 'day $day');
      }
    });

    testWidgets('a new spending changes the total', (tester) async {
      await boot(tester);
      await tester.runAsync(
        () => env.budget.addSpending(
          envelopeId: env.budget.envelopes.first.id,
          amountSen: 5050,
          spentOn: env.budget.today,
        ),
      );
      await settle(tester);

      expect(find.text('RM 800.00'), findsOneWidget); // 749.50 + 50.50
    });

    testWidgets('with no spending it says so', (tester) async {
      await tester.runAsync(() async => env = await TestEnv.create(planSetUp: false));
      await tester.runAsync(() => env.budget.savePlan(paydayDay: 25, salarySen: 380000));
      await tester.binding.setSurfaceSize(const Size(400, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        env.providers(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(body: EnvelopesScreen(selectedTab: env.selectedTab)),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Nothing spent yet.'), findsOneWidget);
    });
  });
}
