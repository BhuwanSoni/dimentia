import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// ─────────────────────────────────────────────────────────────────────────────
// ID STRATEGY
// ─────────────────────────────────────────────────────────────────────────────
//
//  Every reminder uses a single notification ID derived from its Firestore docId.
//  Overdue follow-ups are DISABLED (kOverdueCount = 0) to prevent spam.
//
//  Call markDone(baseId) when the user confirms completion — it cancels
//  the notification so it is never shown after done.

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Function(String?)? onNotificationClick;

  // FIX: Set to 0 — overdue follow-ups were causing 4x notification spam.
  // One reminder = one notification. No follow-ups.
  static const int kOverdueCount = 0;

  // Gap between each overdue follow-up (kept for markDone loop compatibility).
  static const Duration kOverdueInterval = Duration(minutes: 5);

  // ─── Repeating-alert guard ────────────────────────────────────
  static bool _stopRepeating = false;
  static bool _repeatingAlertRunning = false;

  // ─── Vibration patterns ──────────────────────────────────────
  static final Int64List _medicineVibration =
      Int64List.fromList([0, 800, 300, 800, 300, 800]);

  static final Int64List _emergencyVibration =
      Int64List.fromList([0, 1000, 200, 1000, 200, 1000, 200, 1000]);

  static final Int64List _missedVibration =
      Int64List.fromList([0, 600, 400, 600, 400, 600, 400, 600]);

  // ─── Channels ────────────────────────────────────────────────
  static const AndroidNotificationChannel _reminderChannel =
      AndroidNotificationChannel(
    'reminder_channel',
    'Daily Reminders',
    description: 'Reminder notifications',
    importance: Importance.max,
  );

  static const AndroidNotificationChannel _emergencyChannel =
      AndroidNotificationChannel(
    'emergency_channel',
    'Emergency Alerts',
    description: 'Critical emergency notifications',
    importance: Importance.max,
  );

  // ─────────────────────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────────────────────

  static Future<void> init() async {
    tz_data.initializeTimeZones();

    // Hardcoded Asia/Kolkata — flutter_timezone removed due to
    // Kotlin 'Unresolved reference: Registrar' build error on this setup.
    // Safe for India-only deployment.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == 'DONE') {
          debugPrint('✅ Done clicked — payload: ${response.payload}');
          final payload = response.payload ?? '';
          if (payload.startsWith('done:')) {
            final baseId = int.tryParse(payload.replaceFirst('done:', ''));
            if (baseId != null) {
              markDone(baseId);
            }
          }
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
      await androidPlugin?.createNotificationChannel(_emergencyChannel);
      // overdue_channel kept for safe channel removal (won't receive new notifs)
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PERMISSIONS
  // ─────────────────────────────────────────────────────────────

  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;

    final androidPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final notifGranted =
        await androidPlugin?.requestNotificationsPermission();
    if (notifGranted != true) {
      debugPrint('⚠️ Notification permission denied or not granted');
    }

    await androidPlugin?.requestExactAlarmsPermission();
  }

  // ─────────────────────────────────────────────────────────────
  // PRIVATE — build AndroidNotificationDetails
  // ─────────────────────────────────────────────────────────────

  static AndroidNotificationDetails _buildDetails({
    required String channelId,
    required String channelName,
    required Int64List vibrationPattern,
    required AndroidNotificationCategory category,
    String ticker = 'reminder_alert',
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      ticker: ticker,
      category: category,
      fullScreenIntent: false,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PRIVATE — schedule one zonedSchedule notification
  // ─────────────────────────────────────────────────────────────

  static Future<void> _scheduleZoned({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime tzTime,
    required AndroidNotificationDetails androidDetails,
    String? payload,
  }) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        NotificationDetails(android: androidDetails),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('✅ Scheduled id=$id at $tzTime');
    } catch (e) {
      debugPrint('❌ Failed to schedule id=$id : $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SCHEDULE REMINDER  ← main entry point
  //
  //  FIX: Cancels any existing notification with the same id BEFORE
  //  scheduling. This prevents duplicate notifications when the stream
  //  listener and restart-recovery both try to schedule the same reminder.
  //
  //  FIX: kOverdueCount = 0 so no follow-up spam is generated.
  // ─────────────────────────────────────────────────────────────

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime scheduledTime,
    String userName = 'User',
    NotificationAlertType type = NotificationAlertType.task,
    bool enableOverdueFollowUps = false, // FIX: disabled by default
  }) async {
    if (!Platform.isAndroid) return;

    // FIX: Cancel any existing notification with this id before scheduling.
    // Prevents duplicates if called multiple times for the same reminder.
    await _notificationsPlugin.cancel(id);
    debugPrint('🗑️ Pre-cancelled id=$id before scheduling');

    final now = DateTime.now();

    bool wasClamped = false;
    if (scheduledTime.isBefore(now)) {
      scheduledTime = now.add(const Duration(seconds: 30));
      wasClamped = true;
      debugPrint(
        '⚠️ scheduleReminder: scheduledTime was in the past — '
        'clamped to 30 s from now. Overdue follow-ups will NOT be scheduled.',
      );
    }

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    debugPrint('📅 Scheduling — id=$id  type=$type  title="$title"');
    debugPrint('   scheduledTime (local) : $scheduledTime');
    debugPrint('   tzTime                : $tzTime');
    debugPrint('   tz.local              : ${tz.local.name}');
    debugPrint('   now (device)          : $now');
    debugPrint(
        '   tzTime in future?     : ${tzTime.isAfter(tz.TZDateTime.now(tz.local))}');

    String dayText;
    if (scheduledTime.day == now.day) {
      dayText = 'Today';
    } else if (scheduledTime.day == now.add(const Duration(days: 1)).day) {
      dayText = 'Tomorrow';
    } else {
      dayText = DateFormat('MMM d').format(scheduledTime);
    }
    final timeText = DateFormat('hh:mm a').format(scheduledTime);

    final notifTitle = _primaryTitle(type, userName);
    final notifBody  = _primaryBody(type, title, userName, dayText, timeText);
    final pattern    = _patternFor(type);

    final details = _buildDetails(
      channelId: 'reminder_channel',
      channelName: 'Daily Reminders',
      vibrationPattern: pattern,
      category: AndroidNotificationCategory.reminder,
    );

    await _scheduleZoned(
      id: id,
      title: notifTitle,
      body: notifBody,
      tzTime: tzTime,
      androidDetails: details,
      payload: 'done:$id',
    );

    // FIX: kOverdueCount = 0, so this block never executes.
    // Overdue follow-ups are permanently disabled to prevent notification spam.
    if (enableOverdueFollowUps && kOverdueCount > 0 && !wasClamped) {
      debugPrint('📌 Overdue follow-ups disabled (kOverdueCount=0)');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PRIMARY NOTIFICATION TEXT HELPERS
  // ─────────────────────────────────────────────────────────────

  static String _primaryTitle(NotificationAlertType type, String userName) {
    return switch (type) {
      NotificationAlertType.medicine    => '💊 Medicine Reminder for $userName',
      NotificationAlertType.emergency   => '🚨 Emergency Task for $userName',
      NotificationAlertType.missed      => '🔔 Missed Reminder for $userName',
      NotificationAlertType.task        => '📌 Task Reminder for $userName',
      NotificationAlertType.appointment => '🗓️ Appointment Reminder for $userName',
      NotificationAlertType.water       => '💧 Hydration Reminder for $userName',
      NotificationAlertType.exercise    => '🏃 Exercise Reminder for $userName',
    };
  }

  static String _primaryBody(
    NotificationAlertType type,
    String taskTitle,
    String userName,
    String dayText,
    String timeText,
  ) {
    return switch (type) {
      NotificationAlertType.medicine =>
        '$userName, it\'s time to take "$taskTitle"\n📅 $dayText • ⏰ $timeText',
      NotificationAlertType.emergency =>
        '$userName, emergency task due: "$taskTitle"\n📅 $dayText • ⏰ $timeText',
      NotificationAlertType.missed =>
        '$userName, pending task: "$taskTitle"\n📅 $dayText • ⏰ $timeText',
      NotificationAlertType.task =>
        '$userName, complete your task: "$taskTitle"\n📅 $dayText • ⏰ $timeText',
      NotificationAlertType.appointment =>
        '$userName, appointment: "$taskTitle"\n📅 $dayText • ⏰ $timeText',
      NotificationAlertType.water =>
        '$userName, time to drink water! 💧\n📅 $dayText • ⏰ $timeText',
      NotificationAlertType.exercise =>
        '$userName, time for your exercise: "$taskTitle"\n📅 $dayText • ⏰ $timeText',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // MARK DONE  — cancel the notification
  // ─────────────────────────────────────────────────────────────
  //
  //  With kOverdueCount = 0 this just cancels the single notification id.
  //  The loop is kept so callers don't need to change.

  static Future<void> markDone(int baseId) async {
    for (int i = 0; i <= kOverdueCount; i++) {
      await _notificationsPlugin.cancel(baseId + i);
    }
    debugPrint('✅ markDone: cancelled id $baseId');
  }

  static Int64List _patternFor(NotificationAlertType type) {
    return switch (type) {
      NotificationAlertType.emergency => _emergencyVibration,
      NotificationAlertType.missed    => _missedVibration,
      _                               => _medicineVibration,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // HARD ALERT  (immediate, no schedule)
  // ─────────────────────────────────────────────────────────────

  static Future<void> triggerHardAlert({
    required int id,
    required String title,
    required String body,
    NotificationAlertType type = NotificationAlertType.medicine,
  }) async {
    if (!Platform.isAndroid) return;

    final pattern     = _patternFor(type);
    final channelId   = type == NotificationAlertType.emergency
        ? 'emergency_channel'
        : 'reminder_channel';
    final channelName = type == NotificationAlertType.emergency
        ? 'Emergency Alerts'
        : 'Daily Reminders';

    final androidDetails = _buildDetails(
      channelId: channelId,
      channelName: channelName,
      vibrationPattern: pattern,
      category: type == NotificationAlertType.emergency
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      ticker: 'hard_alert',
    );

    try {
      await _notificationsPlugin.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
      debugPrint('🔔 Hard alert fired id=$id type=$type');
    } catch (e) {
      debugPrint('❌ Hard alert failed id=$id : $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // REPEATING ALERT  (in-process loop)
  // ─────────────────────────────────────────────────────────────

  static void stopRepeatingAlert() {
    _stopRepeating = true;
    debugPrint('🛑 Repeating alert stop requested');
  }

  static Future<void> startRepeatingAlert({
    required int id,
    required String title,
    required String body,
    NotificationAlertType type = NotificationAlertType.missed,
    int repeatCount = 5,
    int intervalSeconds = 20,
  }) async {
    if (_repeatingAlertRunning) {
      debugPrint('⚠️ Repeating alert already running — ignoring duplicate call');
      return;
    }

    _stopRepeating = false;
    _repeatingAlertRunning = true;
    debugPrint(
        '🔁 Starting repeating alert — $repeatCount × every ${intervalSeconds}s');

    try {
      for (int i = 0; i < repeatCount; i++) {
        if (_stopRepeating) {
          debugPrint('🛑 Repeating alert stopped at iteration $i');
          break;
        }
        await triggerHardAlert(id: id, title: title, body: body, type: type);
        if (i < repeatCount - 1) {
          await Future.delayed(Duration(seconds: intervalSeconds));
        }
      }
    } finally {
      _repeatingAlertRunning = false;
      debugPrint('✅ Repeating alert finished');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // INSTANT NOTIFICATION  (for foreground FCM messages)
  // ─────────────────────────────────────────────────────────────

  static Future<void> showInstantNotification({
    required String title,
    required String body,
  }) async {
    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CANCEL
  // ─────────────────────────────────────────────────────────────

  static Future<void> cancelReminder(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint('🗑️ Cancelled notification id=$id');
  }

  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
    debugPrint('🗑️ All notifications cancelled');
  }

  // ─────────────────────────────────────────────────────────────
  // DEBUG
  // ─────────────────────────────────────────────────────────────

  static Future<void> debugPendingNotifications() async {
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    debugPrint('📋 Pending notifications: ${pending.length}');
    for (final n in pending) {
      debugPrint('   id=${n.id}  title=${n.title}');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERT TYPE ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum NotificationAlertType {
  medicine,     // 💊 3× 800ms vibration
  emergency,    // 🚨 4× 1000ms vibration
  missed,       // 🔁 4× 600ms vibration
  task,         // 📌 3× 800ms vibration
  appointment,  // 🗓️ 3× 800ms vibration
  water,        // 💧 3× 800ms vibration
  exercise,     // 🏃 3× 800ms vibration
}