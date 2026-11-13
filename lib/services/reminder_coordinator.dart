import 'package:flutter/foundation.dart';

import '../data/obligation_repository.dart';
import '../data/payment_repository.dart';
import '../domain/reminder_planner.dart';
import 'reminder_scheduler.dart';

/// Where notification permission stands.
enum ReminderPermission {
  /// Notifications are allowed; reminders are scheduled.
  granted,

  /// Not allowed yet and we have not asked: show the "turn on reminders" card.
  needsAsk,

  /// The user said no. Android will not show the dialog again, so they must use Settings.
  denied,
}

/// Keeps the scheduled reminders in step with the bills.
///
/// sync() = read bills and payments -> ask the planner what should exist ->
/// hand that list to the scheduler. It is called after every change.
class ReminderCoordinator extends ChangeNotifier {
  ReminderCoordinator({
    required this._obligations,
    required this._payments,
    required this._scheduler,
    this.planner = const ReminderPlanner(),
    DateTime Function()? now,
    this.onOpenBills,
  }) : _now = now ?? DateTime.now;

  final ObligationRepository _obligations;
  final PaymentRepository _payments;
  final ReminderScheduler _scheduler;
  final ReminderPlanner planner;
  final DateTime Function() _now;

  /// Called when the user taps a reminder.
  final VoidCallback? onOpenBills;

  ReminderPermission _permission = ReminderPermission.needsAsk;
  int _scheduledCount = 0;

  // sync() calls are chained so two never run at once. Two overlapping
  // "cancel everything, then schedule" runs could otherwise leave stray reminders.
  Future<void> _queue = Future.value();

  ReminderPermission get permission => _permission;
  bool get isOn => _permission == ReminderPermission.granted;

  /// How many reminders are scheduled right now.
  int get scheduledCount => _scheduledCount;

  Future<void> init() async {
    await _scheduler.init(onTap: _handleTap);
    await refreshPermission();
    _handleTap(await _scheduler.launchPayload()); // app was opened by a reminder
  }

  void _handleTap(String? payload) {
    if (payload == billsPayload) onOpenBills?.call();
  }

  /// Re-reads the permission, because the user can change it in Settings at any time.
  Future<void> refreshPermission() async {
    final granted = await _scheduler.hasPermission();
    final next = granted
        ? ReminderPermission.granted
        : (_permission == ReminderPermission.denied ? ReminderPermission.denied : ReminderPermission.needsAsk);
    if (next != _permission) {
      _permission = next;
      notifyListeners();
    }
    if (granted) await sync();
  }

  /// Shows the system dialog. Schedules everything if the user agrees.
  Future<void> requestPermission() async {
    final granted = await _scheduler.requestPermission();
    _permission = granted ? ReminderPermission.granted : ReminderPermission.denied;
    notifyListeners();
    if (granted) await sync();
  }

  Future<void> sync() {
    _queue = _queue.then((_) => _doSync()).catchError((Object e) {
      if (kDebugMode) debugPrint('Reminder sync failed: $e');
    });
    return _queue;
  }

  Future<void> _doSync() async {
    if (_permission != ReminderPermission.granted) {
      if (_scheduledCount != 0) {
        _scheduledCount = 0;
        notifyListeners();
      }
      return;
    }

    final now = _now();
    final bills = await _obligations.all();
    final paid = await _payments.paidBetween(planner.windowStart(now), planner.windowEnd(now));
    final plan = planner.plan(obligations: bills, paidKeys: paid.keys.toSet(), now: now);

    await _scheduler.replaceAll(plan, now: now);

    _scheduledCount = plan.length;
    notifyListeners();
  }

  /// Debug helper: shows one notification immediately.
  Future<void> sendTest() => _scheduler.showTest();
}
