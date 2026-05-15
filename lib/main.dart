import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: LckApp()));
}

class LckApp extends StatelessWidget {
  const LckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LCK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0BC4E3),
          surface: Color(0xFF141928),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0E1A),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
