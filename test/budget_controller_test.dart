import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/providers/budget_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

EnvelopeView view(BudgetController c, String name) => c.envelopeViews.firstWhere((v) => v.envelope.name == name);

String idOf(BudgetController c, String name) => c.envelopes.firstWhere((e) => e.name == name).id;

void main() {
  // Today is Thu 12 Nov 2026: day 19 of the cycle 25 Oct .. 24 Nov, 13 days left.
  group('after setting up', () {
    late TestEnv env;
    late BudgetController c;

    setUp(() async {
      env = await TestEnv.create(planSetUp: true);
      c = env.budget;
    });
    tearDown(() => env.dispose());

    test('payday, cycle and days left', () {
      expect(c.isSetUp, isTrue);
      expect(c.plan!.paydayDay, 25);
      expect(c.cycle!.start, dateOf(2026, 10, 25));
      expect(c.cycle!.end, dateOf(2026, 11, 24));
      expect(c.daysLeft, 13);
      expect(c.nextPayday, dateOf(2026, 11, 25));
    });

    test('what is left in each envelope', () {
      expect(view(c, 'Fuel').leftSen, 13200);
      expect(view(c, 'Food').leftSen, 27850);
      expect(view(c, 'Other').leftSen, 34000);
      expect(c.leftToSpendSen, 75050);
    });

    test('the safe amount per day is split over the days left', () {
      expect(view(c, 'Fuel').dailySafeSen, 1015); // 13200 / 13
      expect(view(c, 'Food').dailySafeSen, 2142); // 27850 / 13
      expect(view(c, 'Other').dailySafeSen, 2615); // 34000 / 13
      expect(c.dailySafeSen, 1015 + 2142 + 2615);
    });

    test('pace compares the bar with the calendar', () {
      expect(view(c, 'Fuel').pace, Pace.onTrack);
      expect(view(c, 'Food').pace, Pace.onTrack);
      expect(view(c, 'Other').pace, Pace.underPace);
    });

    test('adding spending lowers what is left and tells listeners', () async {
      var calls = 0;
      c.addListener(() => calls++);

      final ok = await c.addSpending(
        envelopeId: idOf(c, 'Food'),
        amountSen: 1250,
        spentOn: dateOf(2026, 11, 12),
        note: 'Coffee',
      );

      expect(ok, isTrue);
      expect(view(c, 'Food').leftSen, 27850 - 1250);
      expect(c.leftToSpendSen, 75050 - 1250);
      expect(calls, greaterThan(0));
    });

    test('overspending makes left negative and the pace "over"', () async {
      await c.addSpending(envelopeId: idOf(c, 'Fuel'), amountSen: 20000, spentOn: dateOf(2026, 11, 12));

      expect(view(c, 'Fuel').leftSen, 13200 - 20000);
      expect(view(c, 'Fuel').pace, Pace.over);
      expect(view(c, 'Fuel').dailySafeSen, 0);
    });

    test('spending dated in an earlier cycle is not counted now', () async {
      await c.addSpending(envelopeId: idOf(c, 'Food'), amountSen: 5000, spentOn: dateOf(2026, 10, 20));
      expect(view(c, 'Food').leftSen, 27850);
    });

    test('deleting a spending gives the money back', () async {
      final lunch = view(c, 'Food').spendings.first; // newest: Lunch, today
      expect(lunch.note, 'Lunch');

      await c.deleteSpending(lunch.id);

      expect(view(c, 'Food').leftSen, 27850 + 1200);
    });

    test('recent notes are distinct, newest first', () {
      expect(c.recentNotes(idOf(c, 'Food')), ['Lunch', 'Groceries', 'Dinner']);
      expect(c.recentNotes(idOf(c, 'Fuel')), ['Petrol']);
    });

    group('planning', () {
      test('this cycle: salary minus bills minus envelopes', () {
        expect(c.salarySen, 380000);
        expect(c.billsReservedSen, 106400); // all six bills due 25 Oct..24 Nov, paid or not
        expect(c.allocatedSen, 150000);
        expect(c.unassignedSen, 380000 - 106400 - 150000);
      });

      test('next cycle: different bills, plan carried over', () {
        c.setPlanningNext(true);

        expect(c.planCycle!.start, dateOf(2026, 11, 25));
        expect(c.billsReservedSen, 91400); // Streaming, Internet, Phone, Car loan, TNB
        expect(c.planRows.map((r) => r.budgetSen), [30000, 70000, 50000]); // inherited
        expect(c.unassignedSen, 380000 - 91400 - 150000);
      });

      test('changing the next cycle leaves this cycle alone', () async {
        c.setPlanningNext(true);
        await c.setBudget(idOf(c, 'Food'), 80000);

        expect(c.planRows.firstWhere((r) => r.envelope.name == 'Food').budgetSen, 80000);
        c.setPlanningNext(false);
        expect(c.planRows.firstWhere((r) => r.envelope.name == 'Food').budgetSen, 70000);
        expect(view(c, 'Food').budgetSen, 70000);
      });

      test('a change to this cycle also carries into the next one', () async {
        await c.setBudget(idOf(c, 'Fuel'), 35000);

        expect(view(c, 'Fuel').budgetSen, 35000);
        c.setPlanningNext(true);
        expect(c.planRows.firstWhere((r) => r.envelope.name == 'Fuel').budgetSen, 35000);
      });

      test('a negative budget is stored as zero', () async {
        await c.setBudget(idOf(c, 'Other'), -500);
        expect(view(c, 'Other').budgetSen, 0);
        expect(view(c, 'Other').pace, Pace.none);
      });

      test('paying a bill does not change what is reserved, but adding one does', () async {
        final reservedBefore = c.billsReservedSen;
        final phone = env.controller.all.firstWhere((i) => i.occurrence.obligation.name == 'Phone plan');

        await env.controller.markPaid(phone);
        expect(c.billsReservedSen, reservedBefore);

        await env.controller.createBill(
          name: 'Water',
          amountSen: 3000,
          isEstimate: false,
          frequency: Frequency.monthly,
          intervalCount: 1,
          startDate: dateOf(2026, 11, 20),
          payByBufferDays: 0,
        );
        expect(c.billsReservedSen, reservedBefore + 3000);
      });
    });

    test('changing payday moves the cycle', () async {
      await c.savePlan(paydayDay: 1, salarySen: 400000);

      expect(c.cycle!.start, dateOf(2026, 11, 1));
      expect(c.cycle!.end, dateOf(2026, 11, 30));
      expect(c.daysLeft, 19);
      expect(c.salarySen, 400000);
    });

    group('envelopes', () {
      test('add, rename and delete', () async {
        expect(await c.addEnvelope('Savings'), isTrue);
        expect(c.envelopes.map((e) => e.name), ['Fuel', 'Food', 'Other', 'Savings']);

        expect(await c.renameEnvelope(idOf(c, 'Savings'), 'Rainy day'), isTrue);
        expect(c.envelopes.last.name, 'Rainy day');

        expect(await c.deleteEnvelope(idOf(c, 'Rainy day')), isTrue);
        expect(c.envelopes.map((e) => e.name), ['Fuel', 'Food', 'Other']);
      });

      test('a duplicate name fails with a message and changes nothing', () async {
        expect(await c.addEnvelope('food'), isFalse);
        expect(c.errorMessage, 'Could not add that envelope.');
        expect(c.envelopes, hasLength(3));
      });

      test('deleting an envelope removes its money from the totals', () async {
        await c.deleteEnvelope(idOf(c, 'Food'));
        expect(c.leftToSpendSen, 13200 + 34000);
        expect(c.allocatedSen, 30000 + 50000);
      });
    });
  });

  group('before setting up', () {
    late TestEnv env;

    setUp(() async => env = await TestEnv.create());
    tearDown(() => env.dispose());

    test('nothing is calculated, but the default envelopes exist', () {
      final c = env.budget;
      expect(c.isSetUp, isFalse);
      expect(c.cycle, isNull);
      expect(c.envelopeViews, isEmpty);
      expect(c.leftToSpendSen, 0);
      expect(c.daysLeft, 0);
      expect(c.envelopes.map((e) => e.name), ['Fuel', 'Food', 'Other']);
      expect(c.isLoading, isFalse);
    });

    test('saving payday and salary sets everything up', () async {
      expect(await env.budget.savePlan(paydayDay: 25, salarySen: 380000), isTrue);

      expect(env.budget.isSetUp, isTrue);
      expect(env.budget.cycle!.start, dateOf(2026, 10, 25));
      expect(env.budget.billsReservedSen, 106400);
      expect(env.budget.unassignedSen, 380000 - 106400); // nothing allocated yet
    });

    test('an invalid payday is refused', () async {
      expect(await env.budget.savePlan(paydayDay: 40, salarySen: 100), isFalse);
      expect(env.budget.errorMessage, 'Could not save your salary.');
      expect(env.budget.isSetUp, isFalse);
    });

    test('budgets cannot be set before the cycle exists', () async {
      expect(await env.budget.setBudget(env.budget.envelopes.first.id, 1000), isFalse);
    });
  });
}
