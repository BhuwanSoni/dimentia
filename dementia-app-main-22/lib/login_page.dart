import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'signup_page.dart';
import 'auth_service.dart';
import 'settings_provider.dart'; // 🔥 ADDED
import 'l10n/app_localizations.dart'; // 🔥 ADDED

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// ─────────────────────────────────────────────────────────────────────────
  /// 🔐 EMAIL LOGIN
  /// ─────────────────────────────────────────────────────────────────────────
  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint("LOGIN ERROR — code: ${e.code} | msg: ${e.message}");

      String message;
      switch (e.code) {
        case 'user-not-found':
          message = "No account found with this email";
          break;
        case 'wrong-password':
          message = "Incorrect password";
          break;
        case 'invalid-email':
          message = "Invalid email format";
          break;
        case 'invalid-credential':
          message = "Incorrect email or password";
          break;
        case 'user-disabled':
          message = "This account has been disabled";
          break;
        case 'too-many-requests':
          message = "Too many attempts. Please try again later";
          break;
        default:
          message = "Login failed (${e.code})";
      }

      _showSnackBar(message, Colors.red);
    } catch (e) {
      debugPrint("UNEXPECTED LOGIN ERROR: $e");
      _showSnackBar("Something went wrong. Please try again", Colors.red);
    }

    if (mounted) setState(() => isLoading = false);
  }

  /// ─────────────────────────────────────────────────────────────────────────
  /// 🔥 GOOGLE SIGN-IN
  /// ─────────────────────────────────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    setState(() => isLoading = true);

    try {
      final user = await AuthService.signInWithGoogle();
      if (user == null) {
        _showSnackBar("Google Sign-In cancelled", Colors.orange);
      }
    } catch (e) {
      debugPrint("GOOGLE SIGN-IN ERROR: $e");
      _showSnackBar("Google Sign-In failed", Colors.red);
    }

    if (mounted) setState(() => isLoading = false);
  }

  /// ─────────────────────────────────────────────────────────────────────────
  /// 🔁 RESET PASSWORD
  /// ─────────────────────────────────────────────────────────────────────────
  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      _showSnackBar(
          "Please enter your email address above first", Colors.orange);
      return;
    }

    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      _showSnackBar("Please enter a valid email address", Colors.orange);
      return;
    }

    setState(() => isLoading = true);
    debugPrint("🔁 Attempting password reset for: $email");

    try {
      List<String> signInMethods = [];
      try {
        // ignore: deprecated_member_use
        signInMethods = await _auth.fetchSignInMethodsForEmail(email);
        debugPrint("🔎 Sign-in methods for $email: $signInMethods");
      } catch (fetchError) {
        debugPrint("⚠️ fetchSignInMethodsForEmail skipped: $fetchError");
      }

      if (signInMethods.isNotEmpty && !signInMethods.contains('password')) {
        if (mounted) {
          _showSnackBar(
            "This account uses Google Sign-In. Use 'Sign in with Google' instead — no password to reset.",
            Colors.orange,
            duration: const Duration(seconds: 5),
          );
        }
        if (mounted) setState(() => isLoading = false);
        return;
      }

      await _auth.sendPasswordResetEmail(email: email);
      debugPrint("✅ Password reset email dispatched to: $email");

      if (mounted) _showResetSuccessDialog(email);
    } on FirebaseAuthException catch (e) {
      debugPrint(
          "🔴 FirebaseAuthException — code: ${e.code} | msg: ${e.message}");

      String message;
      switch (e.code) {
        case 'user-not-found':
          message =
              "No account found for '$email'. Please check the spelling or sign up first.";
          break;
        case 'invalid-email':
          message = "The email address format is not valid";
          break;
        case 'too-many-requests':
          message =
              "Too many reset requests. Please wait a few minutes and try again";
          break;
        case 'network-request-failed':
          message = "No internet connection. Check your network and retry";
          break;
        default:
          message = "Could not send reset email (${e.code}). Please try again";
      }

      if (mounted) {
        _showSnackBar(message, Colors.red,
            duration: const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint("🔴 Unexpected reset error: $e");
      if (mounted) {
        _showSnackBar(
            "Unexpected error. Check your internet and try again", Colors.red);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// ─────────────────────────────────────────────────────────────────────────
  /// 🎉 SUCCESS DIALOG
  /// ─────────────────────────────────────────────────────────────────────────
  void _showResetSuccessDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFE7F0ED),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_read_rounded,
                  size: 48, color: Color(0xFF2F7E6D)),
            ),
            const SizedBox(height: 20),
            const Text(
              "Email Sent!",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937)),
            ),
            const SizedBox(height: 12),
            Text(
              "A password reset link was sent to:\n$email",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("📌 Can't find it?",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E))),
                  SizedBox(height: 8),
                  Text("• Check your Spam / Junk folder",
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                  Text("• Check Promotions tab (Gmail users)",
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                  Text("• Email may take 1–2 minutes to arrive",
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                  Text("• Sender will be: noreply@*.firebaseapp.com",
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                  Text("• Link expires in 1 hour — act quickly!",
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F7E6D),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Got it",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ─────────────────────────────────────────────────────────────────────────
  /// Helper: floating snackbar
  /// ─────────────────────────────────────────────────────────────────────────
  void _showSnackBar(String message, Color color,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!; // 🔥 ADDED
    final settings = SettingsProvider.of(context); // 🔥 ADDED

    return Scaffold(
      backgroundColor: const Color(0xFFE7F0ED),

      /// 🔥 WRAPPED WITH STACK to overlay language button — no UI change below
      body: Stack(
        children: [
          /// ── ORIGINAL FULL UI (unchanged) ──────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 80),

                  /// TITLE
                  Text(
                    l10n.login, // 🔥 localized
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F7E6D),
                    ),
                  ),

                  const SizedBox(height: 40),

                  /// EMAIL FIELD
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: l10n.email, // 🔥 localized
                      prefixIcon:
                          const Icon(Icons.email, color: Color(0xFF2F7E6D)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.pleaseEnterEmail; // 🔥 localized
                      }
                      if (!value.contains("@")) {
                        return l10n.enterValidEmail; // 🔥 localized
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  /// PASSWORD FIELD
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      hintText: l10n.password, // 🔥 localized
                      prefixIcon:
                          const Icon(Icons.lock, color: Color(0xFF2F7E6D)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: const Color(0xFF2F7E6D),
                        ),
                        onPressed: () =>
                            setState(() => obscurePassword = !obscurePassword),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? l10n.pleaseEnterPassword // 🔥 localized
                        : null,
                  ),

                  const SizedBox(height: 10),

                  /// FORGOT PASSWORD
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading ? null : resetPassword,
                      child: Text(
                        l10n.forgotPassword, // 🔥 localized
                        style: const TextStyle(color: Color(0xFF2F7E6D)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// LOGIN BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F7E6D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: isLoading ? null : loginUser,
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              l10n.login, // 🔥 localized
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// GOOGLE SIGN-IN BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : signInWithGoogle,
                      icon: Image.network(
                        'https://cdn-icons-png.flaticon.com/512/2991/2991148.png',
                        height: 22,
                      ),
                      label: Text(
                        l10n.signInWithGoogle, // 🔥 localized
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  /// SIGN UP
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignupPage()),
                        );
                      },
                      child: Text(
                        l10n.dontHaveAccount, // 🔥 localized
                        style: const TextStyle(
                          color: Color(0xFF2F7E6D),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          /// ── 🔥 LANGUAGE BUTTON OVERLAY (only addition) ────────────────
          Positioned(
            top: 40,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButton<String>(
                value: settings.languageCode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: "en", child: Text("EN")),
                  DropdownMenuItem(value: "hi", child: Text("हिंदी")),
                ],
                onChanged: (value) {
                  if (value != null) {
                    settings.updateLanguage(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
