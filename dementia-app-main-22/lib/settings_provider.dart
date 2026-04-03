import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _username = 'User';
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

    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'en';
      _locale = Locale(_languageCode);

      _isReminderSoundEnabled = prefs.getBool('reminder_sound_enabled') ?? true;
      _isVibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _isHighContrast = prefs.getBool('high_contrast') ?? false;

      _username = prefs.getString('username') ?? 'User';
      _emergencyContact = prefs.getString('emergency_contact') ?? '';
      _gender = prefs.getString('gender') ?? '';
      _address = prefs.getString('address') ?? '';

      final birthMillis = prefs.getInt('birthdate');
      _birthdate = birthMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(birthMillis)
          : null;

      _fontSizeMultiplier = prefs.getDouble('font_size') ?? 1.0;
    });
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
