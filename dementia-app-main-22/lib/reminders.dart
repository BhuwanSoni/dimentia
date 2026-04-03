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
 
  // ─── BUG FIX 1 ─────────────────────────────────────────────────────────────
  // Previously returned Future<void>. We need the DocumentReference back so
  // that the caller can derive a stable notification ID from docRef.id.
  // Without this, the schedule and cancel IDs never matched.
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
  // ───────────────────────────────────────────────────────────────────────────
 
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
 
  // ─── BUG FIX 1 (continued) ─────────────────────────────────────────────────
  // This is the ONLY function that must be used to compute the notification ID,
  // for both scheduling and cancelling. Using any other ID source (e.g.,
  // DateTime.now().millisecondsSinceEpoch) means cancel can never find the
  // notification that was scheduled.
  int _notificationIdFromDocId(String docId) {
    return docId.hashCode.abs() % 2147483647;
  }
  // ───────────────────────────────────────────────────────────────────────────
 
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF2D6A4F), width: 2),
                      ),
                    ),
                  ),
 
                  const SizedBox(height: 14),
 
                  // Date picker
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF2D6A4F),
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (date != null) {
                        setDialogState(() => pickedDate = date);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2D6A4F)),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF2D6A4F).withOpacity(0.05),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: Color(0xFF2D6A4F)),
                          const SizedBox(width: 10),
                          Text(
                            pickedDate == null
                                ? 'Pick Date'
                                : DateFormat('EEE, MMM d').format(pickedDate!),
                            style: TextStyle(
                              color: pickedDate == null
                                  ? Colors.grey
                                  : const Color(0xFF2D6A4F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
 
                  const SizedBox(height: 14),
 
                  // Time picker
                  InkWell(
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF2D6A4F),
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (time != null) {
                        setDialogState(() => pickedTime = time);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2D6A4F)),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF2D6A4F).withOpacity(0.05),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time,
                              color: Color(0xFF2D6A4F)),
                          const SizedBox(width: 10),
                          Text(
                            pickedTime == null
                                ? 'Pick Time'
                                : pickedTime!.format(context),
                            style: TextStyle(
                              color: pickedTime == null
                                  ? Colors.grey
                                  : const Color(0xFF2D6A4F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (titleController.text.isEmpty || pickedTime == null) {
                      return;
                    }
 
                    final text = titleController.text.trim();
                    final date = pickedDate ?? DateTime.now();
                    final time = pickedTime!;
 
                    DateTime finalDateTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
 
                    // Clamp to future (notification_service also does this,
                    // but we do it here first so Firestore gets the right time)
                    if (finalDateTime.isBefore(DateTime.now())) {
                      finalDateTime =
                          DateTime.now().add(const Duration(seconds: 30));
                    }
 
                    // ─── BUG FIX 2 ─────────────────────────────────────────
                    // Read settings BEFORE Navigator.pop(). After the dialog
                    // is popped its context is unmounted. Calling
                    // SettingsProvider.of(context) on an unmounted context
                    // throws or silently returns stale/null data, causing
                    // scheduleReminder() to be called with the wrong userName
                    // or not at all.
                    final userName = SettingsProvider.of(context).username;
                    // ───────────────────────────────────────────────────────
 
                    Navigator.pop(context);
 
                    // ─── BUG FIX 1 (core fix) ──────────────────────────────
                    // Save to Firestore first and capture the DocumentReference.
                    // The Firestore doc ID is stable across app restarts and
                    // is the only reliable source for a consistent notif ID.
                    //
                    // Previously:
                    //   await firestore.addReminder(text, finalDateTime);
                    //   final id = DateTime.now().millisecondsSinceEpoch % 100000;
                    //     ↑ random timestamp → cancel can never find this ID
                    //
                    // Now:
                    final docRef =
                        await firestore.addReminder(text, finalDateTime);
                    final notifId = _notificationIdFromDocId(docRef.id);
                    //     ↑ same hash used in _deleteReminder → IDs always match
                    // ───────────────────────────────────────────────────────
 
                    await NotificationService.scheduleReminder(
                      id: notifId,
                      title: text,
                      scheduledTime: finalDateTime,
                      userName: userName,
                    );
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
    // Uses the same _notificationIdFromDocId() as scheduling — IDs now match.
    await NotificationService.cancelReminder(
      _notificationIdFromDocId(reminder.id),
    );
    await firestore.deleteReminder(reminder.id);
  }
 
  // ───────────────────────────────────────────────────────────────────────────
  // REMINDER CARD
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildReminderCard(Reminder reminder) {
    final settings = SettingsProvider.of(context);
 
    IconData cardIcon;
    final t = reminder.title.toLowerCase();
    if (t.contains('dawa') ||
        t.contains('medicine') ||
        t.contains('tablet') ||
        t.contains('pill')) {
      cardIcon = Icons.medication;
    } else if (t.contains('doctor') || t.contains('hospital')) {
      cardIcon = Icons.local_hospital;
    } else if (t.contains('eat') ||
        t.contains('food') ||
        t.contains('khana')) {
      cardIcon = Icons.restaurant;
    } else {
      cardIcon = Icons.notifications_active_rounded;
    }
 
    final bool isOverdue =
        !reminder.isCompleted && reminder.time.isBefore(DateTime.now());
 
    final String dayLabel = _dayLabel(reminder.time);
    final String timeLabel = DateFormat('hh:mm a').format(reminder.time);
    final String fullLabel = '$dayLabel • $timeLabel';
 
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: reminder.isCompleted
            ? Colors.grey.shade100
            : isOverdue
                ? Colors.red.shade50
                : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isOverdue
            ? Border.all(color: Colors.red.shade200, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon bubble
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: reminder.isCompleted
                  ? Colors.grey.shade300
                  : isOverdue
                      ? Colors.red.shade100
                      : const Color(0xFF2D6A4F).withOpacity(0.1),
              shape: BoxShape.circle,
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
        // ─── DEBUG BUTTON ─────────────────────────────────────────────────────
        // Remove this action after confirming notifications work.
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug pending notifications',
            onPressed: () async {
              await NotificationService.debugPendingNotifications();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Check debug console for pending notifications'),
                  ),
                );
              }
            },
          ),
        ],
        // ─────────────────────────────────────────────────────────────────────
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
              parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
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