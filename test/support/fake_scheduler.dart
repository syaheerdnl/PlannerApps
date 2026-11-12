import 'package:bayar/domain/reminder_planner.dart';
import 'package:bayar/services/reminder_scheduler.dart';

/// A scheduler that only records what it was asked to do. No phone, no plugin.
class FakeScheduler implements ReminderScheduler {
  FakeScheduler({this.permissionGranted = true, this.grantOnRequest = true, this.launchPayloadValue});

  /// What the "phone" says when asked if notifications are allowed.
  bool permissionGranted;

  /// Whether tapping "Allow" in the fake system dialog grants permission.
  bool grantOnRequest;

  String? launchPayloadValue;

  /// Pretend scheduling takes this long, so tests can overlap calls.
  Duration replaceDelay = Duration.zero;

  bool initialised = false;
  int permissionRequests = 0;
  int replaceCalls = 0;
  int testNotifications = 0;

  /// The reminders that are scheduled right now.
  List<PlannedReminder> scheduled = [];

  int _active = 0;
  int maxConcurrentReplaces = 0;
  void Function(String? payload)? _onTap;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    initialised = true;
    _onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launchPayloadValue;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (grantOnRequest) permissionGranted = true;
    return permissionGranted;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    _active++;
    if (_active > maxConcurrentReplaces) maxConcurrentReplaces = _active;
    if (replaceDelay > Duration.zero) await Future<void>.delayed(replaceDelay);
    scheduled = List.of(reminders);
    replaceCalls++;
    _active--;
  }

  @override
  Future<void> showTest() async => testNotifications++;

  /// Simulates the user tapping a notification.
  void tapNotification(String? payload) => _onTap?.call(payload);
}
