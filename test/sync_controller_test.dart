import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/providers/sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud.dart';
import 'support/in_memory_remote.dart';
import 'support/test_env.dart';

/// Lets debounced work and the real database finish.
Future<void> wait([int ms = 400]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final envs = <TestEnv>[];

  Future<TestEnv> boot({FakeCloud? cloud, bool seed = true, bool planSetUp = false}) async {
    final env = await TestEnv.create(cloud: cloud, seed: seed, planSetUp: planSetUp);
    envs.add(env);
    return env;
  }

  tearDown(() async {
    for (final e in envs) {
      await e.dispose();
    }
    envs.clear();
  });

  group('state', () {
    test('a build without a cloud says so, and never syncs', () async {
      final env = await boot(cloud: FakeCloud(configured: false));
      expect(env.sync.state, SyncState.notConfigured);

      env.sync.requestSync(immediately: true);
      await wait(100);
      expect(env.cloud.remote.pullCalls, 0);
    });

    test('configured but not signed in', () async {
      final env = await boot(cloud: FakeCloud());
      expect(env.sync.state, SyncState.signedOut);
      expect(env.sync.email, isNull);
    });

    test('already signed in at start-up: it catches up at once', () async {
      final env = await boot(cloud: FakeCloud(signedIn: true), planSetUp: true);
      await env.sync.init();
      await wait();

      expect(env.sync.state, SyncState.idle);
      expect(env.cloud.remote.rows('obligations'), isNotEmpty);
      expect(env.sync.lastSynced, isNotNull);
    });
  });

  group('signing in', () {
    test('the right password signs in and starts a sync', () async {
      final env = await boot(cloud: FakeCloud());

      expect(await env.sync.signIn('me@example.com', 'secret1'), isTrue);
      await wait();

      expect(env.sync.state, SyncState.idle);
      expect(env.sync.email, 'me@example.com');
      expect(env.cloud.remote.rows('obligations'), hasLength(6)); // the six demo bills went up
    });

    test('the wrong password is refused with a plain message', () async {
      final env = await boot(cloud: FakeCloud());

      expect(await env.sync.signIn('me@example.com', 'nope'), isFalse);

      expect(env.sync.state, SyncState.signedOut);
      expect(env.sync.message, 'Wrong email or password.');
      expect(env.cloud.remote.pushCalls, 0);
    });

    test('a new account is created and signed in', () async {
      final env = await boot(cloud: FakeCloud());

      expect(await env.sync.signUp('new@example.com', 'longenough'), isTrue);

      expect(env.sync.state, isNot(SyncState.signedOut));
      expect(env.sync.email, 'new@example.com');
    });

    test('an existing email is explained', () async {
      final env = await boot(cloud: FakeCloud());
      expect(await env.sync.signUp('me@example.com', 'whatever1'), isFalse);
      expect(env.sync.message, 'That email already has an account. Try signing in.');
    });

    test('a too-short password is explained', () async {
      final env = await boot(cloud: FakeCloud());
      expect(await env.sync.signUp('x@example.com', '123'), isFalse);
      expect(env.sync.message, 'Use a password of at least 6 characters.');
    });

    test('if the cloud wants the email confirmed first, it says so', () async {
      final cloud = FakeCloud()..requireConfirmation = true;
      final env = await boot(cloud: cloud);

      expect(await env.sync.signUp('new@example.com', 'longenough'), isFalse);

      expect(env.sync.state, SyncState.signedOut);
      expect(env.sync.message, 'Check your email to confirm the account, then sign in.');
    });

    test('signing out stops syncing and keeps the data on the phone', () async {
      final env = await boot(cloud: FakeCloud(signedIn: true));
      await env.sync.init();
      await wait();
      final pushesBefore = env.cloud.remote.pushCalls;

      await env.sync.signOut();
      await env.controller.createBill(
        name: 'Water',
        amountSen: 3000,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 20),
        payByBufferDays: 0,
      );
      await wait();

      expect(env.sync.state, SyncState.signedOut);
      expect(env.cloud.remote.pushCalls, pushesBefore);
      expect(env.controller.all.any((i) => i.occurrence.obligation.name == 'Water'), isTrue);
    });
  });

  group('syncing automatically', () {
    test('adding a bill syncs it', () async {
      final env = await boot(cloud: FakeCloud(signedIn: true), seed: false);
      await env.sync.init();
      await wait();

      await env.controller.createBill(
        name: 'Water',
        amountSen: 3000,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 20),
        payByBufferDays: 0,
      );
      await wait();

      expect(env.cloud.remote.rows('obligations').map((r) => r['name']), ['Water']);
    });

    test('marking a bill paid syncs the payment', () async {
      final env = await boot(cloud: FakeCloud(signedIn: true));
      await env.sync.init();
      await wait();

      await env.controller.markPaid(env.controller.all.firstWhere((i) => !i.isPaid));
      await wait();

      expect(env.cloud.remote.rows('payments').where((r) => r['deleted_at'] == null), hasLength(4)); // 3 seeded + 1
    });

    test('spending money syncs it (budget changes also trigger a sync)', () async {
      final env = await boot(cloud: FakeCloud(signedIn: true), planSetUp: true);
      await env.sync.init();
      await wait();

      await env.budget.addSpending(
        envelopeId: env.budget.envelopes.first.id,
        amountSen: 1250,
        spentOn: dateOf(2026, 11, 12),
        note: 'Coffee',
      );
      await wait();

      expect(env.cloud.remote.rows('spendings').map((r) => r['note']), contains('Coffee'));
    });

    test('many quick changes become one sync', () async {
      final cloud = FakeCloud(signedIn: true);
      final env = await boot(cloud: cloud, seed: false);
      final slow = SyncController(cloud: cloud, db: env.appDb.db, debounce: const Duration(milliseconds: 120));
      addTearDown(slow.dispose);
      await wait(); // let the environment's own start-up sync finish first
      cloud.remote.pullCalls = 0;

      for (var i = 0; i < 6; i++) {
        slow.requestSync();
        await wait(20);
      }
      expect(cloud.remote.pullCalls, 0, reason: 'still waiting for the last change');
      await wait(500);

      expect(cloud.remote.pullCalls, 6, reason: 'one sync = one pull per table');
    });
  });

  group('two phones', () {
    test('a second phone receives the first one\'s data and its screens reload', () async {
      final remote = InMemoryRemote();
      final a = await boot(cloud: FakeCloud(remote: remote, signedIn: true), planSetUp: true);
      await a.sync.init();
      await wait();

      final b = await boot(cloud: FakeCloud(remote: remote), seed: false);
      expect(b.controller.all, isEmpty);
      await b.sync.signIn('me@example.com', 'secret1');
      await wait(600);

      expect(b.controller.all, isNotEmpty); // BillsController reloaded after the sync
      expect(b.budget.isSetUp, isTrue); // so did the budget (salary and payday synced)
      expect(b.budget.leftToSpendSen, a.budget.leftToSpendSen);
    });

    test('reloading the screens after a sync does not trigger another sync (no loop)', () async {
      final remote = InMemoryRemote();
      final a = await boot(cloud: FakeCloud(remote: remote, signedIn: true), planSetUp: true);
      await a.sync.init();
      await wait();

      final b = await boot(cloud: FakeCloud(remote: remote), seed: false);
      await b.sync.signIn('me@example.com', 'secret1');
      await wait(600);

      final calmed = remote.pullCalls;
      await wait(600);
      expect(remote.pullCalls, calmed, reason: 'syncing kept re-triggering itself');
    });
  });

  group('failures', () {
    test('no connection: an error is shown, nothing is lost, and the next change recovers', () async {
      final cloud = FakeCloud(signedIn: true);
      final env = await boot(cloud: cloud, seed: false);
      await env.sync.init();
      await wait();

      cloud.remote.offline = true;
      await env.controller.createBill(
        name: 'Water',
        amountSen: 3000,
        isEstimate: false,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 20),
        payByBufferDays: 0,
      );
      await wait();

      expect(env.sync.state, SyncState.error);
      expect(env.sync.message, contains('safe on this phone'));
      expect(env.controller.all.any((i) => i.occurrence.obligation.name == 'Water'), isTrue);

      cloud.remote.offline = false;
      await env.sync.syncNow();

      expect(env.sync.state, SyncState.idle);
      expect(cloud.remote.rows('obligations').map((r) => r['name']), ['Water']);
    });

    test('asking to sync while one is running runs one more right after, never two at once', () async {
      final cloud = FakeCloud(signedIn: true);
      final env = await boot(cloud: cloud);

      final first = env.sync.syncNow();
      final second = env.sync.syncNow(); // arrives while the first is running
      await Future.wait([first, second]);

      expect(env.sync.state, SyncState.idle);
      expect(cloud.remote.rows('obligations'), hasLength(6));
    });
  });
}
