import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Palette (Atelier Architekt — Earthy Warm Neutral) ──────────────────────
  static const Color bg = Color(0xFFFAF7F2); // Soft Linen Cream
  static const Color surface = Color(0xFFFFFFFF); // Pure Alabaster White
  static const Color surfaceRaised = Color(0xFFF7F3ED); // Warm Oat Travertine
  static const Color surfaceElevated = Color(0xFFEDE5DC); // Sand Stone
  static const Color border = Color(0xFFDDD5CA); // Refined Sand Border
  static const Color borderSubtle = Color(0xFFEBE4DA);

  static const Color accent = Color(0xFF2C2724); // Deep Espresso
  static const Color accentHover = Color(0xFF1E1A17);
  static const Color accentTerracotta = Color(0xFFE6BEAE); // Soft Terracotta
  static const Color accentTaupe = Color(0xFFB2967D); // Earthy Taupe
  static const Color accentDim = Color(0xFFEAE2D8); // Warm Sand Pill
  static const Color accentGlow = Color(0x1A2C2724);

  static const Color textPrimary = Color(0xFF2C2724); // Deep Espresso text
  static const Color textSecondary = Color(0xFF7A6A5C); // Muted Earthy Taupe
  static const Color textTertiary = Color(0xFFA8998B); // Soft Sand Grey

  static const Color success = Color(0xFF3D6B69); // Earthy Sage Green
  static const Color successDim = Color(0xFFECF8F8); // Pale Sea Salt Mist
  static const Color danger = Color(0xFFC95A5A); // Muted Brick Red
  static const Color dangerDim = Color(0xFFFDF2F2);

  // ── Obstacle colours ────────────────────────────────────────────────────
  static const Color windowColor = Color(0x33ECF8F8);
  static const Color windowBorder = Color(0xFF8C725C);
  static const Color doorColor = Color(0x22E6BEAE);
  static const Color doorBorder = Color(0xFFB2967D);

  // ── Theme data ───────────────────────────────────────────────────────────
  static ThemeData get dark => theme; // Backwards compatible alias
  static ThemeData get light => theme;

  static ThemeData get theme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.light(
        primary: accent,
        secondary: success,
        surface: surface,
        onSurface: textPrimary,
        error: danger,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFFFAF7F2),
          elevation: 1,
          shadowColor: accentGlow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: -0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: GoogleFonts.plusJakartaSans(color: textSecondary, fontSize: 13),
        hintStyle: GoogleFonts.plusJakartaSans(color: textTertiary, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
    );
  }
}
