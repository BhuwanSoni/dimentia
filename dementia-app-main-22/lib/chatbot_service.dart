import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatbotService {
  final String _backendUrl = "https://your-backend-url.onrender.com/chat";

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 CHANGED: Added optional profileText parameter
  Future<String> sendMessage(String userMessage, {String? profileText}) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        return "User not logged in.";
      }

      final uid = user.uid;

      // 🔥 CHANGED: Include profile_text in request body if provided
      final Map<String, dynamic> requestBody = {
        "message": userMessage,
        "user_id": uid,
        if (profileText != null && profileText.isNotEmpty)
          "profile_text": profileText,
      };

      // ✅ Added timeout so app doesn't hang
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      // ✅ Always log for debugging
      print("📡 STATUS CODE: ${response.statusCode}");
      print("📡 BODY: ${response.body}");

      if (response.statusCode != 200) {
        // ✅ Show actual server error instead of generic message
        print("❌ Server error ${response.statusCode}: ${response.body}");
        return "Server error (${response.statusCode}). Check backend logs.";
      }

      // ✅ Safe JSON decode with error handling
      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        print("❌ JSON decode failed: $e\nBody was: ${response.body}");
        return "Got a bad response from server.";
      }

      final aiReply   = data["reply"]      ?? "I'm here for you.";
      final riskLevel = data["risk_level"] ?? "Unknown";

      // ✅ Store chat history
      await _firestore
          .collection("users")
          .doc(uid)
          .collection("chats")
          .add({
        "user_message": userMessage,
        "ai_reply":     aiReply,
        "risk_level":   riskLevel,
        "timestamp":    FieldValue.serverTimestamp(),
      });

      return aiReply;

    } on SocketException catch (e) {
      // No internet or server not reachable
      print("❌ SocketException: $e");
      return "Cannot reach server. Is your backend running at $_backendUrl?";

    } on TimeoutException catch (e) {
      print("❌ Timeout: $e");
      return "Server took too long to respond. Try again.";

    } catch (e) {
      print("❌ ERROR FROM CHAT SERVICE: $e");
      return "Something went wrong: $e";
    }
  }
}