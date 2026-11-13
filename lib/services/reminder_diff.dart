import '../domain/reminder_planner.dart';

// Decides what to cancel and what to schedule when the reminders are re-planned.
//
// Why this exists: Android delivers our reminders as "inexact" alarms, which may arrive a few
// minutes AFTER their time (a window of up to about 10 minutes for a reminder due soon). The app
// re-plans every time it opens. The planner only returns FUTURE reminders, so "cancel everything,
// then schedule the plan" used to delete a reminder that was due at 09:00 but not yet delivered
// when the app was opened at 09:00:33. The reminder never showed.
//
// The fix is to leave alone any pending reminder that is already due but still within a short
// delivery window. To know when a pending notification is due, its id ENCODES the due minute.

/// Reminders are numbered from this moment (wall-clock, treated as UTC so there is no DST maths).
final _epoch = DateTime.utc(2026);

/// Room for this many reminders in the same minute (say, many bills due at 09:00).
const _slotsPerMinute = 100;

/// A reminder this far past its time, and still pending, will not arrive any more: clear it.
const staleAfter = Duration(hours: 2);

/// The id for the [slot]th reminder at [at].
///
/// minutes * 100 + slot: for the next several years this is far below the 32-bit limit
/// notification ids must fit in (2,147,483,647 allows about 40 years).
int reminderIdFor(DateTime at, int slot) {
  assert(slot >= 0 && slot < _slotsPerMinute);
  final minutes = DateTime.utc(at.year, at.month, at.day, at.hour, at.minute).difference(_epoch).inMinutes;
  return minutes * _slotsPerMinute + slot;
}

/// The due time (wall-clock) encoded in an id made by [reminderIdFor].
DateTime reminderTimeOfId(int id) => _epoch.add(Duration(minutes: id ~/ _slotsPerMinute));

/// A reminder to schedule, with the id to schedule it under.
class ScheduledSlot {
  const ScheduledSlot(this.id, this.reminder);

  final int id;
  final PlannedReminder reminder;
}

class ReplacePlan {
  const ReplacePlan({required this.cancel, required this.schedule});

  final List<int> cancel;
  final List<ScheduledSlot> schedule;
}

/// [pendingIds] are the reminders Android still has waiting. [desired] is the fresh plan
/// (future reminders only). [now] is the phone's wall-clock time.
ReplacePlan planReplacement({
  required Iterable<int> pendingIds,
  required List<PlannedReminder> desired,
  required DateTime now,
}) {
  final nowAsUtc = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);

  final cancel = <int>[];
  for (final id in pendingIds) {
    final due = reminderTimeOfId(id);
    final dueButNotDelivered = !due.isAfter(nowAsUtc) && due.isAfter(nowAsUtc.subtract(staleAfter));
    // Keep a reminder that is due right now and still on its way. Everything else (future ones, which
    // the new plan re-adds, and stale or old-style ids) is cleared.
    if (!dueButNotDelivered) cancel.add(id);
  }

  final schedule = <ScheduledSlot>[];
  final perMinute = <int, int>{};
  for (final r in desired) {
    final key = reminderIdFor(r.at, 0);
    final slot = perMinute[key] = (perMinute[key] ?? -1) + 1;
    if (slot >= _slotsPerMinute) continue; // absurd: 100 reminders in one minute
    schedule.add(ScheduledSlot(key + slot, r));
  }
  return ReplacePlan(cancel: cancel, schedule: schedule);
}
