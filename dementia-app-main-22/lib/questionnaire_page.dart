import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────
//  DESIGN TOKENS
// ─────────────────────────────────────────────────────────────
const Color _kGreen     = Color(0xFF2D6A4F);
const Color _kTeal      = Color(0xFF26A69A);
const Color _kDarkGreen = Color(0xFF004D40);
const Color _kBg        = Color(0xFFF4F6F5);
const Color _kCard      = Colors.white;
const Color _kSubText   = Color(0xFF78909C);

const _kHeaderGradient = LinearGradient(colors: [_kGreen, _kTeal]);

// ─────────────────────────────────────────────────────────────
//  QUESTIONNAIRE PAGE
// ─────────────────────────────────────────────────────────────
class QuestionnairePage extends StatefulWidget {
  const QuestionnairePage({super.key});

  @override
  State<QuestionnairePage> createState() => _QuestionnairePageState();
}

class _QuestionnairePageState extends State<QuestionnairePage>
    with TickerProviderStateMixin {

  // ── Profile ──────────────────────────────────────────────
  final TextEditingController ageController      = TextEditingController();
  final TextEditingController eduYearsController = TextEditingController();

  // BUG FIX #2 – Gender encoding
  // The ML model was trained with 0 = Male, 1 = Female.
  // Default is Male → gender = 0.
  // Previously the default was gender = 1 (Male), which sent "1" to the
  // model and was interpreted as Female, flipping every Male result.
  int gender    = 0; // 0 = Male, 1 = Female
  int ses       = 2;
  int education = 5;
  bool profileCompleted = false;
  bool _ageError = false;

  // BUG FIX #1 – Double-submit guard
  // Prevents _calculateScore() from being called a second time while the
  // first API call is still in-flight (which created duplicate Firestore
  // entries visible in Test History).
  bool _isSubmitting = false;

  // ── Questions ────────────────────────────────────────────
  final List<Map<String, dynamic>> questions = [
    {"text": "Do you forget recent conversations or events?",   "icon": Icons.forum_outlined},
    {"text": "Do you sometimes forget what day or time it is?", "icon": Icons.schedule_outlined},
    {"text": "Do you get confused about where you are?",        "icon": Icons.location_on_outlined},
    {"text": "Do you have difficulty completing daily tasks?",  "icon": Icons.checklist_outlined},
    {"text": "Do you struggle to find the right words?",        "icon": Icons.chat_bubble_outline},
    {"text": "Do you frequently misplace items?",               "icon": Icons.search_outlined},
    {"text": "Do you have trouble concentrating?",              "icon": Icons.psychology_outlined},
    {"text": "Do you experience sudden mood changes?",          "icon": Icons.mood_outlined},
    {"text": "Do you get lost in familiar places?",             "icon": Icons.map_outlined},
    {"text": "Do you have difficulty making simple decisions?", "icon": Icons.help_outline},
  ];

  final List<int> answers = List.filled(10, -1);
  int currentQuestion = 0;

  final List<Map<String, dynamic>> options = [
    {"label": "Never",     "value": 0},
    {"label": "Sometimes", "value": 1},
    {"label": "Often",     "value": 2},
    {"label": "Always",    "value": 3},
  ];

  // ── Animations ───────────────────────────────────────────
  late AnimationController _slideCtrl;
  late AnimationController _fadeCtrl;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _fadeCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _slideAnim = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn));
    _playEntrance();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _fadeCtrl.dispose();
    ageController.dispose();
    eduYearsController.dispose();
    super.dispose();
  }

  void _playEntrance() {
    _slideCtrl.forward(from: 0);
    _fadeCtrl.forward(from: 0);
  }

  // ── Info bottom sheet ─────────────────────────────────────
  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.info_outline_rounded,
                        color: _kGreen, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "How to Fill the Form",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kDarkGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _InfoDivider(label: "AGE"),
              const SizedBox(height: 10),
              const _InfoRow(icon: Icons.cake_outlined,
                  text: "Enter your current age in years."),
              const _InfoRow(icon: Icons.check_circle_outline,
                  text: "Valid range: 10 to 120 years."),
              const _InfoRow(
                icon: Icons.warning_amber_rounded,
                text: "Example: if you are 65, enter 65.",
                highlight: true,
              ),
              const SizedBox(height: 20),
              const _InfoDivider(label: "YEARS OF EDUCATION"),
              const SizedBox(height: 10),
              const _InfoRow(
                icon: Icons.school_outlined,
                text: "Enter the total number of years you spent in formal education.",
              ),
              const SizedBox(height: 8),
              const _EduTable(),
              const SizedBox(height: 20),
              const _InfoDivider(label: "ABOUT THE TEST"),
              const SizedBox(height: 10),
              const _InfoRow(
                icon: Icons.psychology_outlined,
                text: "This test screens for early signs of cognitive impairment.",
              ),
              const _InfoRow(icon: Icons.timer_outlined,
                  text: "Takes about 3–5 minutes to complete."),
              const _InfoRow(icon: Icons.lock_outline,
                  text: "Your data is private and securely stored."),
              const _InfoRow(
                icon: Icons.medical_information_outlined,
                text: "Results are indicative only — not a medical diagnosis.",
                highlight: true,
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_kGreen, _kTeal]),
                    borderRadius: BorderRadius.circular(35),
                    boxShadow: [
                      BoxShadow(
                        color: _kGreen.withOpacity(0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text("Got it!",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void resetTest() {
    setState(() {
      answers.fillRange(0, answers.length, -1);
      currentQuestion  = 0;
      profileCompleted = false;
      ageController.clear();
      eduYearsController.clear();
      gender    = 0; // BUG FIX #2 – reset to correct default (0 = Male)
      ses       = 2;
      education = 5;
    });
    _playEntrance();
  }

  void nextQuestion() {
    if (answers[currentQuestion] == -1) return;
    if (currentQuestion < questions.length - 1) {
      setState(() => currentQuestion++);
      _playEntrance();
    } else {
      _calculateScore();
    }
  }

  // ── API call + Firestore save ─────────────────────────────
  Future<void> _calculateScore() async {
    // BUG FIX #1 – Double-submit guard
    // Without this, tapping "See My Results" twice (or a slow network causing
    // the user to tap again) fired two API calls, and because the server
    // also writes to Firestore on each call, every test was stored TWICE.
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          width: 130, height: 130,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _kGreen),
              SizedBox(height: 14),
              Text("Analysing…",
                  style: TextStyle(color: _kDarkGreen, fontSize: 13)),
            ],
          ),
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final int rawScore = answers.reduce((a, b) => a + b);
      final int mmse     = 30 - rawScore;

      // BUG FIX #2 – Gender encoding
      // gender == 0 means Male, gender == 1 means Female.
      // This now matches the ML model's training encoding (0=Male, 1=Female).
      final response = await http.post(
        Uri.parse("https://dimentia.onrender.com/predict"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": user.uid,
          "questionnaire": {
            "AGE":                int.parse(ageController.text),
            "GENDER":             gender,   // 0 = Male, 1 = Female
            "YEARS_OF_EDUCATION": int.parse(eduYearsController.text),
            "SES":                ses,
            "EDUCATION":          education,
            "MMSE":               mmse,
          }
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Server error (${response.statusCode})");
      }

      final data = jsonDecode(response.body);
      if (data.containsKey("error")) {
        throw Exception("Prediction error: ${data["error"]}");
      }

      final int    percentage = (data["probability"] * 100).toInt();
      final String riskLevel  = data["risk_level"];

      // BUG FIX #1 – DO NOT write predictions to Firestore here.
      // The server (prediction_service.py) is now the single writer.
      // Writing here as well was the root cause of every test appearing
      // twice in Test History.
      //
      // We still update the top-level user document for quick-access fields
      // (profile info only — no prediction subcollection write).
      final String nowIso = DateTime.now().toIso8601String();
      final userRef = FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid);

      await userRef.set({
        "AGE":                int.parse(ageController.text),
        "GENDER":             gender,
        "YEARS_OF_EDUCATION": int.parse(eduYearsController.text),
        "SES":                ses,
        "EDUCATION":          education,
        "MMSE":               mmse,
        "probability":        data["probability"],
        "last_test":          nowIso,
      }, SetOptions(merge: true));

      // ── REMOVED: userRef.collection("predictions").add({…})
      // That duplicate write has been deleted. The server already saved
      // the prediction document inside predict_and_store().

      if (mounted) Navigator.pop(context); // dismiss loading dialog

      if (!mounted) return;

      final takeAgain = await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (_, a1, a2) =>
              ResultPage(percentage: percentage, riskLevel: riskLevel),
          transitionsBuilder: (_, a1, __, child) =>
              FadeTransition(opacity: a1, child: child),
          transitionDuration: const Duration(milliseconds: 450),
        ),
      );

      if (!mounted) return;

      if (takeAgain == true) {
        resetTest();
      } else {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a1, a2) => const TestHistoryPage(),
            transitionsBuilder: (_, a1, __, child) =>
                FadeTransition(opacity: a1, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }

    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _kDarkGreen,
            content: Text("Error: $e",
                style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      // Always release the guard so the user can retry after an error
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      floatingActionButton: !profileCompleted
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TestHistoryPage()),
              ),
              backgroundColor: _kGreen,
              elevation: 6,
              icon: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
              label: const Text(
                "History",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: profileCompleted
                  ? _buildTestBody()
                  : _buildProfileBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────
  Widget _buildHeader() {
    final double progress =
        profileCompleted ? (currentQuestion + 1) / questions.length : 0;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: _kHeaderGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    if (profileCompleted && currentQuestion > 0) {
                      setState(() => currentQuestion--);
                      _playEntrance();
                    } else if (profileCompleted) {
                      setState(() => profileCompleted = false);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Cognitive Test",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        profileCompleted
                            ? "Question ${currentQuestion + 1} of ${questions.length}"
                            : "Patient Profile",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showInfoSheet,
                  child: Container(
                    width: 44, height: 44,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: const Icon(Icons.info_outline_rounded,
                        size: 22, color: _kGreen),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          if (profileCompleted)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.white30,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${(progress * 100).toInt()}% complete",
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PROFILE BODY
  // ─────────────────────────────────────────────────────────
  Widget _buildProfileBody() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              _sectionLabel("PERSONAL DETAILS"),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldCard(
                          controller: ageController,
                          label: "Age",
                          hintText: "10–120",
                          icon: Icons.cake_outlined,
                          type: TextInputType.number,
                          hasError: _ageError,
                          onChanged: (_) {
                            if (_ageError) setState(() => _ageError = false);
                          },
                        ),
                        if (_ageError)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.red.shade600, size: 13),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    "Age must be 10 – 120",
                                    style: TextStyle(
                                      color: Colors.red.shade600,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _fieldCard(
                      controller: eduYearsController,
                      label: "Edu. Years",
                      icon: Icons.school_outlined,
                      type: TextInputType.number,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              _sectionLabel("GENDER"),
              const SizedBox(height: 12),

              // BUG FIX #2 – Gender encoding
              // Male  → gender = 0  (was incorrectly 1)
              // Female → gender = 1 (was incorrectly 0)
              // The ML model expects 0=Male, 1=Female (standard OASIS encoding).
              Row(
                children: [
                  Expanded(child: _selectTile(
                    selected: gender == 0,          // FIX: was gender == 1
                    label: "Male",
                    icon: Icons.male_rounded,
                    onTap: () => setState(() => gender = 0), // FIX: was gender = 1
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _selectTile(
                    selected: gender == 1,          // FIX: was gender == 0
                    label: "Female",
                    icon: Icons.female_rounded,
                    onTap: () => setState(() => gender = 1), // FIX: was gender = 0
                  )),
                ],
              ),

              const SizedBox(height: 24),
              _sectionLabel("SOCIOECONOMIC STATUS"),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _chipTile(
                    selected: ses == 1,
                    label: "Low",
                    onTap: () => setState(() => ses = 1),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _chipTile(
                    selected: ses == 2,
                    label: "Middle",
                    onTap: () => setState(() => ses = 2),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _chipTile(
                    selected: ses == 3,
                    label: "High",
                    onTap: () => setState(() => ses = 3),
                  )),
                ],
              ),

              const SizedBox(height: 40),
              _bigButton(
                label: "Start Assessment",
                icon: Icons.arrow_forward_rounded,
                onTap: () {
                  if (ageController.text.isEmpty ||
                      eduYearsController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      backgroundColor: _kDarkGreen,
                      content: Text("Please fill all fields",
                          style: TextStyle(color: Colors.white)),
                    ));
                    return;
                  }

                  final int? age = int.tryParse(ageController.text);
                  if (age == null || age < 10 || age > 120) {
                    setState(() => _ageError = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade700,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        content: const Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Age must be between 10 and 120",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    return;
                  }

                  setState(() {
                    _ageError = false;
                    profileCompleted = true;
                  });
                  _playEntrance();
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  TEST BODY
  // ─────────────────────────────────────────────────────────
  Widget _buildTestBody() {
    final q = questions[currentQuestion];

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Question card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        color: _kGreen.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(q["icon"] as IconData,
                          color: _kGreen, size: 26),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      q["text"] as String,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _kDarkGreen,
                        height: 1.4,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _sectionLabel("SELECT YOUR ANSWER"),
              const SizedBox(height: 12),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Answer options
                      ...options.map((opt) {
                        final bool sel =
                            answers[currentQuestion] == opt["value"] as int;
                        return GestureDetector(
                          onTap: () => setState(
                              () => answers[currentQuestion] = opt["value"]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: sel ? _kGreen : _kCard,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: sel
                                      ? _kGreen.withOpacity(0.30)
                                      : Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: sel ? Colors.white : Colors.transparent,
                                    border: Border.all(
                                      color: sel ? Colors.white : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  child: sel
                                      ? const Icon(Icons.check,
                                          color: _kGreen, size: 14)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    opt["label"] as String,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: sel ? Colors.white : _kDarkGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 16),

                      _bigButton(
                        label: currentQuestion == questions.length - 1
                            ? "See My Results"
                            : "Next Question",
                        icon: currentQuestion == questions.length - 1
                            ? Icons.bar_chart_rounded
                            : Icons.arrow_forward_rounded,
                        onTap: nextQuestion,
                        enabled: answers[currentQuestion] != -1,
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  REUSABLE WIDGETS
  // ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kSubText,
          letterSpacing: 1.4,
        ),
      );

  Widget _fieldCard({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType type,
    String? hintText,
    bool hasError = false,
    ValueChanged<String>? onChanged,
  }) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: hasError
              ? Border.all(color: Colors.red.shade400, width: 1.8)
              : null,
          boxShadow: [
            BoxShadow(
              color: hasError
                  ? Colors.red.withOpacity(0.15)
                  : Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          keyboardType: type,
          onChanged: onChanged,
          style: const TextStyle(
              color: _kDarkGreen, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            labelStyle: TextStyle(
                color: hasError ? Colors.red.shade400 : _kSubText,
                fontSize: 13),
            hintStyle:
                const TextStyle(color: _kSubText, fontSize: 12),
            prefixIcon: Icon(icon,
                color: hasError ? Colors.red.shade400 : _kGreen,
                size: 20),
            suffixIcon: hasError
                ? Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade400, size: 20)
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: hasError ? Colors.red.shade50 : _kCard,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
        ),
      );

  Widget _selectTile({
    required bool selected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected ? _kGreen : _kCard,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? _kGreen.withOpacity(0.30)
                    : Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 30, color: selected ? Colors.white : _kGreen),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: selected ? Colors.white : _kDarkGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );

  Widget _chipTile({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? _kGreen : _kCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? _kGreen.withOpacity(0.30)
                    : Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: selected ? Colors.white : _kDarkGreen,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

  Widget _bigButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(colors: [_kGreen, _kTeal])
                : null,
            color: enabled ? null : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(35),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _kGreen.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: enabled ? Colors.white : Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon,
                  color: enabled ? Colors.white : Colors.grey.shade500,
                  size: 22),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  RESULT PAGE
// ─────────────────────────────────────────────────────────────
class ResultPage extends StatelessWidget {
  final int    percentage;
  final String riskLevel;

  const ResultPage({
    super.key,
    required this.percentage,
    required this.riskLevel,
  });

  @override
  Widget build(BuildContext context) {
    final Color    riskColor;
    final Color    riskBg;
    final IconData riskIcon;
    final String   advice;

    if (riskLevel == "Low") {
      riskColor = const Color(0xFF2D6A4F);
      riskBg    = const Color(0xFFE8F5E9);
      riskIcon  = Icons.check_circle_outline_rounded;
      advice    = "Your responses suggest a low likelihood of cognitive impairment. "
                  "Continue healthy habits and stay mentally active.";
    } else if (riskLevel == "Medium") {
      riskColor = const Color(0xFFF59E0B);
      riskBg    = const Color(0xFFFFFBEB);
      riskIcon  = Icons.warning_amber_rounded;
      advice    = "Your responses indicate some cognitive concerns. We recommend "
                  "speaking with a healthcare professional for a full evaluation.";
    } else {
      riskColor = Colors.red.shade600;
      riskBg    = Colors.red.shade50;
      riskIcon  = Icons.error_outline_rounded;
      advice    = "Your responses suggest a higher risk of cognitive impairment. "
                  "Please consult a doctor as soon as possible for professional assessment.";
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [

            // ── Header ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 14, 20, 22),
              decoration: const BoxDecoration(gradient: _kHeaderGradient),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Your Results",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Cognitive Assessment",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: const Icon(Icons.bar_chart_rounded,
                        size: 30, color: _kGreen),
                  ),
                ],
              ),
            ),

            // ── Scrollable body ──────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // Score card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 160, height: 160,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 160, height: 160,
                                  child: CircularProgressIndicator(
                                    value: percentage / 100,
                                    strokeWidth: 14,
                                    backgroundColor: Colors.grey.shade100,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        riskColor),
                                    strokeCap: StrokeCap.round,
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "$percentage%",
                                      style: TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        color: riskColor,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text("Risk Score",
                                        style: TextStyle(
                                            color: _kSubText,
                                            fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Risk badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                            decoration: BoxDecoration(
                              color: riskBg,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(riskIcon, color: riskColor, size: 22),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    "$riskLevel Risk",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: riskColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Advice card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: _kGreen.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.info_outline,
                                    color: _kGreen, size: 22),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  "What this means",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _kDarkGreen,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            advice,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF546E7A),
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Take Test Again
                    GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_kGreen, _kTeal]),
                          borderRadius: BorderRadius.circular(35),
                          boxShadow: [
                            BoxShadow(
                              color: _kGreen.withOpacity(0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 7),
                            )
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 22),
                            SizedBox(width: 10),
                            Text("Take Test Again",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                )),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Back to Home
                    GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: _kCard,
                          borderRadius: BorderRadius.circular(35),
                          border: Border.all(
                              color: _kGreen.withOpacity(0.35), width: 1.5),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.home_outlined,
                                color: _kGreen, size: 22),
                            SizedBox(width: 10),
                            Text("Back to Home",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: _kGreen,
                                )),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TEST HISTORY PAGE
// ─────────────────────────────────────────────────────────────
class TestHistoryPage extends StatefulWidget {
  const TestHistoryPage({super.key});

  @override
  State<TestHistoryPage> createState() => _TestHistoryPageState();
}

class _TestHistoryPageState extends State<TestHistoryPage> {
  final _user = FirebaseAuth.instance.currentUser;

  Future<void> _deleteRecord(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Record?",
            style: TextStyle(
                color: _kDarkGreen, fontWeight: FontWeight.bold)),
        content: const Text(
            "This test result will be permanently removed. This cannot be undone.",
            style: TextStyle(color: _kSubText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text("Cancel", style: TextStyle(color: _kSubText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    final user = _user;
    if (confirmed != true || user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('predictions')
        .doc(docId)
        .delete();

    final remaining = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('predictions')
        .limit(1)
        .get();

    if (remaining.docs.isEmpty && mounted) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'last_test': FieldValue.delete()});

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const _EmptyHomePage()),
      );
    }
  }

  Future<void> _goToTest() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuestionnairePage()),
    );
    if (mounted) setState(() {});
  }

  Color   _riskColor(String l) => l == 'Low'
      ? const Color(0xFF2E7D32)
      : l == 'Medium'
          ? const Color(0xFFE65100)
          : const Color(0xFFC62828);

  Color   _riskBg(String l) => l == 'Low'
      ? const Color(0xFFE8F5E9)
      : l == 'Medium'
          ? const Color(0xFFFFF3E0)
          : const Color(0xFFFFEBEE);

  IconData _riskIcon(String l) => l == 'Low'
      ? Icons.check_circle_outline
      : l == 'Medium'
          ? Icons.warning_amber_rounded
          : Icons.dangerous_outlined;

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return "${dt.day} ${m[dt.month]} ${dt.year}  •  $h:$min";
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    final predictionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('predictions')
        .orderBy('timestamp', descending: true);

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [

            // ── Header ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 24),
              decoration:
                  const BoxDecoration(gradient: _kHeaderGradient),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Test History",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Your past cognitive assessments",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _goToTest,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              color: _kGreen, size: 18),
                          SizedBox(width: 6),
                          Text("New Test",
                              style: TextStyle(
                                color: _kGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── History list ─────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: predictionsRef.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: _kGreen));
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_outlined,
                              size: 64,
                              color: _kSubText.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text("No history yet",
                              style: TextStyle(
                                  color: _kSubText, fontSize: 16)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc  = docs[i];
                      final data =
                          doc.data() as Map<String, dynamic>;
                      return _HistoryCard(
                        docId:      doc.id,
                        data:       data,
                        index:      docs.length - i,
                        formatDate: _formatDate,
                        riskColor:  _riskColor,
                        riskBg:     _riskBg,
                        riskIcon:   _riskIcon,
                        onDelete:   () => _deleteRecord(doc.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HISTORY CARD
// ─────────────────────────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.docId,
    required this.data,
    required this.index,
    required this.formatDate,
    required this.riskColor,
    required this.riskBg,
    required this.riskIcon,
    required this.onDelete,
  });

  final String docId;
  final Map<String, dynamic> data;
  final int index;
  final String   Function(String)   formatDate;
  final Color    Function(String)   riskColor;
  final Color    Function(String)   riskBg;
  final IconData Function(String)   riskIcon;
  final VoidCallback                onDelete;

  @override
  Widget build(BuildContext context) {
    final String riskLevel   = data['risk_level']  ?? 'Unknown';
    final double probability = (data['probability'] ?? 0.0).toDouble();
    final int    percentage  = (probability * 100).toInt();
    final String timestamp   = data['timestamp']   ?? '';
    final Map<String, dynamic> q =
        Map<String, dynamic>.from(data['questionnaire'] ?? {});

    final Color    rc = riskColor(riskLevel);
    final Color    rb = riskBg(riskLevel);
    final IconData ri = riskIcon(riskLevel);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Card header strip
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: BoxDecoration(
              color: rb,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: rc.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(ri, color: rc, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Test #$index",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _kDarkGreen,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (timestamp.isNotEmpty)
                        Text(
                          formatDate(timestamp),
                          style: const TextStyle(
                              color: _kSubText, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: rc.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: rc.withOpacity(0.3)),
                    ),
                    child: Text(
                      "$riskLevel Risk",
                      style: TextStyle(
                        color: rc,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // Score bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Risk Score",
                        style:
                            TextStyle(color: _kSubText, fontSize: 12)),
                    Text("$percentage%",
                        style: TextStyle(
                          color: rc,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: probability,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(rc),
                  ),
                ),
              ],
            ),
          ),

          // Questionnaire chips
          if (q.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (q['AGE'] != null)
                    _DetailChip(label: "Age", value: "${q['AGE']}"),
                  if (q['MMSE'] != null)
                    _DetailChip(label: "MMSE", value: "${q['MMSE']}"),
                  if (q['EDUCATION'] != null)
                    _DetailChip(
                        label: "Edu Level",
                        value: "${q['EDUCATION']}"),
                  if (q['YEARS_OF_EDUCATION'] != null)
                    _DetailChip(
                        label: "Edu Yrs",
                        value: "${q['YEARS_OF_EDUCATION']}"),
                  if (q['SES'] != null)
                    _DetailChip(label: "SES", value: "${q['SES']}"),
                  if (q['GENDER'] != null)
                    _DetailChip(
                        label: "Gender",
                        // BUG FIX #2 – Display label now matches corrected encoding
                        value: q['GENDER'] == 0 ? "Male" : "Female"),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: "$label: ",
                style: const TextStyle(color: _kSubText, fontSize: 12),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: _kDarkGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EMPTY HOME PAGE
// ─────────────────────────────────────────────────────────────
class _EmptyHomePage extends StatelessWidget {
  const _EmptyHomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration:
                  const BoxDecoration(gradient: _kHeaderGradient),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CogniCheck",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Early cognitive screening",
                    style: TextStyle(
                        color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          color: _kGreen.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                            Icons.psychology_outlined,
                            size: 52,
                            color: _kGreen),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        "No Test Taken Yet",
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kDarkGreen),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Take your first cognitive screening test to assess your brain health and track it over time.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15,
                            color: _kSubText,
                            height: 1.55),
                      ),
                      const SizedBox(height: 40),
                      GestureDetector(
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const QuestionnairePage()),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [_kGreen, _kTeal]),
                            borderRadius: BorderRadius.circular(35),
                            boxShadow: [
                              BoxShadow(
                                color: _kGreen.withOpacity(0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_circle_outline_rounded,
                                  color: Colors.white, size: 22),
                              SizedBox(width: 10),
                              Text("Start Test",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  INFO SHEET HELPERS
// ─────────────────────────────────────────────────────────────
class _InfoDivider extends StatelessWidget {
  final String label;
  const _InfoDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4, height: 18,
          decoration: BoxDecoration(
            color: _kGreen,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _kGreen,
              letterSpacing: 1.3,
            )),
        const SizedBox(width: 10),
        Expanded(
            child: Divider(color: Colors.grey.shade200, thickness: 1)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool highlight;
  const _InfoRow({
    required this.icon,
    required this.text,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Icon(icon,
                size: 18,
                color: highlight ? Colors.orange.shade700 : _kGreen),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: highlight
                    ? Colors.orange.shade800
                    : const Color(0xFF546E7A),
                fontWeight: highlight
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EduTable extends StatelessWidget {
  static const List<Map<String, String>> _rows = [
    {"years": "0 years",   "level": "No formal education"},
    {"years": "5 years",   "level": "Primary school (Class 5)"},
    {"years": "8 years",   "level": "Middle school (Class 8)"},
    {"years": "10 years",  "level": "Secondary school (Class 10)"},
    {"years": "12 years",  "level": "Senior secondary (Class 12)"},
    {"years": "15 years",  "level": "Bachelor's degree"},
    {"years": "17 years",  "level": "Master's degree"},
    {"years": "20+ years", "level": "PhD / Doctoral level"},
  ];

  const _EduTable();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: _rows.asMap().entries.map((entry) {
          final i      = entry.key;
          final row    = entry.value;
          final isLast = i == _rows.length - 1;
          final isEven = i % 2 == 0;
          return Container(
            decoration: BoxDecoration(
              color: isEven ? Colors.white : const Color(0xFFF4F6F5),
              borderRadius: BorderRadius.vertical(
                top:    i == 0 ? const Radius.circular(16) : Radius.zero,
                bottom: isLast ? const Radius.circular(16) : Radius.zero,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kGreen.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        row["years"]!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row["level"]!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _kDarkGreen,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}