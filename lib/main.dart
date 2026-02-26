import 'package:flutter/material.dart';

import 'package:bitchat/ui/app_theme.dart';
import 'package:bitchat/ui/home_screen.dart';
import 'package:bitchat/ui/onboarding_screen.dart';

void main() {
  runApp(const BitchatApp());
}

class BitchatApp extends StatefulWidget {
  const BitchatApp({super.key});

  @override
  State<BitchatApp> createState() => _BitchatAppState();
}

class _BitchatAppState extends State<BitchatApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _hasCompletedOnboarding = false;

  bool get _isDark => _themeMode == ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  void _completeOnboarding(String nickname) {
    setState(() {
      _hasCompletedOnboarding = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bitchat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: _hasCompletedOnboarding
          ? HomeScreen(onThemeToggle: _toggleTheme, isDark: _isDark)
          : OnboardingScreen(onComplete: _completeOnboarding),
    );
  }
}
