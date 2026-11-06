import 'package:flutter/material.dart';

/// Earthy warm neutral palette. Every text colour here meets WCAG 2.2 AA
/// (4.5:1) on the app's light surfaces; [outline] meets the 3:1 needed for
/// form-field borders. Widgets read colours through [ColorScheme] roles
/// where one exists (see [AppTheme.theme]).
class AppTheme {
  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const Color bg = Color(0xFFFAF7F2); // linen
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceRaised = Color(0xFFF7F3ED); // oat
  static const Color surfaceElevated = Color(0xFFEDE5DC); // sand
  static const Color border = Color(0xFFDDD5CA); // decorative dividers/cards
  static const Color borderSubtle = Color(0xFFEBE4DA);

  /// Borders that identify a control (text fields): 3.2:1 on white.
  static const Color outline = Color(0xFF9C8E80);

  // ── Accents ──────────────────────────────────────────────────────────────
  static const Color accent = Color(0xFF2C2724); // espresso
  static const Color accentHover = Color(0xFF1E1A17);
  static const Color accentTerracotta = Color(0xFFE6BEAE); // fills only
  static const Color accentTaupe = Color(0xFFB2967D); // fills/borders only
  /// Taupe for text: 5.7:1 on white (plain [accentTaupe] is only 2.8:1).
  static const Color accentTaupeText = Color(0xFF7D6248);
  static const Color accentDim = Color(0xFFEAE2D8);
  static const Color accentGlow = Color(0x1A2C2724);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF2C2724); // 13.8:1
  /// 5.7:1 on linen, 4.9:1 on the darkest sand surface.
  static const Color textSecondary = Color(0xFF6E5F52);

  /// Kept for existing callers; same value as [textSecondary] (the old
  /// light grey was 2.8:1 and failed AA).
  static const Color textTertiary = textSecondary;

  // ── Status ───────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF3D6B69); // sage, 6.0:1
  static const Color successDim = Color(0xFFECF8F8);
  static const Color danger =
      Color(0xFFA94444); // brick, 5.8:1 (white text too)
  static const Color dangerDim = Color(0xFFFDF2F2);

  // ── Obstacle colours ─────────────────────────────────────────────────────
  static const Color windowColor = Color(0x33ECF8F8);
  static const Color windowBorder = Color(0xFF8C725C);
  static const Color doorColor = Color(0x22E6BEAE);
  static const Color doorBorder = Color(0xFFB2967D);

  // ── Theme data ───────────────────────────────────────────────────────────
  static ThemeData get dark => theme; // Backwards compatible alias
  static ThemeData get light => theme;

  /// Minimum size for anything tappable (Android's 48dp guideline).
  static const Size minTapTarget = Size(48, 48);

  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: accent,
    onPrimary: bg,
    secondary: success,
    onSecondary: surface,
    tertiary: accentTaupeText,
    onTertiary: surface,
    error: danger,
    onError: surface,
    surface: surface,
    onSurface: textPrimary,
    onSurfaceVariant: textSecondary,
    surfaceContainerLowest: surface,
    surfaceContainerLow: bg,
    surfaceContainer: surfaceRaised,
    surfaceContainerHigh: surfaceElevated,
    outline: outline,
    outlineVariant: border,
  );

  static ThemeData get theme {
    final textTheme = AppTextStyle.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: AppTextStyle.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyle.titleMedium.copyWith(color: textPrimary),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: bg,
          elevation: 1,
          shadowColor: accentGlow,
          minimumSize: minTapTarget,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: AppTextStyle.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: minTapTarget,
          textStyle: AppTextStyle.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minTapTarget,
          textStyle: AppTextStyle.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: minTapTarget),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        prefixIconColor: accent,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: bg),
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

/// The app's type scale. Nothing is smaller than 12: the sales screen is
/// read at arm's length across a table. Widgets pick a slot from
/// `Theme.of(context).textTheme` and only ever override its colour.
abstract class AppTextStyle {
  static const String fontFamily = 'PlusJakartaSans';

  static const TextStyle _base = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Big totals.
  static final TextStyle headlineSmall =
      _base.copyWith(fontSize: 22, height: 1.25, fontWeight: FontWeight.w700);

  /// Prices, sheet titles.
  static final TextStyle titleLarge =
      _base.copyWith(fontSize: 20, height: 1.3, fontWeight: FontWeight.w700);

  /// Screen and section headings, app bar titles.
  static final TextStyle titleMedium =
      _base.copyWith(fontSize: 18, height: 1.3, fontWeight: FontWeight.w700);

  /// Card titles, names.
  static final TextStyle titleSmall =
      _base.copyWith(fontSize: 16, height: 1.35, fontWeight: FontWeight.w700);

  /// Input text.
  static final TextStyle bodyLarge = _base.copyWith(fontSize: 16, height: 1.4);

  /// Descriptions and messages.
  static final TextStyle bodyMedium = _base.copyWith(fontSize: 14, height: 1.4);

  /// Secondary details.
  static final TextStyle bodySmall = _base.copyWith(fontSize: 13, height: 1.35);

  /// Buttons.
  static final TextStyle labelLarge =
      _base.copyWith(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600);

  /// Chips, tags, small buttons.
  static final TextStyle labelMedium =
      _base.copyWith(fontSize: 13, height: 1.3, fontWeight: FontWeight.w600);

  /// The smallest text in the app (12).
  static final TextStyle labelSmall =
      _base.copyWith(fontSize: 12, height: 1.3, fontWeight: FontWeight.w500);

  static final TextTheme textTheme = TextTheme(
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}

/// Shorthand for the theme's text styles and colours in widget code.
extension AppThemeContext on BuildContext {
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}
