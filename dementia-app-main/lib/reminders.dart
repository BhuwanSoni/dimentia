import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'settings_provider.dart';
import 'dart:math';

class Reminder {
  final String id;
  final String title;
  final DateTime time;
  bool isCompleted;

  Reminder({
    required this.id,
    required this.title,
    required this.time,
    this.isCompleted = false,
  });
}

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final List<Reminder> _reminders = [
    Reminder(
        id: '1',
        title: 'Take morning medication',
        time: DateTime.now().add(const Duration(hours: 1))),
    Reminder(
        id: '2',
        title: 'Call the doctor',
        time: DateTime.now().add(const Duration(hours: 4))),
    Reminder(
        id: '3',
        title: 'Water the plants',
        time: DateTime.now().add(const Duration(hours: 1)),
        isCompleted: true),
    Reminder(
        id: '4',
        title: 'Read a book',
        time: DateTime.now().add(const Duration(hours: 6)),
        isCompleted: true),
  ];

  double _calculateProgress() {
    if (_reminders.isEmpty) {
      return 0.0;
    }
    final completedCount = _reminders.where((r) => r.isCompleted).length;
    return completedCount / _reminders.length;
  }

  Future<void> _showAddReminderDialog() async {
    final titleController = TextEditingController();
    DateTime? pickedTime;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  hintText: 'Enter reminder title',
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF26A69A)),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setDialogState) {
                  return OutlinedButton.icon(
                    icon: const Icon(Icons.timer_outlined),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF004D40),
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    ),
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        setDialogState(() {
                          pickedTime = DateTime(
                            DateTime.now().year,
                            DateTime.now().month,
                            DateTime.now().day,
                            time.hour,
                            time.minute,
                          );
                        });
                      }
                    },
                    label: Text(
                      pickedTime == null
                          ? 'Pick a Time'
                          : DateFormat('hh:mm a').format(pickedTime!),
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF26A69A),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (titleController.text.isNotEmpty && pickedTime != null) {
                  setState(() {
                    _reminders.add(
                      Reminder(
                        id: DateTime.now().toString(),
                        title: titleController.text,
                        time: pickedTime!,
                      ),
                    );
                  });
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // --- UI HELPER WIDGETS ---

  Widget _buildSectionHeader(BuildContext context, String title) {
    final settings = SettingsProvider.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 24.0, 20.0, 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: (18 * settings.fontSizeMultiplier).toDouble(),
          fontWeight: FontWeight.bold,
          color: const Color(0xFF004D40),
        ),
      ),
    );
  }

  Widget _buildProgressCircle(BuildContext context, double progress) {
    final settings = SettingsProvider.of(context);
    final percentage = (progress * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 800),
              builder: (context, value, child) {
                return CircularProgressIndicator(
                  value: value,
                  backgroundColor: Colors.teal.shade50,
                  color: const Color(0xFF26A69A),
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                );
              },
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$percentage%',
                style: TextStyle(
                  fontSize: (28 * settings.fontSizeMultiplier).toDouble(),
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF004D40),
                ),
              ),
              Text(
                'Complete',
                style: TextStyle(
                  fontSize: (14 * settings.fontSizeMultiplier).toDouble(),
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(Reminder reminder, {bool isCompletedSection = false}) {
    final settings = SettingsProvider.of(context);
    return Dismissible(
      key: Key(reminder.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        setState(() {
          _reminders.removeWhere((r) => r.id == reminder.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${reminder.title} deleted.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      },
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 8.0, right: 16.0),
          leading: Checkbox(
            value: reminder.isCompleted,
            onChanged: (bool? value) {
              setState(() {
                reminder.isCompleted = value!;
              });
            },
            activeColor: const Color(0xFF26A69A),
            shape: const CircleBorder(),
          ),
          title: Text(
            reminder.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: (16 * settings.fontSizeMultiplier).toDouble(),
              decoration: reminder.isCompleted
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              color: reminder.isCompleted ? Colors.grey[500] : Colors.black87,
            ),
          ),
          subtitle: Text(
            DateFormat('hh:mm a').format(reminder.time),
            style: TextStyle(
              fontSize: (14 * settings.fontSizeMultiplier).toDouble(),
              color: reminder.isCompleted ? Colors.grey[400] : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);
    final progress = _calculateProgress();

    final upcomingReminders = _reminders.where((r) => !r.isCompleted).toList();
    upcomingReminders.sort((a, b) => a.time.compareTo(b.time));

    final completedReminders = _reminders.where((r) => r.isCompleted).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Reminders',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Raleway',
                fontSize: (20 * settings.fontSizeMultiplier).toDouble(),
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildProgressCircle(context, progress),
          ),
          if (_reminders.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      "All done for today!\nTap the '+' to add a new reminder.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _buildSectionHeader(context, 'Upcoming')),
            if (upcomingReminders.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                  child: Text(
                    'No pending reminders. Great job!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildReminderCard(upcomingReminders[index]),
                  childCount: upcomingReminders.length,
                ),
              ),
            if (completedReminders.isNotEmpty) ...[
              SliverToBoxAdapter(
                  child: _buildSectionHeader(context, 'Completed')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildReminderCard(completedReminders[index], isCompletedSection: true),
                  childCount: completedReminders.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ]
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddReminderDialog,
        backgroundColor: const Color(0xFF26A69A),
        tooltip: 'Add Reminder',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}