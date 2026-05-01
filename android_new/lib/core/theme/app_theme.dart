import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF131B24);
  static const Color card = Color(0xFF1A2430);
  static const Color primary = Color(0xFF4EC3E0);
  static const Color accent = Color(0xFFF4B860);
  static const Color success = Color(0xFF4DD6A3);
  static const Color error = Color(0xFFFF6B6B);
  static const Color textPrimary = Color(0xFFE9F1F7);
  static const Color textSecondary = Color(0xFF9BB0C0);

  static const Duration fastAnimation = Duration(milliseconds: 180);
  static const Duration mediumAnimation = Duration(milliseconds: 320);

  static final LinearGradient ambientGradient = LinearGradient(
    colors: [
      const Color(0xFF0B0F14),
      const Color(0xFF0F1620),
      const Color(0xFF0B0F14),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static final LinearGradient primaryGradient = LinearGradient(
    colors: [
      primary,
      const Color(0xFF2C8EB8),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
      error: error,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme().apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardColor: card,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: card,
      contentTextStyle: const TextStyle(color: textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
