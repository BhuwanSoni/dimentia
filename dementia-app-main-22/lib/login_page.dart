import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'signup_page.dart';
import 'auth_service.dart';
import 'settings_provider.dart';
import 'l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Design tokens ────────────────────────────────────────────────────────
  static const _forest = Color(0xFF1A4D3C);
  static const _sage = Color(0xFF2F7E6D);
  static const _mint = Color(0xFF4CAF8C);
  static const _cream = Color(0xFFF5F0E8);
  static const _cardWhite = Color(0xFFFFFFFF);
  static const _textDark = Color(0xFF1A2E28);
  static const _textMid = Color(0xFF4A6660);
  static const _textLight = Color(0xFF8CA9A3);
  static const _errorRed = Color(0xFFD64045);
  static const _warningAmber = Color(0xFFE07B39);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutCubic),
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🔐 EMAIL LOGIN
  // ─────────────────────────────────────────────────────────────────────────
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
      _showSnackBar(message, _errorRed);
    } catch (e) {
      debugPrint("UNEXPECTED LOGIN ERROR: $e");
      _showSnackBar("Something went wrong. Please try again", _errorRed);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🔥 GOOGLE SIGN-IN
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    setState(() => isLoading = true);
    try {
      final user = await AuthService.signInWithGoogle();
      if (user == null && mounted) {
        _showSnackBar("Google Sign-In cancelled", _warningAmber);
      }
    } catch (e) {
      debugPrint("GOOGLE SIGN-IN ERROR: $e");
      if (mounted) _showSnackBar("Google Sign-In failed", _errorRed);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🔁 RESET PASSWORD
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar("Please enter your email address above first", _warningAmber);
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      _showSnackBar("Please enter a valid email address", _warningAmber);
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
            _warningAmber,
            duration: const Duration(seconds: 5),
          );
        }
        return;
      }
      await _auth.sendPasswordResetEmail(email: email);
      debugPrint("✅ Password reset email dispatched to: $email");
      if (mounted) _showResetSuccessDialog(email);
    } on FirebaseAuthException catch (e) {
      debugPrint("🔴 FirebaseAuthException — code: ${e.code} | msg: ${e.message}");
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = "No account found for '$email'. Please check the spelling or sign up first.";
          break;
        case 'invalid-email':
          message = "The email address format is not valid";
          break;
        case 'too-many-requests':
          message = "Too many reset requests. Please wait a few minutes and try again";
          break;
        case 'network-request-failed':
          message = "No internet connection. Check your network and retry";
          break;
        default:
          message = "Could not send reset email (${e.code}). Please try again";
      }
      if (mounted) {
        _showSnackBar(message, _errorRed, duration: const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint("🔴 Unexpected reset error: $e");
      if (mounted) {
        _showSnackBar("Unexpected error. Check your internet and try again", _errorRed);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🎉 RESET SUCCESS DIALOG
  // ─────────────────────────────────────────────────────────────────────────
  void _showResetSuccessDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _cardWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_forest, _sage],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _sage.withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.mark_email_read_rounded,
                  size: 38, color: Colors.white),
            ),
            const SizedBox(height: 22),
            const Text(
              "Email Sent!",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _textDark,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "A password reset link was sent to:\n$email",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _textMid,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFE0C2), width: 1),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("📌 Can't find it?",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF92400E))),
                  SizedBox(height: 8),
                  Text("• Check your Spam / Junk folder",
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.6)),
                  Text("• Check Promotions tab (Gmail users)",
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.6)),
                  Text("• Email may take 1–2 minutes to arrive",
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.6)),
                  Text("• Sender will be: noreply@*.firebaseapp.com",
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.6)),
                  Text("• Link expires in 1 hour — act quickly!",
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.6)),
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
                  backgroundColor: _sage,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Got it",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: floating snackbar
  // ─────────────────────────────────────────────────────────────────────────
  void _showSnackBar(String message, Color color,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: color,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: styled input decoration
  // ─────────────────────────────────────────────────────────────────────────
  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _textLight, fontSize: 15),
      prefixIcon: Icon(prefixIcon, color: _sage, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _cardWhite,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _sage, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _errorRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _errorRed, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = SettingsProvider.of(context);

    return Scaffold(
      backgroundColor: _cream,
      body: Stack(
        children: [
          // ── Decorative background blobs ──────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _mint.withOpacity(0.18),
                    _mint.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _forest.withOpacity(0.10),
                    _forest.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // ── Main scrollable content ──────────────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 100),

                      // ── Logo + app name ───────────────────────────
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            width: 72,
                            height: 72,
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Memoir',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: _forest,
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                'Memory Companion',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _textMid,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ── Title ─────────────────────────────────────
                      Text(
                        l10n.login,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Welcome back",
                        style: TextStyle(
                          fontSize: 15,
                          color: _textMid,
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ── Email field ───────────────────────────────
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        style: const TextStyle(color: _textDark, fontSize: 15),
                        decoration: _inputDecoration(
                          hint: l10n.email,
                          prefixIcon: Icons.email_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.pleaseEnterEmail;
                          }
                          if (!value.contains("@")) {
                            return l10n.enterValidEmail;
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // ── Password field ────────────────────────────
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        style: const TextStyle(color: _textDark, fontSize: 15),
                        decoration: _inputDecoration(
                          hint: l10n.password,
                          prefixIcon: Icons.lock_outline_rounded,
                          suffix: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: _textLight,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => obscurePassword = !obscurePassword),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? l10n.pleaseEnterPassword
                            : null,
                      ),

                      // ── Forgot password ───────────────────────────
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isLoading ? null : resetPassword,
                          style: TextButton.styleFrom(
                            foregroundColor: _sage,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                          ),
                          child: Text(
                            l10n.forgotPassword,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ── Login button ──────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sage,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isLoading ? null : loginUser,
                          child: isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  l10n.login,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Divider ───────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: Colors.grey.shade300, thickness: 1)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              "or",
                              style: TextStyle(
                                  color: _textLight,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          Expanded(
                              child: Divider(
                                  color: Colors.grey.shade300, thickness: 1)),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ── Google Sign-In button ─────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: isLoading ? null : signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _cardWhite,
                            side: BorderSide(
                                color: Colors.grey.shade300, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network(
                                'https://cdn-icons-png.flaticon.com/512/2991/2991148.png',
                                height: 22,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                l10n.signInWithGoogle,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _textDark,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 36),

                      // ── Sign up link ──────────────────────────────
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SignupPage()),
                            );
                          },
                          style: TextButton.styleFrom(
                              foregroundColor: _sage),
                          child: Text(
                            l10n.dontHaveAccount,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Language switcher overlay ────────────────────────────────
          Positioned(
            top: 48,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: _cardWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: DropdownButton<String>(
                value: settings.languageCode,
                underline: const SizedBox(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: _textMid),
                style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
                items: const [
                  DropdownMenuItem(value: "en", child: Text("EN")),
                  DropdownMenuItem(value: "hi", child: Text("हिंदी")),
                ],
                onChanged: (value) {
                  if (value != null) settings.updateLanguage(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}