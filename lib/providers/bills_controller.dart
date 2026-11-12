import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../data/obligation_repository.dart';
import '../data/payment_repository.dart';
import '../domain/obligation.dart';
import '../domain/payment.dart';
import '../domain/recurrence.dart';

enum BillFilter { upcoming, paid, all }

/// One row on the Bills screen: a real due date of a bill, plus the payment
/// that settled it (null if it is still unpaid).
class BillItem {
  const BillItem(this.occurrence, this.payment);

  final Occurrence occurrence;
  final Payment? payment;

  bool get isPaid => payment != null;
}

DateTime _systemToday() => dateOnly(DateTime.now());

/// Holds what the Bills screen needs and tells it when something changes.
///
/// Flow: load() reads bills and payments from SQLite, asks the recurrence
/// engine for the due dates in the window, pairs each with its payment (if
/// any), then calls notifyListeners() so the screen redraws.
class BillsController extends ChangeNotifier {
  BillsController({required this._obligations, required this._payments, DateTime Function()? today, this.onLoaded})
    : _todayFn = today ?? _systemToday;

  /// Runs after every load, once the screen has been told. The app uses it to
  /// reschedule reminders, so they always match what the list shows.
  final Future<void> Function()? onLoaded;

  /// Unpaid bills from this far back still show up, as overdue.
  static const lookBackDays = 30;

  /// The last day shown ahead: the day BEFORE today's date next month.
  ///
  /// A flat "30 days" counted a bill due on the 12th twice on the 12th (12 Nov
  /// and 12 Dec), doubling the total. This way a monthly bill appears exactly
  /// once, and a day such as the 31st is clamped to the shorter month's end.
  static DateTime lookAheadEnd(DateTime today) {
    final nextMonth = today.month == 12 ? 1 : today.month + 1;
    final year = today.month == 12 ? today.year + 1 : today.year;
    return addDays(clampedDate(year, nextMonth, today.day), -1);
  }

  final ObligationRepository _obligations;
  final PaymentRepository _payments;
  final DateTime Function() _todayFn;

  List<BillItem> _items = const [];
  BillFilter _filter = BillFilter.upcoming;
  bool _loading = true;
  bool _hasBills = false;
  String? _error;

  /// Today as a calendar date. Asked every time, so the app stays right if it
  /// is left open past midnight.
  DateTime get today => dateOnly(_todayFn());

  BillFilter get filter => _filter;
  bool get isLoading => _loading;
  bool get hasBills => _hasBills;
  String? get errorMessage => _error;

  /// Everything in the window, soonest first.
  List<BillItem> get all => _items;

  /// What the current filter shows.
  List<BillItem> get visible {
    switch (_filter) {
      case BillFilter.upcoming:
        return _items.where((i) => !i.isPaid).toList();
      case BillFilter.paid:
        // _items is oldest first, so reversing puts the latest payment on top.
        return _items.where((i) => i.isPaid).toList().reversed.toList();
      case BillFilter.all:
        return _items;
    }
  }

  /// Sum of everything unpaid in the window (overdue + due soon), in sen.
  int get toPaySen => _items.where((i) => !i.isPaid).fold(0, (sum, i) => sum + i.occurrence.amountSen);

  int get overdueCount => _items.where((i) => !i.isPaid && i.occurrence.dueDate.isBefore(today)).length;

  /// Sum of what was paid, in sen, for due dates inside the window.
  int get paidSen => _items.where((i) => i.isPaid).fold(0, (sum, i) => sum + i.payment!.amountSen);

  void setFilter(BillFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final t = today;
      final from = addDays(t, -lookBackDays);
      final to = lookAheadEnd(t);

      final bills = await _obligations.all();
      final paid = await _payments.paidBetween(from, to);
      final occurrences = occurrencesBetween(bills, from, to);

      _hasBills = bills.isNotEmpty;
      _items = [for (final o in occurrences) BillItem(o, paid[o.key])];
      _error = null;
    } catch (e) {
      _error = 'Could not load your bills.';
      if (kDebugMode) debugPrint('BillsController.load failed: $e');
    }
    _loading = false;
    notifyListeners();

    // After the screen is updated, so a slow or failing reminder never delays the UI.
    try {
      await onLoaded?.call();
    } catch (e) {
      if (kDebugMode) debugPrint('onLoaded failed: $e');
    }
  }

  /// Creates a bill. Returns it, or null if saving failed (see [errorMessage]).
  Future<Obligation?> createBill({
    required String name,
    required int amountSen,
    required bool isEstimate,
    required Frequency frequency,
    required int intervalCount,
    required DateTime startDate,
    DateTime? endDate,
    required int payByBufferDays,
    String? note,
  }) async {
    try {
      final created = await _obligations.create(
        name: name,
        amountSen: amountSen,
        isEstimate: isEstimate,
        frequency: frequency,
        intervalCount: intervalCount,
        startDate: startDate,
        endDate: endDate,
        payByBufferDays: payByBufferDays,
        note: note,
      );
      await load();
      return created;
    } catch (e) {
      return _failed<Obligation>('Could not save the bill.', e);
    }
  }

  Future<bool> updateBill(Obligation bill) async {
    try {
      await _obligations.update(bill);
      await load();
      return true;
    } catch (e) {
      return _failed<bool>('Could not save your changes.', e) ?? false;
    }
  }

  Future<bool> deleteBill(String id) async {
    try {
      await _obligations.delete(id);
      await load();
      return true;
    } catch (e) {
      return _failed<bool>('Could not delete the bill.', e) ?? false;
    }
  }

  /// Remembers the problem for the screen to show, and returns null.
  T? _failed<T>(String message, Object error) {
    _error = message;
    if (kDebugMode) debugPrint('$message $error');
    notifyListeners();
    return null;
  }

  /// Records the payment, then reloads so every number is recalculated.
  Future<void> markPaid(BillItem item) async {
    try {
      await _payments.markPaid(
        obligationId: item.occurrence.obligation.id,
        dueDate: item.occurrence.dueDate,
        amountSen: item.occurrence.amountSen,
      );
    } catch (e) {
      _error = 'Could not save that payment.';
      if (kDebugMode) debugPrint('markPaid failed: $e');
    }
    await load();
  }

  Future<void> undoPaid(BillItem item) async {
    try {
      await _payments.undoPaid(obligationId: item.occurrence.obligation.id, dueDate: item.occurrence.dueDate);
    } catch (e) {
      _error = 'Could not undo that payment.';
      if (kDebugMode) debugPrint('undoPaid failed: $e');
    }
    await load();
  }
}
