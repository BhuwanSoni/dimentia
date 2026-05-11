import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// 🔥 SAVE USER DATA
  static Future<void> saveUserData({
    required String name,
    required String emergencyNumber,
  }) async {
    final user = _auth.currentUser;

    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'name': name,
      'email': user.email,
      'emergency_number': emergencyNumber,
    }, SetOptions(merge: true));
  }
}
