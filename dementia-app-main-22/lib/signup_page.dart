import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'settings_provider.dart'; // 🔥 ADDED
import 'l10n/app_localizations.dart'; // 🔥 ADDED

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> signUpUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await userCredential.user!.updateDisplayName(nameController.text.trim());
      await userCredential.user!.reload();

      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!; // 🔥 ADDED

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.accountCreatedSuccess), // 🔥 localized
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!; // 🔥 ADDED

      String message = l10n.signupFailed; // 🔥 localized

      if (e.code == 'email-already-in-use') {
        message = l10n.emailAlreadyRegistered; // 🔥 localized
      } else if (e.code == 'invalid-email') {
        message = l10n.invalidEmailAddress; // 🔥 localized
      } else if (e.code == 'weak-password') {
        message = l10n.passwordTooWeak; // 🔥 localized
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!; // 🔥 ADDED
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.somethingWentWrong), // 🔥 localized
          backgroundColor: Colors.red,
        ),
      );
    }

    if (mounted) setState(() => isLoading = false);
  }

  @override
  void dispose() {
    nameController.dispose();
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
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),

        /// 🔥 LANGUAGE BUTTON in appBar actions (matches login page style)
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
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
                if (value != null) settings.updateLanguage(value);
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              Text(
                l10n.createAccount, // 🔥 localized
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2F7E6D),
                ),
              ),

              const SizedBox(height: 10),

              Text(
                l10n.signUpToContinue, // 🔥 localized
                style: const TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 30),

              // FULL NAME
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: l10n.fullName, // 🔥 localized
                  prefixIcon:
                      const Icon(Icons.person, color: Color(0xFF2F7E6D)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? l10n.pleaseEnterName // 🔥 localized
                    : null,
              ),

              const SizedBox(height: 20),

              // EMAIL
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(
                  hintText: l10n.email, // 🔥 localized
                  prefixIcon: const Icon(Icons.email, color: Color(0xFF2F7E6D)),
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

              // PASSWORD
              TextFormField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  hintText: l10n.password, // 🔥 localized
                  prefixIcon: const Icon(Icons.lock, color: Color(0xFF2F7E6D)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
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
                validator: (value) => value == null || value.length < 6
                    ? l10n.passwordMinLength // 🔥 localized
                    : null,
              ),

              const SizedBox(height: 30),

              // SIGN UP BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2F7E6D),
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: isLoading ? null : signUpUser,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          l10n.signUp, // 🔥 localized
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 25),

              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  child: Text(
                    l10n.alreadyHaveAccount, // 🔥 localized
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
    );
  }
}
