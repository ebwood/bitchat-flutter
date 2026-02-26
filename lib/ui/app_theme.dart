import 'package:flutter/material.dart';

/// Terminal-inspired dark/light theme for BitChat.
///
/// Matches the aesthetic of the iOS and Android native apps.
class AppTheme {
  AppTheme._();

  // --- Colors ---
  static const _terminalGreen = Color(0xFF00FF41);
  static const _terminalAmber = Color(0xFFFFB000);
  static const _terminalCyan = Color(0xFF00E5FF);
  static const _darkBg = Color(0xFF0D1117);
  static const _darkSurface = Color(0xFF161B22);
  static const _darkCard = Color(0xFF1C2333);
  static const _dimText = Color(0xFF8B949E);
  static const _brightText = Color(0xFFE6EDF3);

  /// Dark theme (default).
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _darkBg,
    colorScheme: const ColorScheme.dark(
      primary: _terminalGreen,
      secondary: _terminalCyan,
      tertiary: _terminalAmber,
      surface: _darkSurface,
      onSurface: _brightText,
      onPrimary: _darkBg,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkSurface,
      foregroundColor: _terminalGreen,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: _terminalGreen,
      ),
    ),
    cardTheme: const CardThemeData(
      color: _darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkCard,
      hintStyle: const TextStyle(color: _dimText, fontFamily: 'monospace'),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: _brightText,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: _brightText,
      ),
      bodySmall: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: _dimText,
      ),
      labelSmall: TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        color: _dimText,
      ),
    ),
    dividerColor: _darkCard,
    useMaterial3: true,
  );

  /// Light theme.
  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF6F8FA),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF1A7F37),
      secondary: Color(0xFF0969DA),
      surface: Colors.white,
      onSurface: Color(0xFF1F2328),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1F2328),
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1F2328),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontFamily: 'monospace', fontSize: 14),
      bodyMedium: TextStyle(fontFamily: 'monospace', fontSize: 13),
      bodySmall: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: Color(0xFF656D76),
      ),
    ),
    useMaterial3: true,
  );

  // --- Signal strength colors for RSSI indicators ---
  static Color rssiColor(int rssi) {
    if (rssi >= -50) return _terminalGreen;
    if (rssi >= -70) return _terminalAmber;
    return Colors.redAccent;
  }
}
