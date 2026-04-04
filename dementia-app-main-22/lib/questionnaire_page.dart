import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
class QuestionnairePage extends StatefulWidget {
  const QuestionnairePage({super.key});

  @override
  State<QuestionnairePage> createState() => _QuestionnairePageState();
}

class _QuestionnairePageState extends State<QuestionnairePage> {

  // ---------------- PROFILE INPUT ----------------
  final TextEditingController ageController = TextEditingController();
  final TextEditingController eduYearsController = TextEditingController();

  int gender = 1;
  int ses = 2;
  int education = 5;

  bool profileCompleted = false;

  // ---------------- QUESTIONS ----------------
  final List<String> questions = [
    "Do you forget recent conversations or events?",
    "Do you sometimes forget what day or time it is?",
    "Do you get confused about where you are?",
    "Do you have difficulty completing daily tasks?",
    "Do you struggle to find the right words?",
    "Do you frequently misplace items?",
    "Do you have trouble concentrating?",
    "Do you experience sudden mood changes?",
    "Do you get lost in familiar places?",
    "Do you have difficulty making simple decisions?"
  ];

  final List<int> answers = List.filled(10, -1);
  int currentQuestion = 0;

  final Map<String, int> options = {
    "Never": 0,
    "Sometimes": 1,
    "Often": 2,
    "Always": 3
  };

  // ---------------- RESET FUNCTION ----------------
  void resetTest() {
    setState(() {
      answers.fillRange(0, answers.length, -1);
      currentQuestion = 0;
      profileCompleted = false;

      ageController.clear();
      eduYearsController.clear();

      gender = 1;
      ses = 2;
      education = 5;
    });
  }

  void nextQuestion() {
    if (answers[currentQuestion] == -1) return;

    if (currentQuestion < questions.length - 1) {
      setState(() => currentQuestion++);
    } else {
      calculateScore();
    }
  }

  // ---------------- API CALL ----------------
  Future<void> calculateScore() async {

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      Navigator.pop(context);
      return;
    }

    // ---------------- MMSE ----------------
    int rawScore = answers.reduce((a, b) => a + b);
    int mmse = 30 - rawScore; 

    // ---------------- API CALL ----------------
    final response = await http.post(
      Uri.parse("https://dimentia.onrender.com/predict"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "user_id": user.uid,
        "questionnaire": {
          "AGE": int.parse(ageController.text),
          "GENDER": gender,
          "YEARS_OF_EDUCATION": int.parse(eduYearsController.text),
          "SES": ses,
          "EDUCATION": education,
          "MMSE": mmse
        }
      }),
    );
    // 🔍 Always log the raw response for debugging
    print("📡 Response status: ${response.statusCode}");
    print("📡 Response body: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception("Server error (${response.statusCode}): ${response.body}");
    }

    final data = jsonDecode(response.body);

    // 🛡️ Guard: backend may return {"error": "..."} even on 200
    if (data.containsKey("error")) {
      throw Exception("Prediction error: ${data["error"]}");
    }

    int percentage = (data["probability"] * 100).toInt();
    String riskLevel = data["risk_level"];

    // 🔥 ---------------- SAVE TO FIRESTORE ----------------
    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .set({
      "AGE": int.parse(ageController.text),
      "GENDER": gender,
      "YEARS_OF_EDUCATION": int.parse(eduYearsController.text),
      "SES": ses,
      "EDUCATION": education,
      "MMSE": mmse,
      "risk_level": riskLevel,
      "probability": data["probability"],
      "last_test": DateTime.now().toIso8601String()
    }, SetOptions(merge: true));

    // ---------------- CLOSE LOADER ----------------
    Navigator.pop(context);

    // ---------------- RESULT SCREEN ----------------
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(
          percentage: percentage,
          riskLevel: riskLevel,
        ),
      ),
    );

    // 🔥 RESET FOR RETEST
    if (result == true) {
      resetTest();
    }

  } catch (e) {

    Navigator.pop(context);

    print("❌ Error: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Error: $e"),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cognitive Test")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: profileCompleted ? buildTestUI() : buildProfileUI(),
      ),
    );
  }

  // ---------------- PROFILE UI ----------------
  Widget buildProfileUI() {
    return Column(
      children: [

        TextField(
          controller: ageController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Age"),
        ),

        const SizedBox(height: 20),

        TextField(
          controller: eduYearsController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Years of Education"),
        ),

        const SizedBox(height: 20),

        const Text("Gender"),

        Row(
          children: [
            Expanded(
              child: RadioListTile(
                title: const Text("Male"),
                value: 1,
                groupValue: gender,
                onChanged: (val) => setState(() => gender = val!),
              ),
            ),
            Expanded(
              child: RadioListTile(
                title: const Text("Female"),
                value: 0,
                groupValue: gender,
                onChanged: (val) => setState(() => gender = val!),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        DropdownButtonFormField(
          initialValue: ses,
          decoration: const InputDecoration(labelText: "SES"),
          items: const [
            DropdownMenuItem(value: 1, child: Text("Low")),
            DropdownMenuItem(value: 2, child: Text("Middle")),
            DropdownMenuItem(value: 3, child: Text("High")),
          ],
          onChanged: (val) => setState(() => ses = val!),
        ),

        const SizedBox(height: 20),

        ElevatedButton(
          onPressed: () {
            if (ageController.text.isEmpty ||
                eduYearsController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please fill all fields")),
              );
              return;
            }

            setState(() => profileCompleted = true);
          },
          child: const Text("Start Test"),
        ),
      ],
    );
  }

  // ---------------- TEST UI ----------------
  Widget buildTestUI() {
    return Column(
      children: [

        Text(
          "Question ${currentQuestion + 1} / ${questions.length}",
          style: const TextStyle(fontSize: 18),
        ),

        const SizedBox(height: 30),

        Text(
          questions[currentQuestion],
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 30),

        ...options.entries.map((option) {
          return RadioListTile(
            title: Text(option.key),
            value: option.value,
            groupValue: answers[currentQuestion],
            onChanged: (value) {
              setState(() {
                answers[currentQuestion] = value!;
              });
            },
          );
        }),

        const Spacer(),

        ElevatedButton(
          onPressed: nextQuestion,
          child: const Text("Next"),
        ),
      ],
    );
  }
}

// ---------------- RESULT PAGE ----------------
class ResultPage extends StatelessWidget {

  final int percentage;
  final String riskLevel;

  const ResultPage({
    super.key,
    required this.percentage,
    required this.riskLevel
  });

  @override
  Widget build(BuildContext context) {

    Color riskColor;

    if (riskLevel == "Low") {
      riskColor = Colors.green;
    } else if (riskLevel == "Medium") {
      riskColor = Colors.orange;
    } else {
      riskColor = Colors.red;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Result")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Text(
              "Cognitive Risk: $percentage%",
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              "Risk Level: $riskLevel",
              style: TextStyle(
                fontSize: 24,
                color: riskColor,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true); // 🔥 triggers reset
              },
              child: const Text("Retest"),
            )

          ],
        ),
      ),
    );
  }
}