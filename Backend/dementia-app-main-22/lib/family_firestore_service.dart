import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class FamilyMember {
  /// Firestore document ID — empty string before the first save.
  final String docId;
  final String name;
  final String relation;
  final String phoneNumber;

  /// Remote HTTPS URL stored in Firestore (empty = no photo).
  final String imageUrl;

  final Color color;

  const FamilyMember({
    this.docId = '',
    required this.name,
    required this.relation,
    required this.phoneNumber,
    required this.imageUrl,
    required this.color,
  });

  /// Deserialise from a Firestore [DocumentSnapshot].
  factory FamilyMember.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FamilyMember(
      docId: doc.id,
      name: data['name'] as String? ?? '',
      relation: data['relation'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      color: Color(data['colorValue'] as int? ?? 0xFFE8F5E9),
    );
  }

  /// Serialise to a plain Firestore-compatible map.
  Map<String, dynamic> toFirestore({required String resolvedImageUrl}) => {
        'name': name,
        'relation': relation,
        'phoneNumber': phoneNumber,
        'imageUrl': resolvedImageUrl,
        'colorValue': color.value,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class FamilyFirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Auth guard ─────────────────────────────────────────────────────────────
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    return user.uid;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('users').doc(_uid).collection('family_members');

  /// Storage reference for a member's profile photo.
  Reference _photoRef(String docId) =>
      _storage.ref('users/$_uid/family_photos/$docId.jpg');

  /// Upload [localPath] to Storage and return the public download URL.
  /// Returns an empty string when [localPath] is empty.
  Future<String> _uploadPhoto(String localPath, String docId) async {
    if (localPath.isEmpty) return '';
    final ref = _photoRef(docId);
    await ref.putFile(
      File(localPath),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  /// Delete the Storage photo for [docId] — best-effort, never throws.
  Future<void> _deletePhoto(String docId) async {
    try {
      await _photoRef(docId).delete();
    } catch (_) {
      // Object may not exist (member had no photo) — safe to ignore.
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Add a new family member.
  ///
  /// Workflow:
  ///  1. Write the Firestore document to get an ID.
  ///  2. Upload [localImagePath] to Firebase Storage (if provided).
  ///  3. Patch the document with the permanent download URL.
  ///
  /// The photo URL survives reinstalls and device switches because it is a
  Future<String> addFamilyMember(
    FamilyMember member, {
    String localImagePath = '',
  }) async {
    // Step 1 — create Firestore document first
    final ref = await _col.add({
      ...member.toFirestore(resolvedImageUrl: ''),
      'createdAt': FieldValue.serverTimestamp(),
    });
  
    try {
      // Step 2 — upload image (if provided)
      final imageUrl = await _uploadPhoto(localImagePath, ref.id);
  
      // Step 3 — save final image URL
      if (imageUrl.isNotEmpty) {
        await ref.update({
          'imageUrl': imageUrl,
        });
      }
  
      return ref.id;
    } catch (e) {
      // Cleanup orphan Firestore doc if upload fails
      await ref.delete();
  
      debugPrint('Failed to add family member: $e');
  
      rethrow;
    }
  }

  /// Real-time stream of all family members, ordered by creation time.
  Stream<List<FamilyMember>> getFamilyMembers() {
    return _col.orderBy('createdAt').snapshots().map(
          (snap) => snap.docs.map(FamilyMember.fromDoc).toList(),
        );
  }

  /// Delete a family member and their photo from Storage.
  Future<void> deleteFamilyMember(String docId) async {
    await _deletePhoto(docId);   // best-effort — won't block on missing photo
    await _col.doc(docId).delete();
  }
} 