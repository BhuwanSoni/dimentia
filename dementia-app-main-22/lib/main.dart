import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'home.dart';
import 'settings_provider.dart';
import 'notification_service.dart';
import 'visual_aide_screen.dart';
import 'login_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Save last interaction time
  final prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey('last_interaction_time')) {
    await prefs.setInt(
      'last_interaction_time',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Initialize notifications (must happen before requestPermissions)
  if (!kIsWeb) {
    await NotificationService.init();
  }

  // ─── BUG FIX: Request both notification + exact alarm permission ─────────────
  // requestPermissions() now calls requestExactAlarmsPermission() internally.
  // Without exact alarm permission, zonedSchedule() silently does nothing
  // on Android 12+ devices.
  //
  // IMPORTANT — you must also add to android/app/src/main/AndroidManifest.xml
  // inside <manifest> (NOT inside <application>):
  //
  //   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
  //
  // AND add the flutter_timezone package to pubspec.yaml:
  //   flutter_timezone: ^1.0.8
  //
  // Then update notification_service.dart init() to use:
  //   final tzName = await FlutterTimezone.getLocalTimezone();
  //   tz.setLocalLocation(tz.getLocation(tzName));
  //
  // ─── BATTERY OPTIMISATION (Android) ──────────────────────────────────────────
  // Even with exact alarm permission, some OEM ROMs (Xiaomi MIUI, Samsung One UI,
  // Realme UI, Oppo ColorOS) kill background processes aggressively. The user
  // must manually disable battery optimisation for this app:
  //   Settings → Apps → [Your App] → Battery → Unrestricted
  //
  // You can prompt the user to do this using the battery_plus or
  // disable_battery_optimization package.
  if (!kIsWeb && Platform.isAndroid) {
    await NotificationService.requestPermissions();
  }

  // Handle notification tap (open VisualAideScreen if payload matches)
  NotificationService.onNotificationClick = (payload) {
    if (payload == 'magic_eye_screen') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => const VisualAideScreen(),
        ),
      );
    }
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(SettingsProviderState settings) {
    final baseTheme = settings.isDarkMode
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    if (settings.isHighContrast) {
      return baseTheme.copyWith(
        colorScheme: settings.isDarkMode
            ? const ColorScheme.highContrastDark()
            : const ColorScheme.highContrastLight(),
      );
    }

    return baseTheme;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsProvider(
      child: Builder(
        builder: (context) {
          final settings = SettingsProvider.of(context);

          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,

            onGenerateTitle: (context) =>
                AppLocalizations.of(context)?.appTitle ?? 'Memoir',

            locale: settings.locale,
            supportedLocales: AppLocalizations.supportedLocales,

            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

            theme: _buildTheme(settings).copyWith(
              textTheme: Theme.of(context).textTheme.apply(
                    fontFamily:
                        settings.languageCode == 'hi' ? 'NotoSans' : null,
                  ),
            ),
            themeMode: ThemeMode.light,

            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// _AuthGate — listens to Firebase auth state and routes to Home or Login.
///
/// FIX: _previousUid mutation has been moved OUT of build() into a dedicated
/// _handleAuthChange() method. Mutating state inside build() is unsafe and was
/// causing the uid-change detection to misfire — meaning reloadAfterLogin()
/// never triggered and navigation didn't happen automatically after email login.
/// ─────────────────────────────────────────────────────────────────────────────
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _previousUid;

  /// Called from the StreamBuilder builder — handles side effects safely
  /// outside of the build phase via addPostFrameCallback.
  void _handleAuthChange(User? user) {
    final currentUid = user?.uid;

    // No change — do nothing
    if (currentUid == _previousUid) return;

    _previousUid = currentUid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = SettingsProvider.of(context);
      if (currentUid != null) {
        settings.reloadAfterLogin(); // new user logged in
      } else {
        settings.resetUserData(); // user logged out
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show spinner while Firebase resolves the initial auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ✅ Side effects handled separately — never mutate state inside build()
        _handleAuthChange(snapshot.data);

        // Route based on auth state
        if (snapshot.data != null) return const HomePage();
        return const LoginPage();
      },
    );
  }
}