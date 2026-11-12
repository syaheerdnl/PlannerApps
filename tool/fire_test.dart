// A throw-away app for ONE device experiment: does a scheduled reminder really fire by
// itself, and does it still fire after the phone restarts?
//
// It uses the app's real LocalNotificationScheduler, but schedules two reminders a few
// minutes from NOW instead of "9:00 on the due date", because the clock of an emulator
// cannot be moved. Run with:  flutter build apk --debug -t tool/fire_test.dart
import 'package:bayar/domain/reminder_planner.dart';
import 'package:bayar/services/local_notification_scheduler.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = LocalNotificationScheduler();
  await scheduler.init();
  final granted = await scheduler.hasPermission() || await scheduler.requestPermission();

  final now = DateTime.now();
  DateTime at(int minutes) {
    final t = now.add(Duration(minutes: minutes));
    return DateTime(t.year, t.month, t.day, t.hour, t.minute);
  }

  final first = at(2);
  final second = at(9);
  await scheduler.replaceAll([
    PlannedReminder(
      at: first,
      kind: ReminderKind.payDay,
      title: 'FIRE TEST 1: Car loan',
      body: 'Scheduled for $first',
      occurrenceKey: 'fire-1',
    ),
    PlannedReminder(
      at: second,
      kind: ReminderKind.payDay,
      title: 'FIRE TEST 2 (after reboot): TNB',
      body: 'Scheduled for $second',
      occurrenceKey: 'fire-2',
    ),
  ]);

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('permission: $granted\nR1 at $first\nR2 at $second', textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
