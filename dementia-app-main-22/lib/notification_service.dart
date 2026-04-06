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

    // Using hardcoded Asia/Kolkata — flutter_timezone removed due to
    // Kotlin 'Unresolved reference: Registrar' build error on this setup.
    // Safe for India-only deployment.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

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

    // ✅ FIX: Handle permission result safely — never crash if denied.
    final notifGranted =
        await androidPlugin?.requestNotificationsPermission();
    if (notifGranted != true) {
      debugPrint('⚠️ Notification permission denied or not granted');
      // Do NOT return — exact alarm request below is still useful
    }

    // inexactAllowWhileIdle does NOT require exact alarm permission,
    // but requesting it here is harmless and enables exact alarms if
    // the user grants it, which improves timing accuracy.
    await androidPlugin?.requestExactAlarmsPermission();
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime scheduledTime,
    String userName = 'User',
  }) async {
    if (!Platform.isAndroid) return;

    final now = DateTime.now();

    // Clamp past times to 30 s in the future.
    // zonedSchedule() silently ignores past times — clamping here ensures
    // the notification always fires even if there is a small scheduling lag.
    if (scheduledTime.isBefore(now)) {
      scheduledTime = now.add(const Duration(seconds: 30));
    }

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    // ─── DEBUG logs — remove after confirming notifications work ────────────
    debugPrint('📅 Scheduling — id=$id  title="$title"');
    debugPrint('   scheduledTime (local) : $scheduledTime');
    debugPrint('   tzTime                : $tzTime');
    debugPrint('   tz.local              : ${tz.local.name}');
    debugPrint('   now (device)          : $now');
    final tzNow = tz.TZDateTime.now(tz.local);
    debugPrint('   tzTime in future?     : ${tzTime.isAfter(tzNow)}');
    // ────────────────────────────────────────────────────────────────────────

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

    // ✅ FIX 1: Removed fullScreenIntent: true.
    //    fullScreenIntent requires USE_FULL_SCREEN_INTENT permission (Android 14+)
    //    and is blocked by most OEM ROMs (Xiaomi, Samsung, Realme).
    //    It causes a runtime crash or silent failure in release APKs.
    //
    // ✅ FIX 2: Removed notification actions temporarily.
    //    Actions can cause crashes in release if the BroadcastReceiver
    //    for the action is not declared in AndroidManifest.xml.
    //    Re-add them only after confirming basic notifications work.
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Daily Reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      // fullScreenIntent removed ✅
      category: AndroidNotificationCategory.reminder,
      // actions removed for stability ✅ — add back after basic flow confirmed
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        newTitle,
        newBody,
        tzTime,
        const NotificationDetails(android: androidDetails),
        payload: title,
        // ✅ inexactAllowWhileIdle works on ALL Android versions without
        //    SCHEDULE_EXACT_ALARM permission and fires reliably.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('✅ Notification scheduled successfully id=$id');
    } catch (e) {
      // ✅ FIX: Wrap in try/catch so one bad notification never crashes the app.
      debugPrint('❌ Failed to schedule notification id=$id : $e');
    }
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