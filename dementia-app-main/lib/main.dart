import 'package:flutter/material.dart';
import 'home.dart';
import 'settings_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsProvider(
        child: MaterialApp(
        title: 'Memoir',
        theme: ThemeData(
          fontFamily: 'Inter',
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFE7F0ED),
          //scaffoldBackgroundColor: Color(0xFFA6C6B7),
        ),
        home: const HomePage(),
        debugShowCheckedModeBanner: false,
        ),
    );
  }
}
