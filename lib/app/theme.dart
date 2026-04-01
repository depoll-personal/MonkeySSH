import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme configuration for the Flutty app.
///
/// Clean & minimal aesthetic with warm terracotta accent,
/// Plus Jakarta Sans typography, and generous spacing.
abstract final class FluttyTheme {
  // ── Warm mineral palette ──────────────────────────────────────────────

  /// Primary terracotta / copper accent.
  static const _accent = Color(0xFFC27349);

  /// Lighter warm accent for gradients and soft highlights.
  static const _accentSoft = Color(0xFFD4956E);

  // Dark mode surfaces — near-black with subtle warmth.
  static const _backgroundDark = Color(0xFF0E0E11);
  static const _surfaceDark = Color(0xFF16161B);
  static const _cardDark = Color(0xFF1D1D24);
  static const _borderDark = Color(0xFF2A2A33);

  // Light mode surfaces — warm off-whites.
  static const _backgroundLight = Color(0xFFF7F6F4);
  static const _surfaceLight = Color(0xFFFFFFFF);
  static const _cardLight = Color(0xFFFFFFFF);
  static const _borderLight = Color(0xFFE8E6E2);

  // Text.
  static const _textPrimaryDark = Color(0xFFEAEAEF);
  static const _textSecondaryDark = Color(0xFF84848F);
  static const _textPrimaryLight = Color(0xFF1A1A1E);
  static const _textSecondaryLight = Color(0xFF6E6E7A);

  // Semantic.
  static const _errorColor = Color(0xFFDC4F47);
  static const _warningColor = Color(0xFFDFA040);

  // Shared radii.
  static const _radiusSm = 10.0;
  static const _radiusMd = 14.0;
  static const _radiusLg = 20.0;
  static const _radiusXl = 24.0;

  /// Exposed success colour for status indicators.
  static const Color success = Color(0xFF4BA87A);

  /// Light theme.
  static ThemeData get light => _buildTheme(Brightness.light);

  /// Dark theme.
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final textPrimary = isDark ? _textPrimaryDark : _textPrimaryLight;
    final textSecondary = isDark ? _textSecondaryDark : _textSecondaryLight;
    final bg = isDark ? _backgroundDark : _backgroundLight;
    final surface = isDark ? _surfaceDark : _surfaceLight;
    final card = isDark ? _cardDark : _cardLight;
    final border = isDark ? _borderDark : _borderLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: _accent,
      onPrimary: Colors.white,
      secondary: isDark ? _cardDark : _surfaceLight,
      onSecondary: textPrimary,
      tertiary: _warningColor,
      onTertiary: Colors.black,
      error: _errorColor,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: card,
      outline: border,
      outlineVariant: isDark ? _borderDark.withAlpha(100) : _borderLight,
    );

    // ── Typography — Plus Jakarta Sans ──────────────────────────────────
    final baseTextTheme = isDark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(baseTextTheme)
        .copyWith(
          headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.6,
            height: 1.2,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.4,
            height: 1.25,
          ),
          headlineSmall: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            height: 1.35,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            height: 1.4,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: textPrimary,
            height: 1.5,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: textSecondary,
            height: 1.45,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: textSecondary,
            height: 1.4,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            height: 1.3,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textSecondary,
            height: 1.3,
          ),
          labelSmall: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: textSecondary,
            letterSpacing: 0.2,
            height: 1.3,
          ),
        );

    // Shared button label style.
    final buttonLabel = GoogleFonts.plusJakartaSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: bg,

      // ── App bar — flat, airy ────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
      ),

      // ── Cards — soft shadow, generous radius ────────────────────────
      cardTheme: CardThemeData(
        color: card,
        elevation: isDark ? 0 : 2,
        shadowColor: isDark ? Colors.transparent : Colors.black.withAlpha(18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: isDark ? BorderSide(color: border) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),

      // ── FAB ─────────────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: isDark ? 6 : 3,
        highlightElevation: isDark ? 10 : 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
        ),
      ),

      // ── Input fields — warm fill, generous padding ──────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? _cardDark : const Color(0xFFF3F2F0),
        hoverColor: isDark ? _borderDark : const Color(0xFFEBEAE6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: const BorderSide(color: _errorColor),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary.withAlpha(140)),
        prefixIconColor: textSecondary,
      ),

      // ── Buttons ─────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd),
          ),
          textStyle: buttonLabel,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: isDark ? 3 : 1,
          shadowColor: isDark ? _accent.withAlpha(50) : Colors.black12,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd),
          ),
          textStyle: buttonLabel,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd),
          ),
          side: BorderSide(color: border, width: 1.5),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Segmented buttons ───────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _accent;
            return card;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return textPrimary;
          }),
          side: WidgetStateProperty.all(BorderSide(color: border)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusSm),
            ),
          ),
        ),
      ),

      // ── Chips ───────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: _accentSoft.withAlpha(50),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),

      // ── Dividers ────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      // ── List tiles — airy vertical padding ─────────────────────────
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        tileColor: Colors.transparent,
        selectedTileColor: _accent.withAlpha(isDark ? 22 : 28),
        iconColor: textSecondary,
      ),

      // ── Bottom sheet ────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? _surfaceDark : _surfaceLight,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusXl)),
        ),
      ),

      // ── Dialog ──────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? _surfaceDark : _surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusXl),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
      ),

      // ── Snackbar ────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? _cardDark : const Color(0xFF2A2A30),
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Tab bar ─────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: _accent,
        unselectedLabelColor: textSecondary,
        indicatorColor: _accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Progress indicators ─────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: border,
        circularTrackColor: border,
      ),

      // ── Icons ───────────────────────────────────────────────────────
      iconTheme: IconThemeData(color: textSecondary, size: 22),

      // ── Popup menu ──────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          side: isDark ? BorderSide(color: border) : BorderSide.none,
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: textPrimary,
        ),
        elevation: isDark ? 4 : 8,
        shadowColor: isDark ? Colors.black45 : Colors.black.withAlpha(25),
      ),

      // ── Expansion tile ──────────────────────────────────────────────
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: textSecondary,
        collapsedIconColor: textSecondary,
        textColor: textPrimary,
        collapsedTextColor: textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
      ),
    );
  }

  /// Monospace text style for terminal/code content.
  static TextStyle get monoStyle =>
      GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w400);

  /// Accent gradient for special elements.
  static LinearGradient get accentGradient => const LinearGradient(
    colors: [_accent, _accentSoft],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Soft elevation shadow for cards and panels.
  static List<BoxShadow> glowShadow([Color? color]) => [
    BoxShadow(
      color: (color ?? _accent).withAlpha(30),
      blurRadius: 24,
      spreadRadius: -4,
    ),
  ];
}
