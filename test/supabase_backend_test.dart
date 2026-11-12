import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/sync/remote_store.dart';
import 'package:bayar/sync/supabase_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase_http.dart';
import 'support/phone.dart';

/// Tests SupabaseBackend with the REAL supabase_flutter client, talking to a
/// fake server that behaves like Supabase (see FakeSupabaseServer). It checks the
/// requests we send, and runs the whole sync engine through it.
void main() {
  late FakeSupabaseServer server;
  final phones = <Phone>[];

  SupabaseBackend newBackend() {
    final client = SupabaseClient(
      'https://fake.supabase.co',
      'anon-key',
      httpClient: server.client,
      // The Flutter app supplies real storage for the PKCE sign-up flow; a plain Dart client needs one here.
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: _MemoryStorage()),
    );
    return SupabaseBackend(client);
  }

  Future<Phone> newPhone(String name, SupabaseBackend backend) async {
    final p = await Phone.create(name, backend);
    phones.add(p);
    return p;
  }

  Map<String, Object?> bill(String id, String name, {String updatedAt = '2026-11-14T09:00:00.000Z', int sen = 1000}) =>
      {
        'id': id,
        'name': name,
        'amount_sen': sen,
        'is_estimate': 0,
        'frequency': 'monthly',
        'interval_count': 1,
        'start_date': '2026-11-20',
        'end_date': null,
        'pay_by_buffer_days': 0,
        'note': null,
        'created_at': '2026-11-14T09:00:00.000Z',
        'updated_at': updatedAt,
        'deleted_at': null,
      };

  setUp(() {
    server = FakeSupabaseServer();
    phones.clear();
  });

  tearDown(() async {
    for (final p in phones) {
      await p.close();
    }
  });

  group('signing in', () {
    test('the right password signs in', () async {
      final backend = newBackend();
      expect(backend.isSignedIn, isFalse);

      await backend.signIn(' me@example.com ', 'secret1'); // surrounding spaces are trimmed

      expect(backend.isSignedIn, isTrue);
      expect(backend.email, 'me@example.com');
    });

    test('the wrong password throws and stays signed out', () async {
      final backend = newBackend();

      await expectLater(backend.signIn('me@example.com', 'wrong'), throwsA(anything));

      expect(backend.isSignedIn, isFalse);
    });

    test('a new account is signed in straight away', () async {
      final backend = newBackend();

      expect(await backend.signUp('new@example.com', 'longenough'), isTrue);

      expect(backend.isSignedIn, isTrue);
      expect(backend.email, 'new@example.com');
    });

    test('if the project needs the email confirmed, sign-up says "not signed in yet"', () async {
      server.requireConfirmation = true;
      final backend = newBackend();

      expect(await backend.signUp('new@example.com', 'longenough'), isFalse);

      expect(backend.isSignedIn, isFalse);
    });

    test('an existing email is refused', () async {
      final backend = newBackend();
      await expectLater(backend.signUp('me@example.com', 'whatever1'), throwsA(anything));
    });

    test('signing out clears the session', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');

      await backend.signOut();

      expect(backend.isSignedIn, isFalse);
    });
  });

  group('the requests it sends', () {
    test('an upload is an upsert on (user_id, id), carries the signed-in user, and sends the user\'s token', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');

      await backend.push('obligations', [bill('b1', 'Rent'), bill('b2', 'Phone')]);

      final post = server.requestsTo('/rest/v1/obligations', method: 'POST').single;
      expect(post.url.queryParameters['on_conflict'], 'user_id,id');
      expect(post.headers['Prefer'], contains('resolution=merge-duplicates'));
      expect(post.headers['apikey'], 'anon-key');
      expect(post.headers['Authorization'], startsWith('Bearer ey'));

      final stored = server.tables['obligations']!.values.toList();
      expect(stored, hasLength(2));
      expect(stored.every((r) => r['user_id'] == server.userIdFor('me@example.com')), isTrue);
    });

    test('settings are upserted on (user_id, key)', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');

      await backend.push('settings', [
        {'key': 'payday_day', 'value': '25', 'updated_at': '2026-11-14T09:00:00.000Z'},
      ]);

      expect(
        server.requestsTo('/rest/v1/settings', method: 'POST').single.url.queryParameters['on_conflict'],
        'user_id,key',
      );
      expect(server.count('settings', server.userIdFor('me@example.com')), 1);
    });

    test('pushing nothing sends nothing', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');
      await backend.push('obligations', const []);
      expect(server.requestsTo('/rest/v1/obligations'), isEmpty);
    });

    test('uploading again with the same id updates the row instead of adding one', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');

      await backend.push('obligations', [bill('b1', 'Rent', sen: 1000)]);
      await backend.push('obligations', [bill('b1', 'Rent', sen: 2000, updatedAt: '2026-11-15T09:00:00.000Z')]);

      final rows = server.tables['obligations']!.values.toList();
      expect(rows, hasLength(1));
      expect(rows.single['amount_sen'], 2000);
    });

    test('a download asks for rows newer than the cursor, oldest first', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');
      await backend.push('obligations', [bill('b1', 'Rent')]);

      await backend.pullChanges('obligations', since: DateTime.utc(2030, 1, 1, 0, 0, 5));

      final get = server.requestsTo('/rest/v1/obligations', method: 'GET').single;
      expect(get.url.queryParameters['server_updated_at'], startsWith('gt.2030-01-01T00:00:05'));
      final order = get.url.queryParameters['order']!;
      expect(order, startsWith('server_updated_at.asc'), reason: 'oldest first, by the cloud\'s clock');
      expect(order, contains('id.asc'), reason: 'ties broken by id so paging is stable');
    });
  });

  group('downloading', () {
    test('rows come back with the cloud\'s own timestamp', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');
      await backend.push('obligations', [bill('b1', 'Rent'), bill('b2', 'Phone')]);

      final rows = await backend.pullChanges('obligations');

      expect(rows, hasLength(2));
      expect(rows.map((r) => r.data['name']), ['Rent', 'Phone']);
      expect(rows.first.serverUpdatedAt, DateTime.utc(2030, 1, 1, 0, 0, 1));
      expect(rows.last.serverUpdatedAt.isAfter(rows.first.serverUpdatedAt), isTrue);
    });

    test('only rows newer than the cursor are returned', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');
      await backend.push('obligations', [bill('b1', 'Rent')]);
      final first = (await backend.pullChanges('obligations')).single;
      await backend.push('obligations', [bill('b2', 'Phone')]);

      final newer = await backend.pullChanges('obligations', since: first.serverUpdatedAt);

      expect(newer.map((r) => r.data['name']), ['Phone']);
    });

    test('a large table is fetched page by page and nothing is missed or repeated', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');
      final uid = server.userIdFor('me@example.com');
      server.seed('obligations', uid, [
        for (var i = 0; i < 2300; i++) bill('id-${i.toString().padLeft(5, '0')}', 'Bill $i'),
      ]);

      final rows = await backend.pullChanges('obligations');

      expect(rows, hasLength(2300));
      expect(rows.map((r) => r.data['id']).toSet(), hasLength(2300)); // no duplicates
      expect(server.requestsTo('/rest/v1/obligations', method: 'GET'), hasLength(3)); // 1000 + 1000 + 300
      final times = rows.map((r) => r.serverUpdatedAt).toList();
      expect(times, [...times]..sort()); // still in order across pages
    });

    test('a user never sees another user\'s rows', () async {
      final mine = newBackend();
      await mine.signIn('me@example.com', 'secret1');
      await mine.push('obligations', [bill('b1', 'My private bill')]);

      server.users['other@example.com'] = 'pw123456';
      final theirs = newBackend();
      await theirs.signIn('other@example.com', 'pw123456');

      expect(await theirs.pullChanges('obligations'), isEmpty);
      expect(await mine.pullChanges('obligations'), hasLength(1));
    });

    test('without signing in nothing is returned', () async {
      final backend = newBackend();
      expect(await backend.pullChanges('obligations'), isEmpty);
    });
  });

  group('failures', () {
    test('a lost connection surfaces as an error', () async {
      final backend = newBackend();
      await backend.signIn('me@example.com', 'secret1');
      server.offline = true;

      await expectLater(backend.pullChanges('obligations'), throwsA(anything));
      await expectLater(backend.push('obligations', [bill('b1', 'Rent')]), throwsA(anything));
    });
  });

  group('the whole sync engine through the real client', () {
    Future<SupabaseBackend> signedIn(String email) async {
      final backend = newBackend();
      await backend.signIn(email, 'secret1');
      return backend;
    }

    test('every column the app sends exists in the SQL file (the fake server rejects any that does not)', () async {
      final a = await newPhone('A', await signedIn('me@example.com'));
      final rent = await a.addBill('Rent', sen: 80000);
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 80000);
      await a.settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      final fuel = (await a.budget.envelopes()).firstWhere((e) => e.name == 'Fuel');
      await a.budget.setAllocation(envelopeId: fuel.id, cycleStart: dateOf(2026, 10, 25), amountSen: 30000);
      await a.budget.addSpending(envelopeId: fuel.id, amountSen: 6000, spentOn: dateOf(2026, 11, 9), note: 'Petrol');

      final result = await a.sync();

      expect(result.ok, isTrue, reason: '$result');
      final uid = server.userIdFor('me@example.com');
      for (final table in ['obligations', 'payments', 'envelopes', 'allocations', 'spendings']) {
        expect(server.count(table, uid), greaterThan(0), reason: table);
      }
      expect(server.count('envelopes', uid), 3);
      expect(server.count('settings', uid), 2); // payday and salary only, never the sync bookkeeping
    });

    test('a second phone on the same account receives everything', () async {
      final a = await newPhone('A', await signedIn('me@example.com'));
      final rent = await a.addBill('Rent', sen: 80000);
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 80000);
      await a.settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
      final food = (await a.budget.envelopes()).firstWhere((e) => e.name == 'Food');
      await a.budget.setAllocation(envelopeId: food.id, cycleStart: dateOf(2026, 10, 25), amountSen: 70000);
      await a.budget.addSpending(envelopeId: food.id, amountSen: 1200, spentOn: dateOf(2026, 11, 12), note: 'Lunch');
      await a.sync();

      final b = await newPhone('B', await signedIn('me@example.com'));
      final result = await b.sync();

      expect(result.ok, isTrue, reason: '$result');
      expect(await b.billNames(), ['Rent']);
      expect(await b.payments.forObligation(rent.id), hasLength(1));
      expect(await b.settings.loadPlan(), const PlanSettings(paydayDay: 25, salarySen: 380000));
      expect((await b.budget.allocations()).single.amountSen, 70000);
      expect((await b.budget.spendingsBetween(dateOf(2026, 10, 25), dateOf(2026, 11, 24))).single.note, 'Lunch');
      expect((await b.budget.envelopes()).map((e) => e.name), ['Fuel', 'Food', 'Other']); // not duplicated
    });

    test('a later edit on either phone wins, through the real client', () async {
      final a = await newPhone('A', await signedIn('me@example.com'));
      final b = await newPhone('B', await signedIn('me@example.com'));
      final rent = await a.addBill('Rent', sen: 80000);
      await a.sync();
      await b.sync();

      a.at(13, 10);
      await a.bills.update(rent.copyWith(amountSen: 81000));
      b.at(13, 15);
      await b.bills.update((await b.bills.byId(rent.id))!.copyWith(amountSen: 82000));
      for (final p in [a, b, a, b]) {
        expect((await p.sync()).ok, isTrue);
      }

      expect(await a.amountOf('Rent'), 82000);
      expect(await b.amountOf('Rent'), 82000);
      expect(server.count('obligations', server.userIdFor('me@example.com')), 1);
    });

    test('two phones marking the same bill paid end up with one payment', () async {
      final a = await newPhone('A', await signedIn('me@example.com'));
      final b = await newPhone('B', await signedIn('me@example.com'));
      final rent = await a.addBill('Rent');
      await a.sync();
      await b.sync();

      a.at(14, 10);
      await a.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 10000);
      b.at(14, 12);
      await b.payments.markPaid(obligationId: rent.id, dueDate: dateOf(2026, 11, 17), amountSen: 10000);
      for (final p in [a, b, a, b]) {
        expect((await p.sync()).ok, isTrue);
      }

      expect(await a.payments.forObligation(rent.id), hasLength(1));
      expect(await b.payments.forObligation(rent.id), hasLength(1));
    });

    test('two different accounts never see each other\'s data', () async {
      server.users['other@example.com'] = 'secret1';
      final mine = await newPhone('Mine', await signedIn('me@example.com'));
      await mine.addBill('My rent');
      await mine.sync();

      final theirs = await newPhone('Theirs', await signedIn('other@example.com'));
      await theirs.sync();

      expect(await theirs.billNames(), isEmpty);
      // They share the same default envelope ids, yet each account keeps its own rows.
      expect(server.count('envelopes', server.userIdFor('me@example.com')), 3);
      expect(server.count('envelopes', server.userIdFor('other@example.com')), 3);
    });

    test('losing the connection mid-sync keeps the data and the next sync finishes the job', () async {
      final a = await newPhone('A', await signedIn('me@example.com'));
      await a.addBill('Rent');
      server.offline = true;

      final failed = await a.sync();
      expect(failed.ok, isFalse);
      expect(await a.billNames(), ['Rent']);

      server.offline = false;
      expect((await a.sync()).ok, isTrue);
      expect(server.count('obligations', server.userIdFor('me@example.com')), 1);
    });

    test('syncing while signed out uploads nothing', () async {
      final backend = newBackend(); // never signed in
      final a = await newPhone('A', backend);
      await a.addBill('Rent');

      final result = await a.sync();

      // The anonymous key can read nothing and write nothing: the upload is refused.
      expect(result.ok, isFalse);
      expect(server.tables['obligations'] ?? {}, isEmpty);
    });
  });

  test('the cloud settings come from compile-time values, and are empty by default', () {
    expect(CloudConfig.isConfigured, isFalse);
  });

  test('RemoteRow keeps what it was given', () {
    final row = RemoteRow(const {'id': 'x'}, DateTime.utc(2030));
    expect(row.data['id'], 'x');
  });
}

class _MemoryStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
}
