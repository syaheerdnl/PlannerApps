import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/providers/bills_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

String label(BillItem i) => '${toIsoDate(i.occurrence.dueDate)} ${i.occurrence.obligation.name}';

BillItem find(BillsController c, String name, String isoDue) =>
    c.all.firstWhere((i) => i.occurrence.obligation.name == name && toIsoDate(i.occurrence.dueDate) == isoDue);

void main() {
  late TestEnv env;

  // "Today" is Thu 12 Nov 2026, so the window is 13 Oct .. 11 Dec (30 days back,
  // and up to the day before 12 Dec ahead).
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  test('load builds the window: upcoming shows unpaid bills, soonest first', () {
    env.controller.setFilter(BillFilter.upcoming);
    expect(env.controller.visible.map(label).toList(), [
      '2026-11-12 Phone plan',
      '2026-11-17 Car loan',
      '2026-11-22 TNB electricity',
      '2026-12-03 Streaming',
      '2026-12-08 Internet',
    ]);
  });

  group('the window ahead ends the day before the same date next month', () {
    test('ordinary month', () => expect(BillsController.lookAheadEnd(dateOf(2026, 11, 12)), dateOf(2026, 12, 11)));
    test(
      'rolls into the next year',
      () => expect(BillsController.lookAheadEnd(dateOf(2026, 12, 15)), dateOf(2027, 1, 14)),
    );
    test('a 31st is clamped to the end of a short month', () {
      expect(BillsController.lookAheadEnd(dateOf(2027, 1, 31)), dateOf(2027, 2, 27));
      expect(BillsController.lookAheadEnd(dateOf(2028, 1, 31)), dateOf(2028, 2, 28)); // leap year
      expect(BillsController.lookAheadEnd(dateOf(2026, 3, 31)), dateOf(2026, 4, 29));
    });

    test('a monthly bill due today is listed once, so the total is not doubled', () async {
      final rent = await TestEnv.create(seed: false);
      addTearDown(rent.dispose);

      await rent.controller.createBill(
        name: 'Rent',
        amountSen: 80000,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 12),
        payByBufferDays: 0,
      );

      expect(rent.controller.all.map(label), ['2026-11-12 Rent']);
      expect(rent.controller.toPaySen, 80000);
    });
  });

  test('paid filter shows paid bills, latest first', () {
    env.controller.setFilter(BillFilter.paid);
    expect(env.controller.visible.map(label).toList(), [
      '2026-11-08 Internet',
      '2026-11-03 Streaming',
      '2026-10-28 Insurance',
    ]);
  });

  test('all filter shows everything in date order', () {
    env.controller.setFilter(BillFilter.all);
    expect(env.controller.visible, hasLength(8));
    expect(label(env.controller.visible.first), '2026-10-28 Insurance');
    expect(label(env.controller.visible.last), '2026-12-08 Internet');
  });

  test('totals', () {
    // 68 + 520 + 180 + 17 + 129 = RM 914.00
    expect(env.controller.toPaySen, 91400);
    // 150 + 17 + 129 = RM 296.00
    expect(env.controller.paidSen, 29600);
    expect(env.controller.overdueCount, 0);
    expect(env.controller.hasBills, isTrue);
  });

  test('markPaid moves the bill to paid and lowers the total', () async {
    final phone = find(env.controller, 'Phone plan', '2026-11-12');

    await env.controller.markPaid(phone);

    env.controller.setFilter(BillFilter.upcoming);
    expect(env.controller.visible.map(label), isNot(contains('2026-11-12 Phone plan')));
    expect(env.controller.toPaySen, 91400 - 6800);
    expect(find(env.controller, 'Phone plan', '2026-11-12').isPaid, isTrue);
  });

  test('undoPaid puts it back', () async {
    final phone = find(env.controller, 'Phone plan', '2026-11-12');
    await env.controller.markPaid(phone);
    await env.controller.undoPaid(find(env.controller, 'Phone plan', '2026-11-12'));

    expect(find(env.controller, 'Phone plan', '2026-11-12').isPaid, isFalse);
    expect(env.controller.toPaySen, 91400);
  });

  test('marking paid twice is harmless', () async {
    final car = find(env.controller, 'Car loan', '2026-11-17');
    await env.controller.markPaid(car);
    await env.controller.markPaid(car);
    expect(env.controller.paidSen, 29600 + 52000);
  });

  test('listeners are told when something changes', () async {
    var calls = 0;
    env.controller.addListener(() => calls++);

    env.controller.setFilter(BillFilter.paid);
    expect(calls, 1);

    env.controller.setFilter(BillFilter.paid); // same value: no notification
    expect(calls, 1);

    await env.controller.markPaid(find(env.controller, 'Car loan', '2026-11-17'));
    expect(calls, greaterThan(1));
  });

  group('later in the month', () {
    test('unpaid bills past their due date are overdue', () async {
      final late = await TestEnv.create(today: dateOf(2026, 11, 20));
      addTearDown(late.dispose);

      // Phone (12 Nov) and Car loan (17 Nov) were never paid.
      expect(late.controller.overdueCount, 2);
    });

    test('overdue bills still show under Upcoming so they are not forgotten', () async {
      final late = await TestEnv.create(today: dateOf(2026, 11, 20));
      addTearDown(late.dispose);

      final names = late.controller.visible.map(label).toList();
      expect(names, containsAll(['2026-11-12 Phone plan', '2026-11-17 Car loan']));
      expect(names.first, '2026-11-12 Phone plan');
    });

    test('anything older than 30 days is out of the window', () async {
      final far = await TestEnv.create(today: dateOf(2026, 12, 30));
      addTearDown(far.dispose);

      expect(far.controller.all.map(label), isNot(contains('2026-11-12 Phone plan')));
    });
  });

  group('editing bills', () {
    test('createBill adds the bill and reloads', () async {
      final created = await env.controller.createBill(
        name: 'Water',
        amountSen: 3550,
        isEstimate: true,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 25),
        payByBufferDays: 1,
      );

      expect(created, isNotNull);
      expect(env.controller.all.map(label), contains('2026-11-25 Water'));
      expect(env.controller.toPaySen, 91400 + 3550);
    });

    test('createBill returns null and reports an error when the input is invalid', () async {
      var notified = 0;
      env.controller.addListener(() => notified++);

      final created = await env.controller.createBill(
        name: '   ',
        amountSen: 100,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 25),
        payByBufferDays: 0,
      );

      expect(created, isNull);
      expect(env.controller.errorMessage, 'Could not save the bill.');
      expect(notified, greaterThan(0));
      expect(env.controller.all, hasLength(8)); // nothing was added
    });

    test('updateBill changes every unpaid occurrence', () async {
      final car = find(env.controller, 'Car loan', '2026-11-17').occurrence.obligation;

      expect(await env.controller.updateBill(car.copyWith(amountSen: 55000)), isTrue);

      expect(find(env.controller, 'Car loan', '2026-11-17').occurrence.amountSen, 55000);
      expect(env.controller.toPaySen, 91400 + 3000);
    });

    test('a payment keeps the amount that was actually paid, even if the bill is edited later', () async {
      final streaming = find(env.controller, 'Streaming', '2026-11-03');
      expect(streaming.isPaid, isTrue);

      await env.controller.updateBill(streaming.occurrence.obligation.copyWith(amountSen: 9900));

      expect(find(env.controller, 'Streaming', '2026-11-03').payment!.amountSen, 1700);
      expect(env.controller.paidSen, 29600); // unchanged
    });

    test('updateBill on a deleted bill fails cleanly', () async {
      final phone = find(env.controller, 'Phone plan', '2026-11-12').occurrence.obligation;
      await env.controller.deleteBill(phone.id);

      expect(await env.controller.updateBill(phone.copyWith(amountSen: 1)), isFalse);
      expect(env.controller.errorMessage, isNotNull);
    });

    test('deleteBill removes all of its occurrences', () async {
      final phone = find(env.controller, 'Phone plan', '2026-11-12').occurrence.obligation;

      expect(await env.controller.deleteBill(phone.id), isTrue);

      expect(env.controller.all.where((i) => i.occurrence.obligation.name == 'Phone plan'), isEmpty);
      expect(env.controller.toPaySen, 91400 - 6800);
    });

    test('deleting a bill also removes its payments from the Paid list', () async {
      final insurance = find(env.controller, 'Insurance', '2026-10-28').occurrence.obligation;
      await env.controller.deleteBill(insurance.id);

      env.controller.setFilter(BillFilter.paid);
      expect(env.controller.visible.map(label), isNot(contains('2026-10-28 Insurance')));
      expect(env.controller.paidSen, 29600 - 15000);
    });
  });

  test('an empty database loads without bills and without error', () async {
    final empty = await TestEnv.create(seed: false);
    addTearDown(empty.dispose);

    expect(empty.controller.hasBills, isFalse);
    expect(empty.controller.visible, isEmpty);
    expect(empty.controller.errorMessage, isNull);
    expect(empty.controller.isLoading, isFalse);
  });
}
