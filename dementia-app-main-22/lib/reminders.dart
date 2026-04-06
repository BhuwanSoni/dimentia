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
  Future<DocumentReference> addReminder(String title, DateTime time) async {
    return await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .add({
      'title': title,
      'time': Timestamp.fromDate(time),
      'completed': false,
    });
  }

  Stream<QuerySnapshot> getReminders() {
    return _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
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

  // Track already-scheduled doc IDs so we don't double-schedule
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

    // Stream listener — catches new reminders added while app is open
    _reminderSub = firestore.getReminders().listen((snapshot) async {
      if (!mounted) return;
      final userName = SettingsProvider.of(context).username;
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final docId = change.doc.id;
        if (_scheduledIds.contains(docId)) continue;

        final data = change.doc.data() as Map<String, dynamic>;
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

        // ✅ FIX: In release builds, a tiny delay between Firestore write and
        // this listener firing can make the time appear to be in the past.
        // NotificationService.scheduleReminder() handles the clamp internally,
        // so we REMOVE the hard skip here and let the service decide.
        // Old code:  if (scheduledTime.isBefore(DateTime.now())) continue;

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

    // ✅ Reschedule all future reminders on every app start.
    // The stream above only catches NEW additions. If the app restarts,
    // all previously scheduled notifications are lost from the OS.
    // This restores them from Firestore on every launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndScheduleExistingReminders();
    });
  }

  // Load and reschedule all future reminders from Firestore
  Future<void> _loadAndScheduleExistingReminders() async {
    final snapshot = await firestore.getReminders().first;
    if (!mounted) return;

    final userName = SettingsProvider.of(context).username;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

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

      // Skip ones the stream already scheduled this session
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

                    // Save to Firestore
                    final docRef =
                        await firestore.addReminder(title, scheduledTime);

                    // Schedule notification using the Firestore doc ID
                    final userName =
                        SettingsProvider.of(context).username;
                    final notifId = _notificationIdFromDocId(docRef.id);
                    _scheduledIds.add(docRef.id);

                    await NotificationService.scheduleReminder(
                      id: notifId,
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
    await NotificationService.cancelReminder(
        _notificationIdFromDocId(reminder.id));
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
                    await firestore.toggleComplete(
                        reminder.id, !reminder.isCompleted);
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