import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/domain/reminder_planner.dart';
import 'package:bayar/providers/bills_controller.dart';
import 'package:bayar/services/reminder_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_scheduler.dart';
import 'support/test_env.dart';

BillItem find(BillsController c, String name, String isoDue) =>
    c.all.firstWhere((i) => i.occurrence.obligation.name == name && toIsoDate(i.occurrence.dueDate) == isoDue);

bool has(FakeScheduler s, String title, DateTime at) => s.scheduled.any((r) => r.title == title && r.at == at);

void main() {
  // "Now" is Thu 12 Nov 2026, 08:00. The seeded bills are the same six as the app's demo data.
  group('with notifications allowed', () {
    late TestEnv env;

    setUp(() async => env = await TestEnv.create());
    tearDown(() => env.dispose());

    test('init prepares the scheduler and schedules reminders straight away', () {
      expect(env.scheduler.initialised, isTrue);
      expect(env.reminders.permission, ReminderPermission.granted);
      expect(env.reminders.isOn, isTrue);
      expect(env.scheduler.scheduled, isNotEmpty);
      expect(env.reminders.scheduledCount, env.scheduler.scheduled.length);
    });

    test('schedules the expected reminders for the seeded bills', () {
      // Phone Nov 1 + Car Nov 3 + TNB Nov 3 + Streaming Dec 2 + Internet Dec 2
      // + Phone Dec 3 + Car Dec 3 + TNB Dec 3
      expect(env.scheduler.scheduled, hasLength(20));
      expect(env.scheduler.scheduled.first.title, 'Phone plan is due today');
      expect(env.scheduler.scheduled.first.at, DateTime(2026, 11, 12, 9));
      expect(has(env.scheduler, 'Car loan: pay by tomorrow', DateTime(2026, 11, 14, 9)), isTrue);
      expect(has(env.scheduler, 'Car loan: time to pay', DateTime(2026, 11, 15, 9)), isTrue);
    });

    test('reminders are in time order', () {
      final times = env.scheduler.scheduled.map((r) => r.at).toList();
      expect(times, [...times]..sort());
    });

    test('paid bills get no reminders (Streaming 3 Nov and Internet 8 Nov are paid)', () {
      expect(env.scheduler.scheduled.where((r) => r.title.startsWith('Internet') && r.at.month == 11), isEmpty);
    });

    test('marking a bill paid removes its reminders, and undo brings them back', () async {
      expect(has(env.scheduler, 'Phone plan is due today', DateTime(2026, 11, 12, 9)), isTrue);

      await env.controller.markPaid(find(env.controller, 'Phone plan', '2026-11-12'));
      expect(has(env.scheduler, 'Phone plan is due today', DateTime(2026, 11, 12, 9)), isFalse);
      expect(env.scheduler.scheduled, hasLength(19));

      await env.controller.undoPaid(find(env.controller, 'Phone plan', '2026-11-12'));
      expect(has(env.scheduler, 'Phone plan is due today', DateTime(2026, 11, 12, 9)), isTrue);
      expect(env.scheduler.scheduled, hasLength(20));
    });

    test('adding a bill schedules its reminders', () async {
      await env.controller.createBill(
        name: 'Water',
        amountSen: 3550,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 25),
        payByBufferDays: 0,
      );

      expect(has(env.scheduler, 'Water: pay by tomorrow', DateTime(2026, 11, 24, 9)), isTrue);
      expect(has(env.scheduler, 'Water is due today', DateTime(2026, 11, 25, 9)), isTrue);
    });

    test('editing a bill moves its reminders', () async {
      final car = find(env.controller, 'Car loan', '2026-11-17').occurrence.obligation;
      await env.controller.updateBill(car.copyWith(payByBufferDays: 0));

      // With no buffer the first reminder is the day before the 17th, not the 14th.
      expect(has(env.scheduler, 'Car loan: pay by tomorrow', DateTime(2026, 11, 16, 9)), isTrue);
      expect(has(env.scheduler, 'Car loan: pay by tomorrow', DateTime(2026, 11, 14, 9)), isFalse);
    });

    test('deleting a bill cancels its reminders', () async {
      final car = find(env.controller, 'Car loan', '2026-11-17').occurrence.obligation;
      await env.controller.deleteBill(car.id);

      expect(env.scheduler.scheduled.where((r) => r.title.startsWith('Car loan')), isEmpty);
    });

    test('overlapping syncs run one at a time', () async {
      env.scheduler.replaceDelay = const Duration(milliseconds: 20);
      env.scheduler.maxConcurrentReplaces = 0;

      await Future.wait([env.reminders.sync(), env.reminders.sync(), env.reminders.sync()]);

      expect(env.scheduler.maxConcurrentReplaces, 1);
    });

    test('listeners hear about the new count', () async {
      var calls = 0;
      env.reminders.addListener(() => calls++);

      await env.controller.markPaid(find(env.controller, 'Phone plan', '2026-11-12'));

      expect(calls, greaterThan(0));
      expect(env.reminders.scheduledCount, 19);
    });

    test('sendTest asks the scheduler for a test notification', () async {
      await env.reminders.sendTest();
      expect(env.scheduler.testNotifications, 1);
    });
  });

  group('permission', () {
    test('not allowed yet: nothing is scheduled and the app should ask', () async {
      final env = await TestEnv.create(notificationsAllowed: false);
      addTearDown(env.dispose);

      expect(env.reminders.permission, ReminderPermission.needsAsk);
      expect(env.scheduler.replaceCalls, 0);
      expect(env.scheduler.scheduled, isEmpty);
      expect(env.reminders.scheduledCount, 0);
    });

    test('asking and being allowed turns reminders on', () async {
      final env = await TestEnv.create(notificationsAllowed: false);
      addTearDown(env.dispose);

      await env.reminders.requestPermission();

      expect(env.scheduler.permissionRequests, 1);
      expect(env.reminders.permission, ReminderPermission.granted);
      expect(env.scheduler.scheduled, hasLength(20));
    });

    test('asking and being refused schedules nothing and remembers the refusal', () async {
      final env = await TestEnv.create(scheduler: FakeScheduler(permissionGranted: false, grantOnRequest: false));
      addTearDown(env.dispose);

      await env.reminders.requestPermission();

      expect(env.reminders.permission, ReminderPermission.denied);
      expect(env.scheduler.scheduled, isEmpty);

      // Later edits still do not schedule anything.
      await env.controller.markPaid(find(env.controller, 'Phone plan', '2026-11-12'));
      expect(env.scheduler.replaceCalls, 0);
    });

    test('turning notifications on in Settings later is picked up', () async {
      final env = await TestEnv.create(scheduler: FakeScheduler(permissionGranted: false, grantOnRequest: false));
      addTearDown(env.dispose);
      await env.reminders.requestPermission();
      expect(env.reminders.permission, ReminderPermission.denied);

      env.scheduler.permissionGranted = true; // the user flips the switch in Settings
      await env.reminders.refreshPermission();

      expect(env.reminders.permission, ReminderPermission.granted);
      expect(env.scheduler.scheduled, hasLength(20));
    });

    test('turning notifications off in Settings stops scheduling', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      expect(env.reminders.isOn, isTrue);

      env.scheduler.permissionGranted = false;
      await env.reminders.refreshPermission();
      final callsBefore = env.scheduler.replaceCalls;
      await env.controller.markPaid(find(env.controller, 'Phone plan', '2026-11-12'));

      expect(env.reminders.isOn, isFalse);
      expect(env.scheduler.replaceCalls, callsBefore);
    });
  });

  group('tapping a reminder', () {
    test('a bills payload opens the Bills tab', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      expect(env.selectedTab.value, 0);

      env.scheduler.tapNotification('bills');

      expect(env.selectedTab.value, 1);
    });

    test('other payloads are ignored', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      env.scheduler.tapNotification('something-else');
      env.scheduler.tapNotification(null);

      expect(env.selectedTab.value, 0);
    });

    test('if the app was launched by a reminder it opens on Bills', () async {
      final env = await TestEnv.create(scheduler: FakeScheduler(launchPayloadValue: 'bills'));
      addTearDown(env.dispose);

      expect(env.selectedTab.value, 1);
    });
  });

  group('overdue', () {
    test('an unpaid past bill gets a nudge at the next 9:00', () async {
      // Nov 20, 08:00: Phone (12 Nov) and Car loan (17 Nov) are unpaid and overdue.
      final env = await TestEnv.create(today: dateOf(2026, 11, 20));
      addTearDown(env.dispose);

      final overdue = env.scheduler.scheduled.where((r) => r.kind == ReminderKind.overdue).toList();

      expect(overdue.map((r) => r.title), containsAll(['Phone plan is overdue', 'Car loan is overdue']));
      expect(overdue.every((r) => r.at == DateTime(2026, 11, 20, 9)), isTrue);
    });
  });
}
