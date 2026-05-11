import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get userId => _auth.currentUser!.uid;

  /// ➕ ADD REMINDER
  Future<void> addReminder(String title, DateTime time) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .add({
      'title': title,
      'time': Timestamp.fromDate(time),
      'completed': false,
    });
  }

  /// 📥 GET REMINDERS (REAL-TIME)
  Stream<QuerySnapshot> getReminders() {
    return _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .orderBy('time')
        .snapshots();
  }

  /// ✅ TOGGLE COMPLETE
  Future<void> toggleComplete(String id, bool value) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .update({'completed': value});
  }

  /// ❌ DELETE
  Future<void> deleteReminder(String id) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(id)
        .delete();
  }
}