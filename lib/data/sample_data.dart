import '../core/dates.dart';
import '../domain/budget.dart';
import '../domain/obligation.dart';
import 'budget_repository.dart';
import 'settings_repository.dart';
import 'obligation_repository.dart';
import 'payment_repository.dart';

/// Debug-only demo data: the same bills as the design prototype.
///
/// It only runs when the database has no bills at all, and main.dart only
/// calls it in debug builds, so a real install starts empty.
///
/// Each bill's start date is its FIRST TRACKED due date (see the recurrence
/// engine), which is why the paid ones start on the day they were paid.
Future<void> seedSampleBills(ObligationRepository bills, PaymentRepository payments) async {
  if ((await bills.all()).isNotEmpty) return;

  final insurance = await bills.create(
    name: 'Insurance',
    amountSen: 15000,
    frequency: Frequency.yearly,
    startDate: dateOf(2026, 10, 28),
  );
  final streaming = await bills.create(
    name: 'Streaming',
    amountSen: 1700,
    frequency: Frequency.monthly,
    startDate: dateOf(2026, 11, 3),
  );
  final internet = await bills.create(
    name: 'Internet',
    amountSen: 12900,
    frequency: Frequency.monthly,
    startDate: dateOf(2026, 11, 8),
  );
  await bills.create(
    name: 'Phone plan',
    amountSen: 6800,
    frequency: Frequency.monthly,
    startDate: dateOf(2026, 11, 12),
    payByBufferDays: 1,
  );
  await bills.create(
    name: 'Car loan',
    amountSen: 52000,
    frequency: Frequency.monthly,
    startDate: dateOf(2026, 11, 17),
    payByBufferDays: 2,
  );
  await bills.create(
    name: 'TNB electricity',
    amountSen: 18000,
    isEstimate: true,
    frequency: Frequency.monthly,
    startDate: dateOf(2026, 11, 22),
    payByBufferDays: 2,
    note: 'Estimate from the last 3 bills',
  );

  await payments.markPaid(obligationId: insurance.id, dueDate: dateOf(2026, 10, 28), amountSen: 15000);
  await payments.markPaid(obligationId: streaming.id, dueDate: dateOf(2026, 11, 3), amountSen: 1700);
  await payments.markPaid(obligationId: internet.id, dueDate: dateOf(2026, 11, 8), amountSen: 12900);
}

/// Debug-only demo budget: payday on the 25th, salary RM 3,800, and the same
/// spending as the design prototype (Fuel RM 132 left, Food RM 278.50, Other RM 340).
Future<void> seedSampleBudget(BudgetRepository budget, SettingsRepository settings) async {
  if (await settings.loadPlan() != null) return;

  await settings.savePlan(const PlanSettings(paydayDay: 25, salarySen: 380000));
  await budget.createDefaultEnvelopesOnce();
  final ids = {for (final e in await budget.envelopes()) e.name: e.id};

  final cycleStart = dateOf(2026, 10, 25); // the cycle 25 Oct .. 24 Nov
  await budget.setAllocation(envelopeId: ids['Fuel']!, cycleStart: cycleStart, amountSen: 30000);
  await budget.setAllocation(envelopeId: ids['Food']!, cycleStart: cycleStart, amountSen: 70000);
  await budget.setAllocation(envelopeId: ids['Other']!, cycleStart: cycleStart, amountSen: 50000);

  Future<void> spend(String envelope, int sen, DateTime on, String note) =>
      budget.addSpending(envelopeId: ids[envelope]!, amountSen: sen, spentOn: on, note: note);

  await spend('Fuel', 10800, dateOf(2026, 10, 28), 'Petrol');
  await spend('Fuel', 6000, dateOf(2026, 11, 9), 'Petrol');
  await spend('Food', 33670, dateOf(2026, 10, 30), 'Groceries');
  await spend('Food', 1850, dateOf(2026, 11, 9), 'Dinner');
  await spend('Food', 5430, dateOf(2026, 11, 10), 'Groceries');
  await spend('Food', 1200, dateOf(2026, 11, 12), 'Lunch');
  await spend('Other', 11700, dateOf(2026, 10, 31), 'Gift');
  await spend('Other', 3500, dateOf(2026, 11, 7), 'Haircut');
  await spend('Other', 800, dateOf(2026, 11, 10), 'Parking');
}
