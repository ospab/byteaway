import 'package:flutter/material.dart';

/// ByteAway dark theme with cyan/teal accent, glassmorphism-ready.
class AppTheme {
  AppTheme._();

  // ── Enhanced Color Palette ──────────────────────────────────────
  static const Color primary = Color(0xFF00E5CC); // Cyan/teal
  static const Color primaryDark = Color(0xFF00B4A0);
  static const Color accent = Color(0xFF7C4DFF); // Purple accent
  static const Color background = Color(0xFF0D1117); // Deep dark
  static const Color surface = Color(0xFF161B22); // Card bg
  static const Color surfaceLight = Color(0xFF21262D); // Elevated card
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color error = Color(0xFFFF6B6B);
  static const Color success = Color(0xFF3FB950);
  static const Color warning = Color(0xFFF0C000);

  // ── Enhanced Colors ─────────────────────────────────────
  static const Color gold = Color(0xFFFFD700);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);
  static const Color cardGlow = Color(0x3300E5CC);
  static const Color gradientStart = Color(0xFF1A1F2E);
  static const Color gradientEnd = Color(0xFF0D1117);
  static const Color surfaceVariant = Color(0xFF1C2128);
  static const Color outline = Color(0xFF30363D);
  static const Color outlineVariant = Color(0xFF21262D);

  // ── Enhanced Gradients ───────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E5CC), Color(0xFF7C4DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0x20FFFFFF), Color(0x08FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient premiumCardGradient = LinearGradient(
    colors: [Color(0xFF1A1F2E), Color(0xFF0D1117)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF00E5CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF3FB950), Color(0xFF00E5CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFE74C3C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Enhanced Theme Data ─────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: accent,
          surface: surface,
          error: error,
          onPrimary: background,
          onSecondary: Colors.white,
          onSurface: textPrimary,
          onError: Colors.white,
          surfaceVariant: surfaceVariant,
          outline: outline,
          outlineVariant: outlineVariant,
        ),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            letterSpacing: -1.0,
            height: 1.2,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.5,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.25,
            height: 1.3,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.0,
            height: 1.4,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: textPrimary,
            letterSpacing: 0.0,
            height: 1.4,
          ),
          titleSmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textPrimary,
            letterSpacing: 0.1,
            height: 1.4,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: textSecondary,
            letterSpacing: 0.0,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: textSecondary,
            letterSpacing: 0.0,
            height: 1.5,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: textSecondary,
            letterSpacing: 0.1,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: primary,
            letterSpacing: 0.5,
            height: 1.3,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: primary,
            letterSpacing: 0.5,
            height: 1.3,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.0,
          ),
          iconTheme: IconThemeData(color: textPrimary, size: 24),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primary,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: background,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            elevation: 2,
            shadowColor: primary.withOpacity(0.3),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: primary, width: 1.5),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.25,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: error, width: 2),
          ),
          hintStyle: const TextStyle(
              color: textSecondary, fontWeight: FontWeight.w400),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? primary
                : textSecondary;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? primary.withOpacity(0.3)
                : surfaceLight;
          }),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? primary
                : Colors.transparent;
          }),
          checkColor: WidgetStateProperty.all(Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceLight,
          selectedColor: primary.withOpacity(0.2),
          labelStyle: const TextStyle(color: textPrimary),
          secondaryLabelStyle: const TextStyle(color: textSecondary),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
        ),
      );

  // ── Enhanced Glassmorphism Effects ──────────────────────────────────────
  static BoxShadow get glassShadow => BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        offset: const Offset(0, 4),
      );

  static BoxShadow get premiumShadow => BoxShadow(
        color: primary.withOpacity(0.15),
        blurRadius: 20,
        offset: const Offset(0, 8),
      );

  static BoxShadow get cardShadow => BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 15,
        offset: const Offset(0, 5),
      );

  static BoxShadow get subtleShadow => BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 8,
        offset: const Offset(0, 2),
      );

  static BoxShadow get glowShadow => BoxShadow(
        color: primary.withOpacity(0.4),
        blurRadius: 25,
        offset: const Offset(0, 0),
        spreadRadius: 2,
      );

  static Border get glassBorder => Border.all(
        color: Colors.white.withOpacity(0.08),
        width: 1.0,
      );

  static Border get premiumBorder => Border.all(
        color: primary.withOpacity(0.2),
        width: 1.0,
      );

  static LinearGradient get glassGradient => LinearGradient(
        colors: [
          Colors.white.withOpacity(0.12),
          Colors.white.withOpacity(0.04),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get premiumGlassGradient => LinearGradient(
        colors: [
          primary.withOpacity(0.15),
          accent.withOpacity(0.05),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── Enhanced Card Decorations ─────────────────────────────────────
  static BoxDecoration get premiumCardDecoration => BoxDecoration(
        gradient: premiumCardGradient,
        borderRadius: BorderRadius.circular(20),
        border: premiumBorder,
        boxShadow: [premiumShadow, cardShadow],
      );

  static BoxDecoration get glassCardDecoration => BoxDecoration(
        gradient: glassGradient,
        borderRadius: BorderRadius.circular(20),
        border: glassBorder,
        boxShadow: [glassShadow],
      );

  static BoxDecoration get elevatedCardDecoration => BoxDecoration(
        gradient: glassGradient,
        borderRadius: BorderRadius.circular(16),
        border: glassBorder,
        boxShadow: [subtleShadow, glassShadow],
      );

  static BoxDecoration get successCardDecoration => BoxDecoration(
        gradient: successGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: success.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: success.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      );

  static BoxDecoration get errorCardDecoration => BoxDecoration(
        gradient: dangerGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: error.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: error.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      );

  // ── Animation & Transition Helpers ─────────────────────────────────────
  static Duration get fastAnimation => const Duration(milliseconds: 200);
  static Duration get mediumAnimation => const Duration(milliseconds: 300);
  static Duration get slowAnimation => const Duration(milliseconds: 500);

  static Curve get defaultCurve => Curves.easeInOutCubic;
  static Curve get bounceCurve => Curves.elasticOut;
  static Curve get smoothCurve => Curves.fastOutSlowIn;

  // ── Utility Methods ─────────────────────────────────────────────────
  static Color getStatusColor(bool isActive, [bool isError = false]) {
    if (isError) return error;
    return isActive ? success : textSecondary;
  }

  static String formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(1)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
