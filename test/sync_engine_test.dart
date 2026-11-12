import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bayar/sync/remote_store.dart';
import 'package:bayar/sync/sync_engine.dart';

import 'support/in_memory_remote.dart';
import 'support/phone.dart';

void main() {
  late InMemoryRemote cloud;
  final phones = <Phone>[];

  Future<Phone> newPhone(String name, {bool firstLaunch = true}) async {
    final p = await Phone.create(name, cloud, firstLaunch: firstLaunch);
    phones.add(p);
    return p;
  }

  setUp(() {
    cloud = InMemoryRemote();
    phones.clear();
  });

  tearDown(() async {
    for (final p in phones) {
      await p.close();
    }
  });

  group('first sync and the steady state', () {
    test('everything on a new phone is uploaded', () async {
      final a = await newPhone('A');
      final rent = await a.addBill('Rent', sen: 80000);
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 80000);
      await a.settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));

      final result = await a.sync();

      expect(result.ok, isTrue, reason: '$result');
      expect(cloud.rows('obligations'), hasLength(1));
      expect(cloud.rows('payments'), hasLength(1));
      expect(cloud.rows('envelopes'), hasLength(3)); // Fuel, Food, Other
      expect(cloud.rows('settings').map((r) => r['key']), containsAll(['payday_day', 'salary_sen']));
    });

    test('pushed rows are marked synced by the push itself, even if the cloud never echoes them back', () async {
      // A cloud whose pull always comes back empty: only the push step can clear the "dirty" mark.
      final silent = _SilentPullRemote();
      final a = await Phone.create('A', silent);
      phones.add(a);
      await a.addBill('Rent');

      await a.sync();
      final second = await a.sync();

      final row = (await a.appDb.db.query('obligations')).single;
      expect(row['synced_at'], row['updated_at']);
      expect(second.pushed, 0, reason: 'the rent bill was sent again');
    });

    test('syncing again with nothing changed does nothing', () async {
      final a = await newPhone('A');
      await a.addBill('Rent');
      await a.sync();

      final second = await a.sync();

      expect(second.pushed, 0);
      expect(second.pulled, 0);
      expect(second.conflicts, 0);
    });

    test('the cloud never receives the sync bookkeeping or the seeding flag', () async {
      final a = await newPhone('A');
      await a.sync();
      await a.sync();

      final keys = cloud.rows('settings').map((r) => r['key']).toList();
      expect(keys.any((k) => (k as String).startsWith('sync_')), isFalse);
      expect(keys, isNot(contains('default_envelopes_created')));
    });

    test('rows carry no local-only columns to the cloud', () async {
      final a = await newPhone('A');
      await a.addBill('Rent');
      await a.sync();

      expect(cloud.rows('obligations').single.containsKey('synced_at'), isFalse);
    });
  });

  group('a row that becomes visible late', () {
    // A row is stamped when it is saved but only visible once its transaction commits. If phone B
    // pulled in between, B's cursor is already past the stamp.
    test('is still picked up, because each pull re-reads a short window before its cursor', () async {
      final a = await newPhone('A');
      await a.addBill('Rent');
      await a.sync();
      final b = await newPhone('B');
      await b.sync(); // B's cursor is now at the newest stamp

      await a.addBill('Late bill');
      await a.sync();
      // ...but pretend its stamp is 10 seconds older than what B has already seen.
      final late = (cloud.rows('obligations')).firstWhere((r) => r['name'] == 'Late bill');
      cloud.restampBehindNewest('obligations', late['id']!, const Duration(seconds: 10));

      await b.sync();
      expect(await b.billNames(), containsAll(['Rent', 'Late bill']));
    });

    test('but only within the window: a row stamped far in the past is not re-read', () async {
      final a = await newPhone('A');
      await a.addBill('Rent');
      await a.sync();
      final b = await newPhone('B');
      await b.sync();

      await a.addBill('Ancient bill');
      await a.sync();
      final old = cloud.rows('obligations').firstWhere((r) => r['name'] == 'Ancient bill');
      cloud.restampBehindNewest('obligations', old['id']!, kPullOverlap + const Duration(minutes: 5));

      await b.sync();
      expect(await b.billNames(), ['Rent']);
    });

    test('re-reading the window changes nothing and counts nothing', () async {
      final a = await newPhone('A');
      await a.addBill('Rent');
      await a.sync();
      await a.sync();
      final again = await a.sync();
      expect(again.pulled, 0);
      expect(again.pushed, 0);
      expect(await a.billNames(), ['Rent']);
    });
  });

  group('two phones', () {
    test('a second phone receives everything', () async {
      final a = await newPhone('A');
      final rent = await a.addBill('Rent', sen: 80000);
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 80000);
      await a.settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      final fuel = (await a.budget.envelopes()).firstWhere((e) => e.name == 'Fuel');
      await a.budget.setAllocation(envelopeId: fuel.id, cycleStart: dateOf(2026, 10, 25), amountSen: 30000);
      await a.budget.addSpending(envelopeId: fuel.id, amountSen: 6000, spentOn: dateOf(2026, 11, 9), note: 'Petrol');
      await a.sync();

      final b = await newPhone('B');
      final result = await b.sync();

      expect(result.ok, isTrue, reason: '$result');
      expect(await b.billNames(), ['Rent']);
      expect(await b.amountOf('Rent'), 80000);
      expect((await b.payments.forObligation(rent.id)), hasLength(1));
      expect(await b.settings.loadPlan(), const PlanSettings(paydayDay: 25, salarySen: 380000));
      expect((await b.budget.allocations()).single.amountSen, 30000);
      expect((await b.budget.spendingsBetween(dateOf(2026, 10, 25), dateOf(2026, 11, 24))).single.note, 'Petrol');
    });

    test('both phones start with the same default envelopes, so syncing does not duplicate them', () async {
      final a = await newPhone('A');
      final b = await newPhone('B'); // also "first launch": it created Fuel/Food/Other on its own
      await a.sync();
      await b.sync();
      await a.sync();

      for (final p in [a, b]) {
        expect((await p.budget.envelopes()).map((e) => e.name), ['Fuel', 'Food', 'Other'], reason: p.name);
      }
      expect((await a.budget.envelopes()).map((e) => e.id), (await b.budget.envelopes()).map((e) => e.id));
    });

    test('a change made on one phone reaches the other', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final rent = await a.addBill('Rent', sen: 80000);
      await a.sync();
      await b.sync();

      a.at(13);
      await a.bills.update(rent.copyWith(amountSen: 85000));
      await a.sync();
      await b.sync();

      expect(await b.amountOf('Rent'), 85000);
    });

    test('a deletion reaches the other phone', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final rent = await a.addBill('Rent');
      await a.sync();
      await b.sync();
      expect(await b.billNames(), ['Rent']);

      a.at(13);
      await a.bills.delete(rent.id);
      await a.sync();
      await b.sync();

      expect(await b.billNames(), isEmpty);
    });

    test('marking a bill paid on one phone shows on the other', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final rent = await a.addBill('Rent');
      await a.sync();
      await b.sync();

      b.at(14);
      await b.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 10000);
      await b.sync();
      await a.sync();

      expect(await a.payments.forObligation(rent.id), hasLength(1));
    });

    test('undoing a payment travels too', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final rent = await a.addBill('Rent');
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 10000);
      await a.sync();
      await b.sync();
      expect(await b.payments.forObligation(rent.id), hasLength(1));

      a.at(15);
      await a.payments.undoPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17));
      await a.sync();
      await b.sync();

      expect(await b.payments.forObligation(rent.id), isEmpty);
    });

    test('deleting an envelope hides its budgets and spending on the other phone too', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final food = (await a.budget.envelopes()).firstWhere((e) => e.name == 'Food');
      await a.budget.setAllocation(envelopeId: food.id, cycleStart: dateOf(2026, 10, 25), amountSen: 70000);
      await a.budget.addSpending(envelopeId: food.id, amountSen: 1200, spentOn: dateOf(2026, 11, 12));
      await a.sync();
      await b.sync();

      a.at(14);
      await a.budget.deleteEnvelope(food.id);
      await a.sync();
      await b.sync();

      expect((await b.budget.envelopes()).map((e) => e.name), ['Fuel', 'Other']);
      expect(await b.budget.allocations(), isEmpty);
      expect(await b.budget.spendingsBetween(dateOf(2026, 10, 25), dateOf(2026, 11, 24)), isEmpty);
    });

    test('salary changes sync', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      await a.settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      await a.sync();
      await b.sync();

      b.at(14);
      await b.settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 400000));
      await b.sync();
      await a.sync();

      expect((await a.settings.loadPlan())!.salarySen, 400000);
    });
  });

  group('conflicts: the same thing changed on two phones', () {
    Future<(Phone, Phone, Obligation)> sharedRent() async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final rent = await a.addBill('Rent', sen: 80000);
      await a.sync();
      await b.sync();
      return (a, b, rent);
    }

    Future<void> converge(List<Phone> ps) async {
      for (var i = 0; i < 2; i++) {
        for (final p in ps) {
          final r = await p.sync();
          expect(r.ok, isTrue, reason: '${p.name}: $r');
        }
      }
    }

    test('the later edit wins on both phones (B is later)', () async {
      final (a, b, rent) = await sharedRent();

      a.at(13, 10);
      await a.bills.update(rent.copyWith(amountSen: 81000));
      b.at(13, 15);
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 82000));

      await converge([a, b]);

      expect(await a.amountOf('Rent'), 82000);
      expect(await b.amountOf('Rent'), 82000);
    });

    test('the later edit wins on both phones (A is later), whatever order they sync in', () async {
      final (a, b, rent) = await sharedRent();

      b.at(13, 10);
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 82000));
      a.at(13, 15);
      await a.bills.update(rent.copyWith(amountSen: 81000));

      await converge([b, a]); // B syncs first this time

      expect(await a.amountOf('Rent'), 81000);
      expect(await b.amountOf('Rent'), 81000);
    });

    test('a later edit beats an earlier deletion', () async {
      final (a, b, rent) = await sharedRent();

      a.at(13, 10);
      await a.bills.delete(rent.id);
      b.at(13, 15);
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 90000));

      await converge([a, b]);

      expect(await a.amountOf('Rent'), 90000);
      expect(await b.amountOf('Rent'), 90000);
    });

    test('a later deletion beats an earlier edit', () async {
      final (a, b, rent) = await sharedRent();

      b.at(13, 10);
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 90000));
      a.at(13, 15);
      await a.bills.delete(rent.id);

      await converge([a, b]);

      expect(await a.billNames(), isEmpty);
      expect(await b.billNames(), isEmpty);
    });

    test('both phones mark the same bill paid offline: exactly one payment survives, everywhere', () async {
      final (a, b, rent) = await sharedRent();
      final due = dateOf(2026, 11, 17);

      a.at(14, 10);
      final fromA = await a.payments.markPaid(obligationId: rent.id, dueDate: due, amountSen: 80000);
      b.at(14, 12);
      final fromB = await b.payments.markPaid(obligationId: rent.id, dueDate: due, amountSen: 80000);
      expect(fromA.id, isNot(fromB.id)); // two different payment records

      await converge([a, b]);

      for (final p in [a, b]) {
        final active = await p.payments.forObligation(rent.id);
        expect(active, hasLength(1), reason: p.name);
        expect(active.single.id, fromA.id, reason: '${p.name}: the earlier payment wins');
        // The other one is kept, but retired.
        final all = await p.appDb.db.query('payments');
        expect(all, hasLength(2), reason: p.name);
        expect(all.where((r) => r['deleted_at'] != null), hasLength(1), reason: p.name);
      }
      expect(cloud.rows('payments').where((r) => r['deleted_at'] == null), hasLength(1));
    });

    test('both phones set the budget for the same envelope and cycle: the later one wins', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      await a.sync();
      await b.sync();
      final food = (await a.budget.envelopes()).firstWhere((e) => e.name == 'Food');
      final cycle = dateOf(2026, 10, 25);

      a.at(14, 10);
      await a.budget.setAllocation(envelopeId: food.id, cycleStart: cycle, amountSen: 60000);
      b.at(14, 15);
      await b.budget.setAllocation(envelopeId: food.id, cycleStart: cycle, amountSen: 75000);

      await converge([a, b]);

      for (final p in [a, b]) {
        final rows = await p.budget.allocations();
        expect(rows, hasLength(1), reason: p.name);
        expect(rows.single.amountSen, 75000, reason: p.name);
      }
    });

    test('three phones all end up identical', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final c = await newPhone('C');
      a.at(12, 9);
      final rent = await a.addBill('Rent', sen: 80000);
      await a.addBill('Phone', sen: 6800);
      await converge([a, b, c]);

      b.at(13, 9);
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 85000));
      c.at(13, 12);
      await c.addBill('Water', sen: 3000);
      a.at(13, 15);
      await a.bills.delete((await a.bills.all()).firstWhere((x) => x.name == 'Phone').id);

      await converge([c, a, b]);
      await converge([b, c, a]);

      for (final p in [a, b, c]) {
        expect(await p.billNames(), ['Rent', 'Water'], reason: p.name);
        expect(await p.amountOf('Rent'), 85000, reason: p.name);
      }
    });
  });

  group('failures', () {
    test('no connection: the sync reports it, nothing is lost, and it works later', () async {
      final a = await newPhone('A');
      await a.addBill('Rent');
      cloud.offline = true;

      final failed = await a.sync();

      expect(failed.ok, isFalse);
      expect(failed.error, contains('No connection'));
      expect(await a.billNames(), ['Rent']);

      cloud.offline = false;
      final ok = await a.sync();
      expect(ok.ok, isTrue);
      expect(cloud.rows('obligations'), hasLength(1));
    });

    test('a failure half way through leaves the rest to be sent next time, with no duplicates', () async {
      final a = await newPhone('A');
      final rent = await a.addBill('Rent');
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 10000);
      cloud.failOnPushNumber = 2; // obligations go up, then the upload fails

      final failed = await a.sync();
      expect(failed.ok, isFalse);
      expect(cloud.rows('obligations'), hasLength(1));

      cloud.failOnPushNumber = null;
      final ok = await a.sync();
      expect(ok.ok, isTrue, reason: '$ok');
      expect(cloud.rows('obligations'), hasLength(1));
      expect(cloud.rows('payments'), hasLength(1));
    });

    test('a phone that cannot reach the cloud keeps its own edits and merges them later', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      final rent = await a.addBill('Rent', sen: 80000);
      await a.sync();
      await b.sync();

      b.at(13);
      cloud.offline = true;
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 99000));
      expect((await b.sync()).ok, isFalse);
      cloud.offline = false;

      await b.sync();
      await a.sync();

      expect(await a.amountOf('Rent'), 99000);
    });

    test('a row whose parent has not arrived yet is retried, not lost', () async {
      final a = await newPhone('A');
      // The cloud already has a payment for a bill this phone has not seen.
      await cloud.push('payments', [
        {
          'id': 'pay-1',
          'obligation_id': 'bill-from-elsewhere',
          'due_date': '2026-11-17',
          'amount_sen': 5000,
          'paid_at': '2026-11-14T09:00:00.000Z',
          'created_at': '2026-11-14T09:00:00.000Z',
          'updated_at': '2026-11-14T09:00:00.000Z',
          'deleted_at': null,
        },
      ]);

      final first = await a.sync();
      expect(first.ok, isTrue, reason: '$first');
      expect(first.deferred, 1);
      expect(await a.activeRows('payments'), 0);

      // The bill shows up in the cloud later.
      await cloud.push('obligations', [
        {
          'id': 'bill-from-elsewhere',
          'name': 'Insurance',
          'amount_sen': 15000,
          'is_estimate': 0,
          'frequency': 'monthly',
          'interval_count': 1,
          'start_date': '2026-11-17',
          'end_date': null,
          'pay_by_buffer_days': 0,
          'note': null,
          'created_at': '2026-11-14T09:00:00.000Z',
          'updated_at': '2026-11-14T09:00:00.000Z',
          'deleted_at': null,
        },
      ]);

      final second = await a.sync();
      expect(second.ok, isTrue, reason: '$second');
      expect(await a.billNames(), ['Insurance']);
      expect(await a.activeRows('payments'), 1);
    });
  });

  group('clocks and formats', () {
    test('a phone with a wrong clock still gets everyone else\'s changes, and shares its own', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      await a.addBill('Rent');
      await a.sync();
      await b.sync(); // B's cursor now sits at "after Rent" on the CLOUD's clock

      // C's clock is years in the past, so its rows look ancient.
      final c = await newPhone('C');
      c.now = DateTime.utc(2020, 1, 1);
      await c.addBill('Old clock bill');
      await c.sync();

      await b.sync();

      expect(await b.billNames(), containsAll(['Rent', 'Old clock bill']));
    });

    test('timestamps from the cloud in Postgres style are stored in the app format', () async {
      final a = await newPhone('A');
      await cloud.push('obligations', [
        {
          'id': 'bill-pg',
          'name': 'Water',
          'amount_sen': 3000,
          'is_estimate': 0,
          'frequency': 'monthly',
          'interval_count': 1,
          'start_date': '2026-11-20',
          'end_date': null,
          'pay_by_buffer_days': 0,
          'note': null,
          'created_at': '2026-11-14T09:00:00.123456+00:00',
          'updated_at': '2026-11-14T17:00:00+08:00',
          'deleted_at': null,
          'user_id': 'some-user', // extra cloud columns are ignored
          'server_updated_at': '2026-11-14T09:00:00Z',
        },
      ]);

      await a.sync();

      final row = (await a.appDb.db.query('obligations')).single;
      expect(row['created_at'], '2026-11-14T09:00:00.123456Z');
      expect(row['updated_at'], '2026-11-14T09:00:00.000Z'); // 17:00 at +08:00 is 09:00 UTC
      expect(row.containsKey('user_id'), isFalse);
      // And the row is not seen as changed locally, so it is not sent straight back.
      expect((await a.sync()).pushed, 0);
    });

    test('equal versions on both sides are not re-sent', () async {
      final a = await newPhone('A');
      final b = await newPhone('B');
      await a.addBill('Rent');
      await a.sync();
      await b.sync();

      expect((await b.sync()).pushed, 0);
      expect((await a.sync()).pushed, 0);
    });
  });
}

/// Accepts uploads like the normal fake cloud, but never returns anything when asked for changes.
class _SilentPullRemote extends InMemoryRemote {
  @override
  Future<List<RemoteRow>> pullChanges(String table, {DateTime? since}) async => const [];
}
