import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _SettingsInherited extends InheritedWidget {
  const _SettingsInherited({
    required this.data,
    required super.child,
  });

  final SettingsProviderState data;

  @override
  bool updateShouldNotify(_SettingsInherited oldWidget) {
    return true; // 🔥 FORCE FULL REBUILD (IMPORTANT)
  }
}

class SettingsProvider extends StatefulWidget {
  const SettingsProvider({required this.child, super.key});

  final Widget child;

  static SettingsProviderState of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<_SettingsInherited>();
    assert(result != null, 'No SettingsProvider found in context');
    return result!.data;
  }

  @override
  State<SettingsProvider> createState() => SettingsProviderState();
}

class SettingsProviderState extends State<SettingsProvider> {
  /// ===== BASIC SETTINGS =====
  String _languageCode = 'en';
  Locale _locale = const Locale('en');

  bool _isReminderSoundEnabled = true;
  bool _isVibrationEnabled = true;
  bool _isDarkMode = false;
  bool _isHighContrast = false;

  /// ===== USER DATA =====
  String _username = '';
  String _emergencyContact = '';
  String _gender = '';
  String _address = '';
  DateTime? _birthdate;

  /// ===== UI SETTINGS =====
  double _fontSizeMultiplier = 1.0;

  /// ===== GETTERS =====
  String get languageCode => _languageCode;
  Locale get locale => _locale;

  bool get isReminderSoundEnabled => _isReminderSoundEnabled;
  bool get isVibrationEnabled => _isVibrationEnabled;
  bool get isDarkMode => _isDarkMode;
  bool get isHighContrast => _isHighContrast;

  String get username => _username;
  String get emergencyContact => _emergencyContact;
  String get gender => _gender;
  String get address => _address;
  DateTime? get birthdate => _birthdate;

  double get fontSizeMultiplier => _fontSizeMultiplier;

  /// 🔥 AGE CALCULATION
  int get age {
    if (_birthdate == null) return 0;

    final today = DateTime.now();
    int age = today.year - _birthdate!.year;

    if (today.month < _birthdate!.month ||
        (today.month == _birthdate!.month && today.day < _birthdate!.day)) {
      age--;
    }
    return age;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// ===== LOAD SETTINGS =====
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load non-user preferences from SharedPreferences first
    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'en';
      _locale = Locale(_languageCode);
      _isReminderSoundEnabled = prefs.getBool('reminder_sound_enabled') ?? true;
      _isVibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _isHighContrast = prefs.getBool('high_contrast') ?? false;
      _fontSizeMultiplier = prefs.getDouble('font_size') ?? 1.0;
    });

    // 🔥 Always load user data fresh from Firestore on every login
    await _loadUserFromFirestore();
  }

  /// 🔥 Load user profile from Firestore (always fresh, no stale cache)
  Future<void> _loadUserFromFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();

      // Try Firestore first, fall back to Firebase Auth displayName
      final firestoreName = data?['username'] as String?;
      final authName = user.displayName;
      final resolvedName = (firestoreName != null && firestoreName.trim().isNotEmpty)
          ? firestoreName.trim()
          : (authName != null && authName.trim().isNotEmpty)
              ? authName.trim()
              : '';

      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _username = resolvedName;
        _emergencyContact = data?['emergency_contact'] as String? ?? prefs.getString('emergency_contact') ?? '';
        _gender = data?['gender'] as String? ?? prefs.getString('gender') ?? '';
        _address = data?['address'] as String? ?? prefs.getString('address') ?? '';

        final birthMillis = data?['birthdate'] as int? ?? prefs.getInt('birthdate');
        _birthdate = birthMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(birthMillis)
            : null;
      });

      // Cache the resolved name locally for offline use
      if (resolvedName.isNotEmpty) {
        await prefs.setString('username', resolvedName);
      }
    } catch (e) {
      // Firestore failed — fall back to SharedPreferences cache
      debugPrint('Firestore load failed, using cache: $e');
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _username = prefs.getString('username') ?? '';
        _emergencyContact = prefs.getString('emergency_contact') ?? '';
        _gender = prefs.getString('gender') ?? '';
        _address = prefs.getString('address') ?? '';

        final birthMillis = prefs.getInt('birthdate');
        _birthdate = birthMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(birthMillis)
            : null;
      });
    }
  }

  /// 🔥 Call this on logout to wipe stale user data
  Future<void> resetUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('emergency_contact');
    await prefs.remove('gender');
    await prefs.remove('address');
    await prefs.remove('birthdate');

    setState(() {
      _username = '';
      _emergencyContact = '';
      _gender = '';
      _address = '';
      _birthdate = null;
    });
  }

  /// 🔥 Call this after login to reload fresh data
  Future<void> reloadAfterLogin() async {
    await _loadUserFromFirestore();
  }

  /// ===== LANGUAGE (🔥 MAIN FIX) =====
  Future<void> updateLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('language_code', value);

    setState(() {
      _languageCode = value;
      _locale = Locale(value);
    });
  }

  /// ===== TOGGLES =====
  Future<void> toggleReminderSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminder_sound_enabled', value);

    setState(() => _isReminderSoundEnabled = value);
  }

  Future<void> toggleVibration(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_enabled', value);

    setState(() => _isVibrationEnabled = value);
  }

  Future<void> toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);

    setState(() => _isDarkMode = value);
  }

  Future<void> toggleHighContrast(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('high_contrast', value);

    setState(() => _isHighContrast = value);
  }

  /// ===== USER DATA =====
  Future<void> updateUsername(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', trimmed);

    // 🔥 Also save to Firestore so it persists across devices/logins
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'username': trimmed}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Failed to save username to Firestore: $e');
    }

    setState(() => _username = trimmed);
  }

  Future<void> updateEmergencyContact(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emergency_contact', value);

    setState(() => _emergencyContact = value);
  }

  Future<void> updateGender(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gender', value);

    setState(() => _gender = value);
  }

  Future<void> updateAddress(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('address', value);

    setState(() => _address = value);
  }

  Future<void> updateBirthdate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('birthdate', date.millisecondsSinceEpoch);

    setState(() => _birthdate = date);
  }

  /// ===== FONT SIZE =====
  Future<void> updateFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_size', value);

    setState(() => _fontSizeMultiplier = value);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsInherited(
      data: this,
      child: widget.child,
    );
  }
}
