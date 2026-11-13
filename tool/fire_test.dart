// A throw-away app for ONE device experiment: does a reminder still show when the app is opened
// just AFTER the reminder's time, before Android has delivered it?
//
// This reproduces a real bug: reminders are "inexact" alarms that Android may deliver a few
// minutes late, and re-planning used to cancel a reminder that was due but not yet delivered.
//
// It uses the app's real LocalNotificationScheduler. Reminder 1 is due 2 minutes from now. 20 seconds
// AFTER it is due, this app re-plans with an empty future plan, exactly like the real app does when it
// comes to the foreground. With the bug, reminder 1 never shows. With the fix, it does.
//
// Build:  flutter build apk --release -t tool/fire_test.dart
import 'dart:async';

import 'package:bayar/domain/reminder_planner.dart';
import 'package:bayar/services/local_notification_scheduler.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = LocalNotificationScheduler();
  await scheduler.init();
  final granted = await scheduler.hasPermission() || await scheduler.requestPermission();

  final now = DateTime.now();
  // --dart-define=DUE=09:18 picks the minute; otherwise 2 minutes from now.
  const dueText = String.fromEnvironment('DUE');
  final due = dueText.isEmpty
      ? DateTime(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(minutes: 2))
      : DateTime(now.year, now.month, now.day, int.parse(dueText.split(':')[0]), int.parse(dueText.split(':')[1]));

  await scheduler.replaceAll(now: now, [
    PlannedReminder(
      at: due,
      kind: ReminderKind.payDay,
      title: 'REPLAN TEST: due $due',
      body: 'This must show even though the app re-planned after its time.',
      occurrenceKey: 'replan-1',
    ),
  ]);

  // "The user opens the app" 20 seconds after the reminder was due; nothing in the future to plan.
  final reopenAt = due.add(const Duration(seconds: 20));
  Timer(reopenAt.difference(DateTime.now()), () => scheduler.replaceAll(now: DateTime.now(), const []));

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'permission: $granted\ndue $due\nre-plan at $reopenAt\nthen wait for the notification',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
