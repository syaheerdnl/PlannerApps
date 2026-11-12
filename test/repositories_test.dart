import 'package:bayar/core/dates.dart';
import 'package:bayar/data/db.dart';
import 'package:bayar/data/obligation_repository.dart';
import 'package:bayar/data/payment_repository.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late ObligationRepository bills;
  late PaymentRepository payments;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 11, 12, 9, 0);
    // ':memory:' = a brand-new empty database for every test, nothing on disk.
    appDb = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    bills = ObligationRepository(appDb.db, clock: () => now);
    payments = PaymentRepository(appDb.db, clock: () => now);
  });

  tearDown(() => appDb.close());

  Future<Obligation> carLoan() => bills.create(
    name: 'Car loan',
    amountSen: 52000,
    frequency: Frequency.monthly,
    startDate: dateOf(2026, 11, 17),
    payByBufferDays: 2,
  );

  group('ObligationRepository', () {
    test('create then read back keeps every field', () async {
      final created = await bills.create(
        name: '  TNB electricity ',
        amountSen: 18000,
        isEstimate: true,
        frequency: Frequency.monthly,
        intervalCount: 1,
        startDate: dateOf(2026, 11, 22),
        endDate: dateOf(2027, 11, 22),
        payByBufferDays: 2,
        note: 'Scan the bill each month',
      );

      final read = await bills.byId(created.id);

      expect(read, isNotNull);
      expect(read!.name, 'TNB electricity'); // trimmed
      expect(read.amountSen, 18000);
      expect(read.isEstimate, isTrue);
      expect(read.frequency, Frequency.monthly);
      expect(read.startDate, dateOf(2026, 11, 22));
      expect(read.endDate, dateOf(2027, 11, 22));
      expect(read.payByBufferDays, 2);
      expect(read.note, 'Scan the bill each month');
      expect(read.createdAt, now);
      expect(read.updatedAt, now);
      expect(read.deletedAt, isNull);
    });

    test('ids are unique UUIDs', () async {
      final a = await carLoan();
      final b = await carLoan();
      expect(a.id, isNot(b.id));
      expect(a.id.length, 36);
    });

    test('all() is sorted by name, ignoring case', () async {
      await bills.create(
        name: 'phone plan',
        amountSen: 6800,
        frequency: Frequency.monthly,
        startDate: dateOf(2026, 11, 12),
      );
      await bills.create(
        name: 'Car loan',
        amountSen: 52000,
        frequency: Frequency.monthly,
        startDate: dateOf(2026, 11, 17),
      );
      await bills.create(
        name: 'Insurance',
        amountSen: 15000,
        frequency: Frequency.yearly,
        startDate: dateOf(2026, 10, 28),
      );

      final names = (await bills.all()).map((b) => b.name).toList();
      expect(names, ['Car loan', 'Insurance', 'phone plan']);
    });

    test('update saves changes and bumps updated_at only', () async {
      final created = await carLoan();
      now = DateTime.utc(2026, 11, 13, 10, 30);

      final updated = await bills.update(created.copyWith(amountSen: 55000, note: 'Rate went up'));
      final read = (await bills.byId(created.id))!;

      expect(read.amountSen, 55000);
      expect(read.note, 'Rate went up');
      expect(read.createdAt, DateTime.utc(2026, 11, 12, 9, 0));
      expect(read.updatedAt, DateTime.utc(2026, 11, 13, 10, 30));
      expect(updated.updatedAt, read.updatedAt);
    });

    test('copyWith can clear a nullable field', () async {
      final created = await bills.create(
        name: 'Loan',
        amountSen: 1000,
        frequency: Frequency.monthly,
        startDate: dateOf(2026, 11, 1),
        endDate: dateOf(2027, 1, 1),
      );
      await bills.update(created.copyWith(endDate: null));
      expect((await bills.byId(created.id))!.endDate, isNull);
    });

    test('delete is soft: hidden from the app but the row remains', () async {
      final created = await carLoan();
      now = DateTime.utc(2026, 11, 14, 8, 0);

      await bills.delete(created.id);

      expect(await bills.byId(created.id), isNull);
      expect(await bills.all(), isEmpty);

      final raw = await appDb.db.query('obligations');
      expect(raw, hasLength(1));
      expect(raw.first['deleted_at'], '2026-11-14T08:00:00.000Z');
    });

    test('updating a deleted bill fails', () async {
      final created = await carLoan();
      await bills.delete(created.id);
      expect(() => bills.update(created.copyWith(amountSen: 1)), throwsStateError);
    });

    test('rejects invalid input', () {
      expect(
        () => bills.create(name: '   ', amountSen: 100, frequency: Frequency.once, startDate: dateOf(2026, 11, 1)),
        throwsArgumentError,
      );
      expect(
        () => bills.create(name: 'X', amountSen: -1, frequency: Frequency.once, startDate: dateOf(2026, 11, 1)),
        throwsArgumentError,
      );
      expect(
        () => bills.create(
          name: 'X',
          amountSen: 1,
          frequency: Frequency.monthly,
          intervalCount: 0,
          startDate: dateOf(2026, 11, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => bills.create(
          name: 'X',
          amountSen: 1,
          frequency: Frequency.monthly,
          payByBufferDays: -3,
          startDate: dateOf(2026, 11, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => bills.create(
          name: 'X',
          amountSen: 1,
          frequency: Frequency.monthly,
          startDate: dateOf(2026, 11, 10),
          endDate: dateOf(2026, 11, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PaymentRepository', () {
    test('markPaid then read it back', () async {
      final loan = await carLoan();
      final paid = await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);

      expect(paid.dueDate, dateOf(2026, 11, 17));
      expect(paid.paidAt, now);

      final list = await payments.forObligation(loan.id);
      expect(list, hasLength(1));
      expect(list.first.amountSen, 52000);
    });

    test('marking the same occurrence twice keeps a single payment', () async {
      final loan = await carLoan();
      final a = await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);
      final b = await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);

      expect(b.id, a.id);
      expect(await payments.forObligation(loan.id), hasLength(1));
    });

    test('different months are separate payments', () async {
      final loan = await carLoan();
      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);
      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 12, 17), amountSen: 52000);

      final list = await payments.forObligation(loan.id);
      expect(list.map((p) => toIsoDate(p.dueDate)), ['2026-12-17', '2026-11-17']); // newest first
    });

    test('undo hides the payment, and it can be paid again afterwards', () async {
      final loan = await carLoan();
      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);

      expect(await payments.undoPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17)), isTrue);
      expect(await payments.forObligation(loan.id), isEmpty);
      expect(await payments.undoPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17)), isFalse);

      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);
      expect(await payments.forObligation(loan.id), hasLength(1));

      // Both rows exist on disk: one undone, one active. The partial unique
      // index only counts the active one.
      expect(await appDb.db.query('payments'), hasLength(2));
    });

    test('paidBetween returns only payments inside the range, keyed for lookup', () async {
      final loan = await carLoan();
      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 10, 17), amountSen: 52000);
      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);

      final map = await payments.paidBetween(dateOf(2026, 11, 1), dateOf(2026, 11, 30));

      expect(map, hasLength(1));
      expect(map.containsKey('${loan.id}|2026-11-17'), isTrue);
      expect(map.containsKey('${loan.id}|2026-10-17'), isFalse);
    });

    test('deleting a bill also hides its payments', () async {
      final loan = await carLoan();
      await payments.markPaid(obligationId: loan.id, dueDate: dateOf(2026, 11, 17), amountSen: 52000);

      await bills.delete(loan.id);

      expect(await payments.forObligation(loan.id), isEmpty);
      expect(await payments.paidBetween(dateOf(2026, 1, 1), dateOf(2026, 12, 31)), isEmpty);
    });

    test('database refuses a payment for a bill that does not exist', () async {
      expect(
        () => payments.markPaid(obligationId: 'no-such-bill', dueDate: dateOf(2026, 11, 17), amountSen: 100),
        throwsA(anything),
      );
    });
  });
}
