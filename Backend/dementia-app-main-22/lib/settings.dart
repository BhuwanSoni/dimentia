import 'package:flutter/material.dart';
import 'settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  Future<void> _saveUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('username', _usernameController.text);  // 🔥 FIX 2: was 'user_name', must match SettingsProvider key
    await prefs.setString('emergency_number', _contactController.text);
    await prefs.setString('address', _addressController.text);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'name': _usernameController.text,
      'email': user.email,
      'emergency_number': _contactController.text,
      'address': _addressController.text,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.settingsSaved),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final settings = SettingsProvider.of(context);

    if (_usernameController.text.isEmpty) {
      _usernameController.text = settings.username;
    }

    if (_contactController.text.isEmpty) {
      _contactController.text = settings.emergencyContact;
    }

    if (_addressController.text.isEmpty) {
      _addressController.text = settings.address;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settings),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveUserData,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          /// PROFILE
          Text(l.profile,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),

          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: l.username,
                      prefixIcon: const Icon(Icons.person),
                    ),
                    onChanged: (value) {
                      settings.updateUsername(value);
                    },
                  ),
                  const SizedBox(height: 10),

                  /// GENDER
                  DropdownButtonFormField<String>(
                    initialValue:
                        settings.gender.isEmpty ? null : settings.gender,
                    decoration: InputDecoration(
                      labelText: l.gender,
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    items: [
                      DropdownMenuItem(value: "Male", child: Text(l.male)),
                      DropdownMenuItem(value: "Female", child: Text(l.female)),
                      DropdownMenuItem(value: "Other", child: Text(l.other)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.updateGender(value);
                      }
                    },
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: l.address,
                      prefixIcon: const Icon(Icons.home),
                    ),
                    onChanged: (value) {
                      settings.updateAddress(value);
                    },
                  ),

                  const SizedBox(height: 10),

                  ListTile(
                    leading: const Icon(Icons.cake),
                    title: Text(
                      settings.birthdate == null
                          ? l.selectBirthdate
                          : "${settings.birthdate!.day}/${settings.birthdate!.month}/${settings.birthdate!.year}",
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2000),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );

                      if (picked != null) {
                        settings.updateBirthdate(picked);
                      }
                    },
                  ),

                  if (settings.birthdate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        "${l.age}: ${settings.age} ${l.years}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 25),

          /// LANGUAGE (🔥 FIXED)
          Text(l.language,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),

          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(l.language),
              trailing: DropdownButton<String>(
                value: settings.languageCode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: "en",
                    child: Text("English"),
                  ),
                  DropdownMenuItem(
                    value: "hi",
                    child: Text("हिन्दी"),
                  ),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    await settings.updateLanguage(value);

                    // 🔥 FORCE UI UPDATE
                    if (mounted) {
                      setState(() {});
                    }
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 25),

          /// EMERGENCY
          Text(l.emergency,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),

          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l.emergencyContact,
                  prefixIcon: const Icon(Icons.phone),
                ),
                onChanged: (value) {
                  settings.updateEmergencyContact(value);
                },
              ),
            ),
          ),

          const SizedBox(height: 30),

          ElevatedButton(
            onPressed: _saveUserData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              l.saveSettings,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
