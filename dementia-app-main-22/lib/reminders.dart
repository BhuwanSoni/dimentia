import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'settings_provider.dart';
import 'notification_service.dart';

class Reminder {
  final String id;
  final String title;
  final DateTime time;
  final bool isCompleted;
  final String recurringType; // ✅ NEW: none | daily | weekly | monthly | custom
  final bool isMissed;        // ✅ NEW: true when backend marks it missed

  Reminder({
    required this.id,
    required this.title,
    required this.time,
    required this.isCompleted,
    this.recurringType = 'none',
    this.isMissed = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class FirestoreService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get userId => _auth.currentUser!.uid;

  // ✅ UPDATED: now accepts recurringType so manual reminders can also be recurring
  Future<DocumentReference> addReminder(
    String title,
    DateTime time, {
    String recurringType = 'none',
  }) async {
    final ts = Timestamp.fromDate(time.toUtc());
    return await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .add({
      'title':          title,
      'task':           title,
      'time':           ts,
      'scheduled_time': ts,
      'completed':      false,
      'missed':         false,
      'source':         'manual',
      'recurring_type': recurringType, // ✅ stored so backend can advance it
    });
  }

  Stream<QuerySnapshot> getReminders() {
    return _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .orderBy('scheduled_time')
        .snapshots();
  }

  Future<void> toggleComplete(String id, bool value) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .update({'completed': value});
  }

  Future<DateTime?> getReminderTime(String id) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .get();
    if (!doc.exists) return null;
    final data   = doc.data()!;
    final rawTime = data['scheduled_time'] ?? data['time'];
    if (rawTime == null) return null;
    if (rawTime is Timestamp) return rawTime.toDate().toLocal();
    if (rawTime is String) {
      final parsed = DateTime.tryParse(rawTime);
      if (parsed == null) return null;
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }
    return null;
  }

  Future<void> deleteReminder(String id) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .delete();
  }

  // ✅ NEW: Snooze a missed reminder by updating scheduled_time in Firestore.
  // The Firestore stream will pick it up and re-schedule the notification.
  Future<void> snoozeReminder(String id, {int snoozeMinutes = 10}) async {
    final newTime = DateTime.now().toUtc().add(Duration(minutes: snoozeMinutes));
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .update({
      'scheduled_time': Timestamp.fromDate(newTime),
      'time':           Timestamp.fromDate(newTime),
      'completed':      false,
      'missed':         false,
      'snoozed_until':  Timestamp.fromDate(newTime),
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REMINDER PAGE
// ─────────────────────────────────────────────────────────────────────────────
class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final firestore = FirestoreService();
  final Set<String> _scheduledIds = {};

  // ✅ NEW: Track IDs for which we've already shown a missed-reminder banner
  // this session to avoid spamming the user.
  final Set<String> _missedBannerShown = {};

  int _notificationIdFromDocId(String docId) {
    return docId.hashCode.abs() % 2147483647;
  }

  StreamSubscription<QuerySnapshot>? _reminderSub;

  @override
  void initState() {
    super.initState();

    _reminderSub = firestore.getReminders().listen((snapshot) async {
      if (!mounted) return;
      final userName = SettingsProvider.of(context).username;

      for (final change in snapshot.docChanges) {
        final docId = change.doc.id;
        final data  = change.doc.data() as Map<String, dynamic>;

        debugPrint('STREAM EVENT: ${change.type} $docId');

        if (change.type == DocumentChangeType.removed) {
          await NotificationService.markDone(_notificationIdFromDocId(docId));
          _scheduledIds.remove(docId);
          _missedBannerShown.remove(docId);
          continue;
        }

        if (change.type == DocumentChangeType.modified) {
          final isCompleted = data['completed'] == true;
          final isMissed    = data['missed']    == true;

          if (isCompleted) {
            await NotificationService.markDone(_notificationIdFromDocId(docId));
            _scheduledIds.remove(docId);
          }

          // ✅ NEW: Show snooze banner when a reminder is marked missed
          if (isMissed && !_missedBannerShown.contains(docId) && mounted) {
            _missedBannerShown.add(docId);
            final taskName = data['task'] ?? data['title'] ?? 'your reminder';
            _showMissedReminderBanner(docId, taskName);
          }

          // ✅ NEW: Re-schedule notification after snooze (scheduled_time changed)
          if (!isCompleted && !isMissed && _scheduledIds.contains(docId)) {
            final rawTime = data['scheduled_time'] ?? data['time'];
            if (rawTime is Timestamp) {
              final newTime = rawTime.toDate().toLocal();
              if (newTime.isAfter(DateTime.now())) {
                final title = data['task'] ?? data['title'] ?? 'Reminder';
                await NotificationService.scheduleReminder(
                  id:            _notificationIdFromDocId(docId),
                  title:         title,
                  scheduledTime: newTime,
                  userName:      userName,
                  type:          NotificationAlertType.task,
                );
                debugPrint('🔔 Re-scheduled (snooze): $title at $newTime');
              }
            }
          }
          continue;
        }

        if (change.type != DocumentChangeType.added) continue;
        if (_scheduledIds.contains(docId)) continue;
        if (data['completed'] == true) continue;

        final rawTime = data['scheduled_time'] ?? data['time'];
        if (rawTime == null) {
          debugPrint('⚠️ Reminder $docId has no time field — skipping');
          continue;
        }

        DateTime scheduledTime;
        if (rawTime is Timestamp) {
          scheduledTime = rawTime.toDate().toLocal();
        } else if (rawTime is String) {
          final parsed = DateTime.tryParse(rawTime);
          if (parsed == null) continue;
          scheduledTime = parsed.isUtc ? parsed.toLocal() : parsed;
        } else {
          continue;
        }

        if (scheduledTime
            .isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
          debugPrint('⚠️ Reminder $docId is in the past — skipping notification');
          continue;
        }

        _scheduledIds.add(docId);
        final title = data['task'] ?? data['title'] ?? 'Reminder';
        await NotificationService.scheduleReminder(
          id:            _notificationIdFromDocId(docId),
          title:         title,
          scheduledTime: scheduledTime,
          userName:      userName,
          type:          NotificationAlertType.task,
        );

        debugPrint('🔔 Scheduled reminder: $title at $scheduledTime ($docId)');
      }
    });
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    super.dispose();
  }

  // ✅ NEW: Show a SnackBar with a snooze action when a reminder is missed
  void _showMissedReminderBanner(String reminderId, String taskName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        backgroundColor: Colors.orange.shade700,
        content: Text(
          '⏰ You missed: "$taskName". Remind again in 10 min?',
          style: const TextStyle(color: Colors.white),
        ),
        action: SnackBarAction(
          label: 'Snooze 10 min',
          textColor: Colors.white,
          onPressed: () async {
            await firestore.snoozeReminder(reminderId, snoozeMinutes: 10);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Reminder snoozed for 10 minutes'),
                  backgroundColor: Color(0xFF2D6A4F),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  String _dayLabel(DateTime time) {
    final now         = DateTime.now();
    final today       = DateTime(now.year, now.month, now.day);
    final tomorrow    = today.add(const Duration(days: 1));
    final reminderDay = DateTime(time.year, time.month, time.day);

    if (reminderDay == today)    return 'Today';
    if (reminderDay == tomorrow) return 'Tomorrow';
    return DateFormat('MMM d').format(time);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ UPDATED: ADD REMINDER DIALOG — now includes recurring type picker
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showAddReminderDialog() async {
    final titleController = TextEditingController();
    DateTime?   pickedDate;
    TimeOfDay?  pickedTime;
    String      recurringType = 'none'; // ✅ default

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'New Reminder',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D6A4F),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title input ──────────────────────────────────────
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: 'Enter reminder',
                        prefixIcon: const Icon(Icons.edit_note,
                            color: Color(0xFF2D6A4F)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Quick category chips ─────────────────────────────
                    // These pre-fill the text field with common tasks.
                    const Text(
                      'Quick Add',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _quickChip('💊 Medicine',  titleController, setDialogState),
                        _quickChip('💧 Water',     titleController, setDialogState),
                        _quickChip('🚶 Walking',   titleController, setDialogState),
                        _quickChip('🩺 BP Check',  titleController, setDialogState),
                        _quickChip('🍽 Meal',       titleController, setDialogState),
                        _quickChip('💉 Insulin',   titleController, setDialogState),
                        _quickChip('🙏 Prayers',   titleController, setDialogState),
                        _quickChip('😴 Sleep',     titleController, setDialogState),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Date picker ──────────────────────────────────────
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today,
                          color: Color(0xFF2D6A4F)),
                      title: Text(
                        pickedDate == null
                            ? 'Pick date'
                            : DateFormat('MMM d, yyyy').format(pickedDate!),
                      ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate:   DateTime.now(),
                          lastDate:    DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setDialogState(() => pickedDate = d);
                      },
                    ),

                    // ── Time picker ──────────────────────────────────────
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time,
                          color: Color(0xFF2D6A4F)),
                      title: Text(
                        pickedTime == null
                            ? 'Pick time'
                            : pickedTime!.format(context),
                      ),
                      onTap: () async {
                        final t = await showTimePicker(
                          context:     context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (t != null) setDialogState(() => pickedTime = t);
                      },
                    ),
                    const SizedBox(height: 8),

                    // ✅ NEW: Recurring type quick-select chips
                    const Text(
                      'Repeat',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _recurringChip('🗓 One Time', 'none',    recurringType, (v) => setDialogState(() => recurringType = v)),
                        _recurringChip('🔁 Daily',    'daily',   recurringType, (v) => setDialogState(() => recurringType = v)),
                        _recurringChip('📅 Weekly',   'weekly',  recurringType, (v) => setDialogState(() => recurringType = v)),
                        _recurringChip('🗒 Monthly',  'monthly', recurringType, (v) => setDialogState(() => recurringType = v)),
                      ],
                    ),

                    // ✅ Show helpful hint when recurring is selected
                    if (recurringType != 'none') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          recurringType == 'daily'
                              ? '🔁 This reminder will repeat every day at the selected time.'
                              : recurringType == 'weekly'
                                  ? '📅 This will repeat every week on the same day.'
                                  : '🗒 This will repeat every month on the same date.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2D6A4F),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty ||
                        pickedDate == null ||
                        pickedTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please fill all fields')),
                      );
                      return;
                    }

                    final scheduledTime = DateTime(
                      pickedDate!.year,
                      pickedDate!.month,
                      pickedDate!.day,
                      pickedTime!.hour,
                      pickedTime!.minute,
                    );

                    if (scheduledTime.isBefore(DateTime.now())) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please pick a future time')),
                      );
                      return;
                    }

                    Navigator.pop(context);

                    await firestore.addReminder(
                      title,
                      scheduledTime,
                      recurringType: recurringType, // ✅ pass to Firestore
                    );

                    if (context.mounted) {
                      final recurringHint = recurringType != 'none'
                          ? ' (${recurringType[0].toUpperCase()}${recurringType.substring(1)})'
                          : '';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ Reminder set for ${DateFormat('MMM d • hh:mm a').format(scheduledTime)}$recurringHint',
                          ),
                          backgroundColor: const Color(0xFF2D6A4F),
                        ),
                      );
                    }
                  },
                  child: const Text('Save',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ✅ Helper: Quick-fill chip for task name
  Widget _quickChip(String label, TextEditingController controller,
      void Function(void Function()) setDialogState) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: const Color(0xFFE8F5E9),
      onPressed: () => setDialogState(() {
        // Strip emoji prefix for the task text
        final text = label.replaceAll(RegExp(r'^\S+\s'), '').trim();
        controller.text = text;
      }),
    );
  }

  // ✅ Helper: Recurring type selection chip
  Widget _recurringChip(
    String label,
    String value,
    String selected,
    void Function(String) onSelected,
  ) {
    final isSelected = selected == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      selectedColor: const Color(0xFF2D6A4F),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
      ),
      checkmarkColor: Colors.white,
      onSelected: (_) => onSelected(value),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DELETE REMINDER
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _deleteReminder(Reminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: Text('Delete "${reminder.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await firestore.deleteReminder(reminder.id);
    await NotificationService.markDone(_notificationIdFromDocId(reminder.id));
    _scheduledIds.remove(reminder.id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ UPDATED: REMINDER CARD — shows recurring badge
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildReminderCard(Reminder reminder) {
    final settings  = SettingsProvider.of(context);
    final now       = DateTime.now();
    final isOverdue = reminder.time.isBefore(now) && !reminder.isCompleted;

    final dayLabel  = _dayLabel(reminder.time);
    final timeLabel = DateFormat('hh:mm a').format(reminder.time);
    final fullLabel = '$dayLabel • $timeLabel';

    // ✅ Recurring badge label
    final recurringBadge = {
      'daily':   '🔁 Daily',
      'weekly':  '📅 Weekly',
      'monthly': '🗒 Monthly',
    }[reminder.recurringType];

    IconData cardIcon;
    if (reminder.isCompleted) {
      cardIcon = Icons.check_circle_outline;
    } else if (reminder.isMissed) {
      cardIcon = Icons.alarm_off_rounded;
    } else if (isOverdue) {
      cardIcon = Icons.warning_amber_rounded;
    } else if (reminder.recurringType != 'none') {
      cardIcon = Icons.repeat_rounded;           // ✅ recurring icon
    } else {
      cardIcon = Icons.notifications_active_outlined;
    }

    Color iconColor;
    if (reminder.isCompleted) {
      iconColor = Colors.grey;
    } else if (reminder.isMissed) {
      iconColor = Colors.orange;
    } else if (isOverdue) {
      iconColor = Colors.red;
    } else if (reminder.recurringType != 'none') {
      iconColor = const Color(0xFF1976D2);      // blue for recurring
    } else {
      iconColor = const Color(0xFF2D6A4F);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: reminder.isCompleted
                    ? Colors.grey.shade100
                    : reminder.isMissed
                        ? Colors.orange.shade50
                        : isOverdue
                            ? Colors.red.shade50
                            : reminder.recurringType != 'none'
                                ? Colors.blue.shade50
                                : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(cardIcon, color: iconColor, size: 24),
            ),

            const SizedBox(width: 14),

            // Title + date/time + recurring badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: TextStyle(
                      fontSize: 17 * settings.fontSizeMultiplier,
                      fontWeight: FontWeight.bold,
                      color: reminder.isCompleted
                          ? Colors.grey
                          : Colors.black87,
                      decoration: reminder.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Time row
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: reminder.isMissed
                            ? Colors.orange
                            : isOverdue
                                ? Colors.red
                                : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          fullLabel,
                          style: TextStyle(
                            fontSize: 14 * settings.fontSizeMultiplier,
                            color: reminder.isMissed
                                ? Colors.orange
                                : isOverdue
                                    ? Colors.red
                                    : Colors.grey.shade600,
                            fontWeight: (isOverdue || reminder.isMissed)
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ✅ Badges row
                  if (isOverdue || reminder.isMissed || recurringBadge != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (reminder.isMissed)
                          _badge('Missed', Colors.orange),
                        if (!reminder.isMissed && isOverdue)
                          _badge('Overdue', Colors.red),
                        if (recurringBadge != null)
                          _badge(recurringBadge, const Color(0xFF1976D2)),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    reminder.isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: reminder.isCompleted
                        ? Colors.green
                        : Colors.grey.shade400,
                    size: 28,
                  ),
                  onPressed: () async {
                    final completing = !reminder.isCompleted;
                    await firestore.toggleComplete(reminder.id, completing);

                    final notifId = _notificationIdFromDocId(reminder.id);
                    if (completing) {
                      await NotificationService.markDone(notifId);
                      _scheduledIds.remove(reminder.id);
                    } else {
                      final scheduledTime =
                          await firestore.getReminderTime(reminder.id);
                      if (scheduledTime != null &&
                          scheduledTime.isAfter(DateTime.now())) {
                        final userName = SettingsProvider.of(context).username;
                        await NotificationService.scheduleReminder(
                          id:            notifId,
                          title:         reminder.title,
                          scheduledTime: scheduledTime,
                          userName:      userName,
                          type:          NotificationAlertType.task,
                        );
                      }
                    }
                  },
                ),

                // ✅ Snooze button for missed reminders
                if (reminder.isMissed)
                  IconButton(
                    icon: const Icon(Icons.snooze_rounded,
                        color: Colors.orange, size: 24),
                    tooltip: 'Snooze 10 min',
                    onPressed: () async {
                      await firestore.snoozeReminder(reminder.id,
                          snoozeMinutes: 10);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('✅ Reminder snoozed for 10 minutes'),
                            backgroundColor: Color(0xFF2D6A4F),
                          ),
                        );
                      }
                    },
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 24),
                    onPressed: () => _deleteReminder(reminder),
                  ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.2, duration: 300.ms);
  }

  // ✅ Helper: small badge pill
  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
      appBar: AppBar(
        title: const Text(
          'Daily Schedule',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2D6A4F),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug pending notifications',
            onPressed: () async {
              await NotificationService.debugPendingNotifications();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Check debug console for pending notifications'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReminderDialog,
        backgroundColor: const Color(0xFF2D6A4F),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Reminder',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder(
        stream: firestore.getReminders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF2D6A4F)),
            );
          }

          final reminders = snapshot.data!.docs.map((doc) {
            final data    = doc.data() as Map<String, dynamic>;
            final rawTime = data['scheduled_time'] ?? data['time'];

            if (rawTime == null) {
              return Reminder(
                id:            doc.id,
                title:         data['task'] ?? data['title'] ?? 'No Title',
                time:          DateTime.now(),
                isCompleted:   data['completed'] ?? false,
                recurringType: data['recurring_type'] ?? 'none',
                isMissed:      data['missed'] ?? false,
              );
            }

            DateTime parsedTime;
            if (rawTime is Timestamp) {
              parsedTime = rawTime.toDate().toLocal();
            } else if (rawTime is String) {
              final parsed = DateTime.tryParse(rawTime);
              if (parsed != null) {
                parsedTime = parsed.isUtc ? parsed.toLocal() : parsed;
              } else {
                parsedTime = DateTime.now();
              }
            } else {
              parsedTime = DateTime.now();
            }

            return Reminder(
              id:            doc.id,
              title:         data['task'] ?? data['title'] ?? 'No Title',
              time:          parsedTime,
              isCompleted:   data['completed'] ?? false,
              recurringType: data['recurring_type'] ?? 'none', // ✅ NEW
              isMissed:      data['missed']    ?? false,         // ✅ NEW
            );
          }).toList();

          reminders.sort((a, b) => a.time.compareTo(b.time));

          if (reminders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No reminders yet 😊',
                    style: TextStyle(
                      fontSize: 18 * settings.fontSizeMultiplier,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add one',
                    style: TextStyle(
                      fontSize: 14 * settings.fontSizeMultiplier,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 100),
            itemCount: reminders.length,
            itemBuilder: (context, index) =>
                _buildReminderCard(reminders[index]),
          );
        },
      ),
    );
  }
}