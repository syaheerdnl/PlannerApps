import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_planner.dart';
import 'reminder_diff.dart';
import 'reminder_scheduler.dart';
import 'time_zone.dart';

/// The real thing: schedules notifications through flutter_local_notifications.
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'bill_reminders';
  static const _channelName = 'Bill reminders';
  static const _channelDescription = 'Reminders to pay your bills on time';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    await _setUpTimeZone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_bayar'),
        // Permission is asked later, from our own screen, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap?.call(response.payload),
    );
  }

  /// Scheduled times are "9:00 in the phone's time zone", so the plugin must know
  /// which zone that is. Without this it would use UTC and fire at the wrong hour.
  Future<void> _setUpTimeZone() async {
    // The full database, so alias zones like Asia/Kuala_Lumpur exist.
    tzdata.initializeTimeZones();

    String? name;
    try {
      name = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (e) {
      if (kDebugMode) debugPrint('Could not read the phone time zone: $e');
    }

    tz.setLocalLocation(resolveLocation(identifier: name, deviceOffset: DateTime.now().timeZoneOffset));
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  @override
  Future<bool> hasPermission() async {
    if (_isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (_isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    if (_isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (_isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders, {required DateTime now}) async {
    // Ask what Android is still holding, and clear only what the new plan replaces. A reminder that is
    // due but not yet delivered stays (see reminder_diff.dart), so re-planning never eats a reminder
    // that is about to show.
    final pending = await _plugin.pendingNotificationRequests();
    final plan = planReplacement(pendingIds: pending.map((p) => p.id), desired: reminders, now: now);

    for (final id in plan.cancel) {
      await _plugin.cancel(id: id);
    }

    for (final slot in plan.schedule) {
      final r = slot.reminder;
      try {
        await _plugin.zonedSchedule(
          id: slot.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime(tz.local, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute),
          notificationDetails: _details,
          // "Inexact" lets Android deliver it within a short window of 9:00 to save
          // battery, and needs no special alarm permission. Fine for a bill reminder.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: billsPayload,
        );
      } catch (e) {
        // One bad reminder must not stop the rest from being scheduled.
        if (kDebugMode) debugPrint('Could not schedule "${r.title}": $e');
      }
    }
  }

  @override
  Future<void> showTest() {
    return _plugin.show(
      id: 0,
      title: 'Car loan: time to pay',
      body: 'RM 520.00 · due Tue 17 Nov (test)',
      notificationDetails: _details,
      payload: billsPayload,
    );
  }
}
