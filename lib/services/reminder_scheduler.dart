import '../domain/reminder_planner.dart';

/// What the app needs from "the thing that shows notifications".
///
/// The app talks to this interface only. The real implementation wraps the
/// notification plugin; tests use a fake, so no phone is needed to test the logic.
abstract class ReminderScheduler {
  /// Prepares the plugin. [onTap] is called with the payload when the user taps
  /// a notification while the app is running or in the background.
  Future<void> init({void Function(String? payload)? onTap});

  /// If the app was started by tapping a notification, its payload; otherwise null.
  Future<String?> launchPayload();

  Future<bool> hasPermission();

  /// Shows the system permission dialog. Returns true if the user allowed it.
  Future<bool> requestPermission();

  /// Makes the scheduled reminders match [reminders] (future ones only). [now] is the phone's wall-clock
  /// time. A reminder that is already due but still being delivered is left alone, so opening the
  /// app a minute after 9:00 cannot cancel the 9:00 reminder.
  Future<void> replaceAll(List<PlannedReminder> reminders, {required DateTime now});

  /// Shows a notification right now (debug builds use this to test the setup).
  Future<void> showTest();
}

/// The payload attached to every bill reminder. Tapping it opens the Bills tab.
const billsPayload = 'bills';
