import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Function(String?)? onNotificationClick;

  static const AndroidNotificationChannel _reminderChannel =
      AndroidNotificationChannel(
    'reminder_channel',
    'Daily Reminders',
    description: 'Reminder notifications',
    importance: Importance.max,
  );

  static Future<void> init() async {
    tz_data.initializeTimeZones();

    // ─── BUG FIX 1: Timezone ─────────────────────────────────────────────────
    // Hard-coding 'Asia/Kolkata' causes wrong fire times if the device is in
    // a different timezone. Use `flutter_timezone` package instead:
    //
    //   pubspec.yaml:
    //     flutter_timezone: ^1.0.8
    //
    //   Then replace the line below with:
    //     import 'package:flutter_timezone/flutter_timezone.dart';
    //     final tzName = await FlutterTimezone.getLocalTimezone();
    //     tz.setLocalLocation(tz.getLocation(tzName));
    //
    // Keeping Asia/Kolkata for now — replace this as soon as possible.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    // ─────────────────────────────────────────────────────────────────────────

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == 'DONE') {
          debugPrint('✅ Done clicked');
        } else if (response.actionId == 'CALL') {
          debugPrint('📞 Call clicked');
        }
        onNotificationClick?.call(response.payload);
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_reminderChannel);
    }
  }

  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;

    final androidPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Standard notification permission (Android 13+)
    await androidPlugin?.requestNotificationsPermission();

    // ─── BUG FIX 2: Exact alarm permission (Android 12+) ─────────────────────
    // Without this, zonedSchedule() silently does nothing on Android 12+.
    //
    // You MUST also add this to android/app/src/main/AndroidManifest.xml
    // inside the <manifest> tag (not inside <application>):
    //
    //   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    //
    // This shows a system dialog asking the user to allow exact alarms.
    // If the user denies it, notifications will not fire — handle this case
    // by checking canScheduleExactNotifications() and showing a message.
    await androidPlugin?.requestExactAlarmsPermission();
    // ─────────────────────────────────────────────────────────────────────────
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime scheduledTime,
    String userName = "User",
  }) async {
    if (!Platform.isAndroid) return;

    final now = DateTime.now();

    // ─── BUG FIX 3: Minimum future buffer ────────────────────────────────────
    // 10 seconds is not enough — by the time Firestore write + this call
    // completes, the time may already be in the past. zonedSchedule() silently
    // ignores past times. Use 30 seconds minimum.
    if (scheduledTime.isBefore(now)) {
      scheduledTime = now.add(const Duration(seconds: 30));
    }
    // ─────────────────────────────────────────────────────────────────────────

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    // ─── DEBUG: remove after confirming notifications work ───────────────────
    debugPrint('📅 Scheduling — id=$id  title="$title"');
    debugPrint('   scheduledTime (local) : $scheduledTime');
    debugPrint('   tzTime                : $tzTime');
    debugPrint('   tz.local              : ${tz.local.name}');
    debugPrint('   now (device)          : $now');
    final tzNow = tz.TZDateTime.now(tz.local);
    debugPrint('   tzTime in future?     : ${tzTime.isAfter(tzNow)}');
    // ─────────────────────────────────────────────────────────────────────────

    String dayText;
    if (scheduledTime.day == now.day) {
      dayText = 'Today';
    } else if (scheduledTime.day == now.add(const Duration(days: 1)).day) {
      dayText = 'Tomorrow';
    } else {
      dayText = DateFormat('MMM d').format(scheduledTime);
    }

    final timeText = DateFormat('hh:mm a').format(scheduledTime);
    final newTitle = '🔔 Reminder for $userName';
    final newBody =
        "$userName, it's time to $title\n📅 $dayText • ⏰ $timeText";

    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Daily Reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('DONE', '✅ Done'),
        AndroidNotificationAction('CALL', '📞 Call'),
      ],
    );

    await _notificationsPlugin.zonedSchedule(
      id,
      newTitle,
      newBody,
      tzTime,
      const NotificationDetails(android: androidDetails),
      payload: title,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    debugPrint('✅ Notification scheduled successfully id=$id');
  }

  static Future<void> cancelReminder(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint('🗑️ Cancelled notification id=$id');
  }

  /// Call this anywhere in debug builds to confirm what is actually scheduled.
  static Future<void> debugPendingNotifications() async {
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    debugPrint('📋 Pending notifications: ${pending.length}');
    for (final n in pending) {
      debugPrint('   id=${n.id}  title=${n.title}');
    }
  }
}