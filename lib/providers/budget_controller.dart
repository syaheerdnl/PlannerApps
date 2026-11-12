import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../data/budget_repository.dart';
import '../data/obligation_repository.dart';
import '../data/settings_repository.dart';
import '../domain/budget.dart';
import '../domain/pay_cycle.dart';
import '../domain/recurrence.dart';

/// One envelope's budget for the cycle being planned (the Plan tab).
class PlanRow {
  const PlanRow(this.envelope, this.budgetSen);

  final Envelope envelope;
  final int budgetSen;
}

DateTime _systemToday() => dateOnly(DateTime.now());

/// Everything about the salary budget: payday, envelopes, what each gets, and
/// what has been spent.
///
/// load() reads the database and works out the numbers once; screens read the
/// results and are told to redraw. Every change writes to the database and then
/// calls load() again, so the screens can never show something the database
/// does not have.
class BudgetController extends ChangeNotifier {
  BudgetController({
    required this._budget,
    required this._settings,
    required this._obligations,
    DateTime Function()? today,
    this.onChanged,
  }) : _todayFn = today ?? _systemToday;

  /// Called after the USER changes something (not after a plain reload), so the
  /// app can sync the change to the cloud.
  final VoidCallback? onChanged;

  final BudgetRepository _budget;
  final SettingsRepository _settings;
  final ObligationRepository _obligations;
  final DateTime Function() _todayFn;

  PlanSettings? _plan;
  List<Envelope> _envelopes = const [];
  List<Allocation> _allocations = const [];
  List<Spending> _spendings = const [];
  int _billsCurrentSen = 0;
  int _billsNextSen = 0;
  bool _planningNext = false;
  bool _loading = true;
  String? _error;

  DateTime get today => dateOnly(_todayFn());
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  /// False until payday and salary have been entered.
  bool get isSetUp => _plan != null;
  PlanSettings? get plan => _plan;
  List<Envelope> get envelopes => _envelopes;

  /// The cycle we are in right now. Null until set up.
  PayCycle? get cycle => _plan == null ? null : PayCycle.containing(today, paydayDay: _plan!.paydayDay);

  /// The cycle shown on the Plan tab: this one, or the next.
  PayCycle? get planCycle {
    final c = cycle;
    if (c == null) return null;
    return _planningNext ? c.next(paydayDay: _plan!.paydayDay) : c;
  }

  bool get planningNext => _planningNext;

  int get daysLeft => cycle?.daysLeft(today) ?? 0;
  DateTime? get nextPayday => cycle?.nextPayday;

  // ── What you can spend (current cycle) ────────────────────────────────────

  List<EnvelopeView> get envelopeViews {
    final c = cycle;
    if (c == null) return const [];
    return [
      for (final e in _envelopes)
        buildEnvelopeView(envelope: e, allocations: _allocations, spendings: _spendings, cycle: c, today: today),
    ];
  }

  /// Money left across all envelopes (an overspent envelope counts as negative).
  int get leftToSpendSen => envelopeViews.fold(0, (sum, v) => sum + v.leftSen);

  /// What you can spend today, summed over the envelopes that still have money.
  int get dailySafeSen => envelopeViews.fold(0, (sum, v) => sum + v.dailySafeSen);

  // ── Planning (the cycle chosen on the Plan tab) ───────────────────────────

  List<PlanRow> get planRows {
    final c = planCycle;
    if (c == null) return const [];
    return [for (final e in _envelopes) PlanRow(e, allocationFor(_allocations, e.id, c.start))];
  }

  int get salarySen => _plan?.salarySen ?? 0;

  /// Every bill due in the planned cycle, paid or not: this money is spoken for.
  int get billsReservedSen => _planningNext ? _billsNextSen : _billsCurrentSen;

  int get allocatedSen => planRows.fold(0, (sum, r) => sum + r.budgetSen);

  /// Salary - bills - envelopes. Zero means every ringgit has a job.
  int get unassignedSen => salarySen - billsReservedSen - allocatedSen;

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      await _budget.createDefaultEnvelopesOnce();
      _plan = await _settings.loadPlan();
      _envelopes = await _budget.envelopes();
      _allocations = await _budget.allocations();

      final c = cycle;
      if (c == null) {
        _spendings = const [];
        _billsCurrentSen = 0;
        _billsNextSen = 0;
      } else {
        final next = c.next(paydayDay: _plan!.paydayDay);
        _spendings = await _budget.spendingsBetween(c.start, c.end);
        final bills = await _obligations.all();
        _billsCurrentSen = _sumBills(occurrencesBetween(bills, c.start, c.end));
        _billsNextSen = _sumBills(occurrencesBetween(bills, next.start, next.end));
      }
      _error = null;
    } catch (e) {
      _error = 'Could not load your budget.';
      if (kDebugMode) debugPrint('BudgetController.load failed: $e');
    }
    _loading = false;
    notifyListeners();
  }

  int _sumBills(List<Occurrence> occurrences) => occurrences.fold(0, (sum, o) => sum + o.amountSen);

  // ── Changes. Each returns true on success. ────────────────────────────────

  Future<bool> savePlan({required int paydayDay, required int salarySen}) {
    return _run(
      'Could not save your salary.',
      () => _settings.savePlan(PlanSettings(paydayDay: paydayDay, salarySen: salarySen)),
    );
  }

  void setPlanningNext(bool next) {
    if (next == _planningNext) return;
    _planningNext = next;
    notifyListeners();
  }

  /// Sets the budget of [envelopeId] for the cycle on the Plan tab.
  Future<bool> setBudget(String envelopeId, int amountSen) {
    final c = planCycle;
    if (c == null) return Future.value(false);
    return _run(
      'Could not save that budget.',
      () =>
          _budget.setAllocation(envelopeId: envelopeId, cycleStart: c.start, amountSen: amountSen < 0 ? 0 : amountSen),
    );
  }

  // Budget +/- taps are queued, so two quick taps become two steps, not one.
  Future<void> _adjustQueue = Future.value();

  /// Moves a budget by [deltaSen] from its CURRENT value (never below zero).
  ///
  /// Taps are run one after another. If each tap read the value from the screen
  /// instead, two fast taps would both start from the same number and the
  /// second would undo nothing and add nothing.
  Future<bool> adjustBudget(String envelopeId, int deltaSen) {
    final result = _adjustQueue.then((_) {
      final current = planRows.where((r) => r.envelope.id == envelopeId).firstOrNull?.budgetSen ?? 0;
      return setBudget(envelopeId, current + deltaSen);
    });
    _adjustQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> addEnvelope(String name) => _run('Could not add that envelope.', () => _budget.createEnvelope(name));

  Future<bool> renameEnvelope(String id, String name) =>
      _run('Could not rename that envelope.', () => _budget.renameEnvelope(id, name));

  Future<bool> deleteEnvelope(String id) => _run('Could not delete that envelope.', () => _budget.deleteEnvelope(id));

  Future<bool> addSpending({
    required String envelopeId,
    required int amountSen,
    required DateTime spentOn,
    String? note,
  }) {
    return _run(
      'Could not save that spending.',
      () => _budget.addSpending(envelopeId: envelopeId, amountSen: amountSen, spentOn: spentOn, note: note),
    );
  }

  Future<bool> deleteSpending(String id) => _run('Could not delete that spending.', () => _budget.deleteSpending(id));

  Future<bool> _run(String failure, Future<void> Function() action) async {
    try {
      await action();
      await load();
      onChanged?.call();
      return true;
    } catch (e) {
      _error = failure;
      if (kDebugMode) debugPrint('$failure $e');
      notifyListeners();
      return false;
    }
  }

  /// The few most recent distinct notes for an envelope, for one-tap reuse.
  List<String> recentNotes(String envelopeId, {int limit = 4}) {
    final seen = <String>{};
    final notes = <String>[];
    for (final s in _spendings) {
      if (s.envelopeId != envelopeId || s.note == null) continue;
      if (seen.add(s.note!.toLowerCase())) notes.add(s.note!);
      if (notes.length == limit) break;
    }
    return notes;
  }
}
