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
//  Every reminder occupies a BLOCK of IDs so follow-up notifications never
//  collide with the original or with each other.
//
//  Given a base id (e.g. 100):
//    100       → original reminder
//    100 + 1   → 1st overdue follow-up  (+5 min)
//    100 + 2   → 2nd overdue follow-up  (+10 min)
//    100 + 3   → 3rd overdue follow-up  (+15 min)
//
//  Rule: space your base IDs at least (1 + kOverdueCount) apart.
//  e.g. use 100, 110, 120 … if kOverdueCount = 3.
//
//  Call markDone(baseId) when the user confirms completion — it cancels
//  the original + all follow-ups so they are never shown.

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Function(String?)? onNotificationClick;

  // Number of overdue follow-up pings after the original reminder fires.
  static const int kOverdueCount = 3;

  // Gap between each overdue follow-up (5 minutes).
  static const Duration kOverdueInterval = Duration(minutes: 5);

  // ─── Repeating-alert guard ────────────────────────────────────
  // Prevents a second parallel loop from starting if the first is still running.
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

  static const AndroidNotificationChannel _overdueChannel =
      AndroidNotificationChannel(
    'overdue_channel',
    'Overdue Follow-ups',
    description: 'Follow-up notifications for unfinished reminders',
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
          // FIX: Cancel original + all overdue follow-ups when user taps Done.
          // Extract baseId from payload format "type:title" is not enough to
          // recover the id, so callers should also wire markDone() from their
          // own screen. This guard handles the notification-action path by
          // passing the baseId encoded in the payload as "done:<baseId>".
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
      await androidPlugin?.createNotificationChannel(_overdueChannel);
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
      fullScreenIntent: false, // keep false — crashes on Xiaomi/Samsung
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
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('✅ Scheduled id=$id at $tzTime');
    } catch (e) {
      debugPrint('❌ Failed to schedule id=$id : $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PRIVATE — schedule overdue follow-ups
  //
  //  Schedules kOverdueCount follow-ups at:
  //    baseTime + 5 min  (id = baseId + 1)
  //    baseTime + 10 min (id = baseId + 2)
  //    baseTime + 15 min (id = baseId + 3)
  // ─────────────────────────────────────────────────────────────

  static Future<void> _scheduleOverdueFollowUps({
    required int baseId,
    required String taskTitle,
    required String userName,
    required tz.TZDateTime baseTime,
    required NotificationAlertType type,
  }) async {
    for (int i = 1; i <= kOverdueCount; i++) {
      final followUpTime   = baseTime.add(kOverdueInterval * i);
      final overdueMinutes = kOverdueInterval.inMinutes * i;
      final followUpTitle  = _overdueTitle(type, userName);
      final followUpBody   = _overdueBody(type, taskTitle, userName, overdueMinutes);
      final pattern        = _patternFor(type);

      final details = _buildDetails(
        channelId: 'overdue_channel',
        channelName: 'Overdue Follow-ups',
        vibrationPattern: pattern,
        category: AndroidNotificationCategory.reminder,
        ticker: 'overdue_alert',
      );

      await _scheduleZoned(
        id: baseId + i,
        title: followUpTitle,
        body: followUpBody,
        tzTime: followUpTime,
        androidDetails: details,
        // FIX: encode baseId in payload so markDone() can be triggered from
        // the notification action handler in init().
        payload: 'done:$baseId',
      );

      debugPrint(
        '⏰ Follow-up $i/$kOverdueCount → id=${baseId + i}  '
        'at $followUpTime  (+${overdueMinutes} min)',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // OVERDUE TEXT HELPERS
  // ─────────────────────────────────────────────────────────────

  static String _overdueTitle(NotificationAlertType type, String userName) {
    return switch (type) {
      NotificationAlertType.medicine    => '⚠️ Overdue: Medicine not taken',
      NotificationAlertType.emergency   => '🚨 Still unresolved: Emergency task',
      NotificationAlertType.missed      => '🔁 Still pending: Missed task',
      NotificationAlertType.task        => '📌 Overdue: Task not completed',
      NotificationAlertType.appointment => '🗓️ Overdue: Missed appointment',
      NotificationAlertType.water       => '💧 Overdue: Hydration reminder',
      NotificationAlertType.exercise    => '🏃 Overdue: Exercise not done',
    };
  }

  static String _overdueBody(
    NotificationAlertType type,
    String taskTitle,
    String userName,
    int minutesLate,
  ) {
    final lateText = minutesLate == 5 ? '5 minutes ago' : '$minutesLate minutes ago';

    return switch (type) {
      NotificationAlertType.medicine =>
        '$userName, you haven\'t taken "$taskTitle" yet.\n'
        'This was due $lateText. Please take it now! 💊',
      NotificationAlertType.emergency =>
        '$userName, emergency task "$taskTitle" is still unresolved.\n'
        'It was due $lateText. 🚨',
      NotificationAlertType.missed =>
        '$userName, "$taskTitle" is still pending.\n'
        'You missed it $lateText. 🔁',
      NotificationAlertType.task =>
        '$userName, the task "$taskTitle" is not done yet.\n'
        'It was due $lateText. 📌',
      NotificationAlertType.appointment =>
        '$userName, you missed your appointment: "$taskTitle".\n'
        'It was $lateText. 🗓️',
      NotificationAlertType.water =>
        '$userName, you haven\'t had water yet!\n'
        'Reminder was $lateText. Please hydrate 💧',
      NotificationAlertType.exercise =>
        '$userName, your exercise "$taskTitle" is overdue.\n'
        'It was scheduled $lateText. 🏃',
    };
  }

  static Int64List _patternFor(NotificationAlertType type) {
    return switch (type) {
      NotificationAlertType.emergency => _emergencyVibration,
      NotificationAlertType.missed    => _missedVibration,
      _                               => _medicineVibration,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // SCHEDULE REMINDER  ← main entry point
  //
  //  Works for ALL NotificationAlertType values.
  //  Automatically schedules kOverdueCount follow-ups after the
  //  original fires, 5 min apart, unless enableOverdueFollowUps = false.
  //
  //  ⚠️  ID spacing rule:
  //      Space base IDs by at least (1 + kOverdueCount) = 4.
  //      Recommended: use multiples of 10 → 100, 110, 120 …
  //
  //  FIX: If scheduledTime is in the past, it is clamped to 30 s from now
  //       but overdue follow-ups are NOT scheduled in that case — they would
  //       otherwise fire immediately and spam the user.
  // ─────────────────────────────────────────────────────────────

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime scheduledTime,
    String userName = 'User',
    NotificationAlertType type = NotificationAlertType.medicine,
    bool enableOverdueFollowUps = true,
  }) async {
    if (!Platform.isAndroid) return;

    final now = DateTime.now();

    // FIX: Track whether the time was clamped so we can skip follow-ups.
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

    // ─── DEBUG ────────────────────────────────────────────────
    debugPrint('📅 Scheduling — id=$id  type=$type  title="$title"');
    debugPrint('   scheduledTime (local) : $scheduledTime');
    debugPrint('   tzTime                : $tzTime');
    debugPrint('   tz.local              : ${tz.local.name}');
    debugPrint('   now (device)          : $now');
    debugPrint(
        '   tzTime in future?     : ${tzTime.isAfter(tz.TZDateTime.now(tz.local))}');
    // ──────────────────────────────────────────────────────────

    // ─── Friendly day / time strings ─────────────────────────
    String dayText;
    if (scheduledTime.day == now.day) {
      dayText = 'Today';
    } else if (scheduledTime.day == now.add(const Duration(days: 1)).day) {
      dayText = 'Tomorrow';
    } else {
      dayText = DateFormat('MMM d').format(scheduledTime);
    }
    final timeText = DateFormat('hh:mm a').format(scheduledTime);

    // ─── Build notification content ───────────────────────────
    final notifTitle = _primaryTitle(type, userName);
    final notifBody  = _primaryBody(type, title, userName, dayText, timeText);
    final pattern    = _patternFor(type);

    final details = _buildDetails(
      channelId: 'reminder_channel',
      channelName: 'Daily Reminders',
      vibrationPattern: pattern,
      category: AndroidNotificationCategory.reminder,
    );

    // ─── 1. Schedule original reminder ───────────────────────
    await _scheduleZoned(
      id: id,
      title: notifTitle,
      body: notifBody,
      tzTime: tzTime,
      androidDetails: details,
      // FIX: encode baseId in payload so Done action can call markDone().
      payload: 'done:$id',
    );

    // ─── 2. Schedule overdue follow-ups ──────────────────────
    // FIX: Skip follow-ups entirely when time was clamped (past-time task).
    //      Scheduling follow-ups on a clamped time causes them to fire
    //      at +5/+10/+15 min from "now", which looks like repeated spam.
    if (enableOverdueFollowUps && !wasClamped) {
      await _scheduleOverdueFollowUps(
        baseId: id,
        taskTitle: title,
        userName: userName,
        baseTime: tzTime,
        type: type,
      );
      debugPrint(
        '📌 $kOverdueCount overdue follow-ups set for id=$id '
        '(every ${kOverdueInterval.inMinutes} min)',
      );
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
  // MARK DONE  — cancel original + all follow-ups
  // ─────────────────────────────────────────────────────────────
  //
  //  Call this when the user taps "Done" or confirms completion.
  //  Cancels ids: baseId, baseId+1, baseId+2, baseId+3.

  static Future<void> markDone(int baseId) async {
    for (int i = 0; i <= kOverdueCount; i++) {
      await _notificationsPlugin.cancel(baseId + i);
    }
    debugPrint(
        '✅ markDone: cancelled ids $baseId – ${baseId + kOverdueCount}');
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
  //
  //  FIX: Added _repeatingAlertRunning guard to prevent a second
  //       parallel loop starting if this is called again before the
  //       first finishes (e.g. on hot reload or screen revisit).
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
    // FIX: Bail out if a loop is already running to avoid parallel duplicate alerts.
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
      // FIX: Always reset the flag so future calls are not permanently blocked.
      _repeatingAlertRunning = false;
      debugPrint('✅ Repeating alert finished');
    }
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