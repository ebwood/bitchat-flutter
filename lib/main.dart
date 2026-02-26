import 'package:flutter/material.dart';

import 'package:bitchat/ui/app_theme.dart';
import 'package:bitchat/ui/home_screen.dart';

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

  bool get _isDark => _themeMode == ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
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
      home: HomeScreen(onThemeToggle: _toggleTheme, isDark: _isDark),
    );
  }
}
