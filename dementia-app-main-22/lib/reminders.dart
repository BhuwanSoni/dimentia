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

  Reminder({
    required this.id,
    required this.title,
    required this.time,
    required this.isCompleted,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class FirestoreService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get userId => _auth.currentUser!.uid;

  // Returns DocumentReference so caller can derive a stable notification ID.
  // Writes the same schema as the Python backend so both sources are consistent.
  Future<DocumentReference> addReminder(String title, DateTime time) async {
    final ts = Timestamp.fromDate(time.toUtc());
    return await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .add({
      'title': title,
      'task': title,            // ← matches Python backend field
      'time': ts,
      'scheduled_time': ts,     // ← matches Python backend field
      'completed': false,
      'source': 'manual',
      'recurring_type': 'none',
    });
  }

  Stream<QuerySnapshot> getReminders() {
    // Returns ALL reminders (active + completed), ordered by time.
    // The UI separates them visually. We keep completed ones visible
    // so users can see their history and un-complete if needed.
    return _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .orderBy('time')
        .snapshots();
  }

  // Returns only incomplete reminders (used for notification scheduling).
  Stream<QuerySnapshot> getActiveReminders() {
    return _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .where('completed', isEqualTo: false)
        .orderBy('time')
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

  // Fetch a single reminder's scheduled time (used to re-schedule after un-complete).
  Future<DateTime?> getReminderTime(String id) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .get();
    if (!doc.exists) return null;
    final data = doc.data()!;
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

  // Track already-scheduled doc IDs so we don't double-schedule.
  // This is populated BEFORE the Firestore write in the dialog,
  // so the stream listener sees it and skips the duplicate.
  final Set<String> _scheduledIds = {};

  // The ONLY function used to compute notification ID — for both scheduling
  // and cancelling. Using any other source means cancel can never find
  // the notification that was scheduled.
  int _notificationIdFromDocId(String docId) {
    return docId.hashCode.abs() % 2147483647;
  }

  StreamSubscription<QuerySnapshot>? _reminderSub;

  @override
  void initState() {
    super.initState();

    // Stream listener — catches new reminders added while app is open.
    //
    // FIX: This is now the ONLY place that schedules notifications for
    // newly added reminders. The dialog Save button no longer calls
    // scheduleReminder() directly. Instead, it pre-registers the docId
    // in _scheduledIds before writing to Firestore, so this listener
    // skips it (the dialog already handled it). For reminders created
    // elsewhere (e.g. another device), this listener catches them normally.
    _reminderSub = firestore.getReminders().listen((snapshot) async {
      if (!mounted) return;
      final userName = SettingsProvider.of(context).username;
      for (final change in snapshot.docChanges) {
        final docId = change.doc.id;
        final data = change.doc.data() as Map<String, dynamic>;

        // ✅ FIX: Handle modifications — if a reminder is marked completed
        // (e.g. by the Python backend or another device), cancel its notifications.
        if (change.type == DocumentChangeType.modified) {
          final isCompleted = data['completed'] == true;
          if (isCompleted) {
            await NotificationService.markDone(_notificationIdFromDocId(docId));
            _scheduledIds.remove(docId);
          }
          continue;
        }

        if (change.type != DocumentChangeType.added) continue;

        // Skip if already scheduled this session (dialog pre-registered it).
        if (_scheduledIds.contains(docId)) continue;

        final rawTime = data['scheduled_time'] ?? data['time'];
        if (rawTime == null) continue;

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

        // ✅ FIX: Skip if already completed — don't schedule notifications
        // for reminders that arrive from the backend already completed.
        if (data['completed'] == true) continue;

        _scheduledIds.add(docId);
        final title = data['task'] ?? data['title'] ?? 'Reminder';
        await NotificationService.scheduleReminder(
          id: _notificationIdFromDocId(docId),
          title: title,
          scheduledTime: scheduledTime,
          userName: userName,
        );
      }
    });

    // Reschedule all future reminders on every app start.
    // The stream above only catches NEW additions. If the app restarts,
    // all previously scheduled notifications are lost from the OS.
    // This restores them from Firestore on every launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndScheduleExistingReminders();
    });
  }

  // Load and reschedule all future reminders from Firestore.
  Future<void> _loadAndScheduleExistingReminders() async {
    final snapshot = await firestore.getReminders().first;
    if (!mounted) return;

    final userName = SettingsProvider.of(context).username;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // ✅ FIX: Never reschedule completed reminders on app restart.
      if (data['completed'] == true) continue;

      final rawTime = data['scheduled_time'] ?? data['time'];
      if (rawTime == null) continue;

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

      // Skip clearly old reminders (more than 1 minute in the past)
      // — nothing useful to schedule for them.
      if (scheduledTime
          .isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
        continue;
      }

      // Skip ones already scheduled this session.
      if (_scheduledIds.contains(doc.id)) continue;

      _scheduledIds.add(doc.id);

      final title = data['task'] ?? data['title'] ?? 'Reminder';
      await NotificationService.scheduleReminder(
        id: _notificationIdFromDocId(doc.id),
        title: title,
        scheduledTime: scheduledTime,
        userName: userName,
      );
    }
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    super.dispose();
  }

  String _dayLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final reminderDay = DateTime(time.year, time.month, time.day);

    if (reminderDay == today) return 'Today';
    if (reminderDay == tomorrow) return 'Tomorrow';
    return DateFormat('MMM d').format(time);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ADD REMINDER DIALOG
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _showAddReminderDialog() async {
    final titleController = TextEditingController();
    DateTime? pickedDate;
    TimeOfDay? pickedTime;

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
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title input
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

                  // Date picker
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
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setDialogState(() => pickedDate = d);
                    },
                  ),

                  // Time picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.access_time, color: Color(0xFF2D6A4F)),
                    title: Text(
                      pickedTime == null
                          ? 'Pick time'
                          : pickedTime!.format(context),
                    ),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (t != null) setDialogState(() => pickedTime = t);
                    },
                  ),
                ],
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

                    // Save to Firestore — get the docRef first.
                    final docRef =
                        await firestore.addReminder(title, scheduledTime);

                    // FIX: Pre-register the docId in _scheduledIds BEFORE
                    // the stream listener fires. The Firestore onSnapshot
                    // callback arrives almost immediately after the write,
                    // sometimes before this line runs. By marking it here
                    // we ensure the stream listener sees the id and skips it,
                    // preventing a second scheduleReminder() call.
                    _scheduledIds.add(docRef.id);

                    // Schedule the notification HERE (single source of truth
                    // for reminders created from this device's dialog).
                    final userName =
                        SettingsProvider.of(context).username;
                    await NotificationService.scheduleReminder(
                      id: _notificationIdFromDocId(docRef.id),
                      title: title,
                      scheduledTime: scheduledTime,
                      userName: userName,
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '✅ Reminder set for ${DateFormat('MMM d • hh:mm a').format(scheduledTime)}'),
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

  // ───────────────────────────────────────────────────────────────────────────
  // DELETE REMINDER
  // ───────────────────────────────────────────────────────────────────────────
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
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await firestore.deleteReminder(reminder.id);
    // Cancel original + all overdue follow-ups (ids: baseId, baseId+1..+3).
    await NotificationService.markDone(_notificationIdFromDocId(reminder.id));
    _scheduledIds.remove(reminder.id);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // REMINDER CARD
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildReminderCard(Reminder reminder) {
    final settings = SettingsProvider.of(context);
    final now = DateTime.now();
    final isOverdue =
        reminder.time.isBefore(now) && !reminder.isCompleted;

    final dayLabel = _dayLabel(reminder.time);
    final timeLabel = DateFormat('hh:mm a').format(reminder.time);
    final fullLabel = '$dayLabel • $timeLabel';

    IconData cardIcon;
    if (reminder.isCompleted) {
      cardIcon = Icons.check_circle_outline;
    } else if (isOverdue) {
      cardIcon = Icons.warning_amber_rounded;
    } else {
      cardIcon = Icons.notifications_active_outlined;
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
                    : isOverdue
                        ? Colors.red.shade50
                        : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                cardIcon,
                color: reminder.isCompleted
                    ? Colors.grey
                    : isOverdue
                        ? Colors.red
                        : const Color(0xFF2D6A4F),
                size: 24,
              ),
            ),

            const SizedBox(width: 14),

            // Title + date/time
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
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: isOverdue
                            ? Colors.red
                            : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          fullLabel,
                          style: TextStyle(
                            fontSize: 14 * settings.fontSizeMultiplier,
                            color: isOverdue
                                ? Colors.red
                                : Colors.grey.shade600,
                            fontWeight: isOverdue
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isOverdue) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Overdue',
                            style: TextStyle(
                                color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
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
                    // Mark done in Firestore.
                    await firestore.toggleComplete(reminder.id, completing);

                    final notifId = _notificationIdFromDocId(reminder.id);
                    if (completing) {
                      // ✅ FIX: Always cancel original + ALL overdue follow-ups
                      // (ids baseId..baseId+kOverdueCount) when user completes.
                      // This handles both: user completes before notification fires,
                      // or after it fired but follow-ups are still pending.
                      await NotificationService.markDone(notifId);
                      _scheduledIds.remove(reminder.id);
                    } else {
                      // User is un-completing — re-schedule if still in future.
                      final scheduledTime = await firestore.getReminderTime(reminder.id);
                      if (scheduledTime != null &&
                          scheduledTime.isAfter(DateTime.now())) {
                        final userName = SettingsProvider.of(context).username;
                        _scheduledIds.add(reminder.id);
                        await NotificationService.scheduleReminder(
                          id: notifId,
                          title: reminder.title,
                          scheduledTime: scheduledTime,
                          userName: userName,
                        );
                      }
                    }
                  },
                ),
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

  // ───────────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────
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
        // DEBUG BUTTON — remove after confirming notifications work
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
              child: CircularProgressIndicator(color: Color(0xFF2D6A4F)),
            );
          }

          final reminders = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final rawTime = data['scheduled_time'] ?? data['time'];

            if (rawTime == null) {
              return Reminder(
                id: doc.id,
                title: data['task'] ?? data['title'] ?? 'No Title',
                time: DateTime.now(),
                isCompleted: data['completed'] ?? false,
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
              id: doc.id,
              title: data['task'] ?? data['title'] ?? 'No Title',
              time: parsedTime,
              isCompleted: data['completed'] ?? false,
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