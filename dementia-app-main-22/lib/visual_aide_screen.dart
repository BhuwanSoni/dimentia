import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ ADDED
import 'settings_provider.dart';

class VisualAideScreen extends StatefulWidget {
  const VisualAideScreen({super.key});

  @override
  State<VisualAideScreen> createState() => _VisualAideScreenState();
}

class _VisualAideScreenState extends State<VisualAideScreen> {
  File? _selectedImage;
  String? _description;
  bool _isLoading = false;
  String _targetLanguage = "English";
  final ImagePicker _picker = ImagePicker();

  Future<void> _identifyObject() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );

      if (photo == null) return;

      setState(() {
        _selectedImage = File(photo.path);
        _isLoading = true;
        _description = null;
      });

      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _description = _targetLanguage == "Hindi"
            ? "यह एक वस्तु है।"
            : "This looks like an object.";
        _isLoading = false;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_interaction_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      setState(() {
        _description = _targetLanguage == "Hindi"
            ? "कुछ समस्या हुई।"
            : "Something went wrong.";
        _isLoading = false;
      });
    }
  }

  // ✅ LOGOUT FUNCTION
  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pop(context);
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);
    final bool isHindi = _targetLanguage == "Hindi";

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: _buildAppBar(isHindi),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 15)
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: _selectedImage == null
                    ? _buildEmptyState()
                    : Image.file(_selectedImage!, fit: BoxFit.cover),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Center(
                child: _isLoading
                    ? _buildLoadingState()
                    : SingleChildScrollView(
                        child: Text(
                          _description ??
                              (isHindi
                                  ? "जानने के लिए बटन दबाएं"
                                  : "Tap the eye to see"),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24 * settings.fontSizeMultiplier,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D6A4F),
                          ),
                        ).animate().fadeIn(),
                      ),
              ),
            ),
          ),
          _buildBigButton(isHindi, settings.fontSizeMultiplier),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(color: Color(0xFF2D6A4F), strokeWidth: 5),
        SizedBox(height: 15),
        Text("Looking...", style: TextStyle(fontSize: 18, color: Colors.grey)),
      ],
    );
  }

  Widget _buildBigButton(bool isHindi, double scale) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GestureDetector(
        onTap: _isLoading ? null : _identifyObject,
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFF2D6A4F),
            borderRadius: BorderRadius.circular(45),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.remove_red_eye, color: Colors.white, size: 40),
              const SizedBox(width: 15),
              Text(
                isHindi ? "यह क्या है?" : "WHAT IS THIS?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ).animate(target: _isLoading ? 0 : 1).scale(duration: 200.ms),
    );
  }

  // ✅ UPDATED APPBAR WITH LOGOUT
  PreferredSizeWidget _buildAppBar(bool isHindi) {
    return AppBar(
      title: Text(isHindi ? "जादुई आँख" : "Magic Eye"),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: () => setState(
            () => _targetLanguage = isHindi ? "English" : "Hindi",
          ),
          child: Text(
            isHindi ? "English" : "हिन्दी",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),

        // ✅ LOGOUT BUTTON
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Icon(
        Icons.camera_alt_outlined,
        size: 100,
        color: Colors.grey[300],
      ),
    );
  }
}
