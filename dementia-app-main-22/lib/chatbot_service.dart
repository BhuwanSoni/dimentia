import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // ✅ for DateFormat

class ChatbotService {
  final String _backendUrl = "https://dimentia.onrender.com/chat";

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ✅ FIX: Removed FirebaseFirestore import and the duplicate Firestore write.
  // The Python backend (generate_response in assistant_service.py) is the single
  // authoritative writer for chat history. Writing from Flutter too caused every
  // reply to appear 2–3 times in Firestore, making get_conversation_history()
  // feed duplicate turns to the LLM and causing confused/looping responses.

  Future<String> sendMessage(String userMessage, {String? profileText}) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        return "User not logged in.";
      }

      final uid = user.uid;

      // ✅ Always send timezone so the backend reminder parser uses IST,
      // not the server's UTC default. This fixes ghost/shifted reminders
      // from both voice and chat code paths.
      //
      // ✅ Send live date/time so the backend can answer "what time is it"
      // and "what day is today" accurately without relying on server UTC.
      final now = DateTime.now();
      final Map<String, dynamic> requestBody = {
        "message":      userMessage,
        "user_id":      uid,
        "timezone":     "Asia/Kolkata",
        "current_time": DateFormat('hh:mm a').format(now),        // e.g. "03:45 PM"
        "current_date": DateFormat('EEEE, MMMM d, yyyy').format(now), // e.g. "Wednesday, May 13, 2026"
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

      final aiReply = data["reply"] ?? "I'm here for you.";

      return aiReply;

    } on SocketException catch (e) {
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