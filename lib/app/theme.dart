import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme configuration for the Flutty app.
/// Inspired by premium terminal tooling with a liquid-glass aesthetic.
abstract final class FluttyTheme {
  static const _accentTeal = Color(0xFF3EDBC2);
  static const _accentTealDeep = Color(0xFF1B8E82);
  static const _accentBlue = Color(0xFF69A7FF);
  static const _accentViolet = Color(0xFF8E7CFF);
  static const _accentGlow = Color(0xFF7AF0E0);
  static const _backgroundDark = Color(0xFF060814);
  static const _surfaceDark = Color(0xFF0E1321);
  static const _surfaceDarkSoft = Color(0xFF151B2C);
  static const _surfaceDarkStrong = Color(0xFF1B2338);
  static const _borderDark = Color(0xFF2A3554);
  static const _textPrimaryDark = Color(0xFFF5F7FF);
  static const _textSecondaryDark = Color(0xFFAAB5D6);
  static const _backgroundLight = Color(0xFFF1F6FF);
  static const _surfaceLight = Color(0xFFFFFFFF);
  static const _surfaceLightSoft = Color(0xFFF7FAFF);
  static const _surfaceLightStrong = Color(0xFFEAF0FB);
  static const _borderLight = Color(0xFFD5E0F2);
  static const _textPrimaryLight = Color(0xFF10182B);
  static const _textSecondaryLight = Color(0xFF60708E);
  static const _errorColor = Color(0xFFFF5F7A);

  /// Light theme.
  static ThemeData get light => _buildTheme(Brightness.light);

  /// Dark theme.
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme = isDark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final textTheme = GoogleFonts.interTextTheme(baseTextTheme).copyWith(
      headlineLarge: GoogleFonts.inter(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: isDark ? _textSecondaryDark : _textSecondaryLight,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: isDark ? _textSecondaryDark : _textSecondaryLight,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? _textPrimaryDark : _textPrimaryLight,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: isDark ? _textSecondaryDark : _textSecondaryLight,
      ),
    );

    final colorScheme =
        ColorScheme.fromSeed(
          brightness: brightness,
          seedColor: _accentTeal,
          primary: isDark ? _accentGlow : _accentTealDeep,
          secondary: _accentBlue,
          tertiary: _accentViolet,
          surface: isDark ? _surfaceDark : _surfaceLight,
          error: _errorColor,
        ).copyWith(
          primary: isDark ? _accentGlow : _accentTealDeep,
          onPrimary: Colors.white,
          secondary: isDark
              ? _accentBlue.withAlpha(240)
              : const Color(0xFF376ED6),
          onSecondary: Colors.white,
          tertiary: isDark
              ? _accentViolet.withAlpha(240)
              : const Color(0xFF635BDB),
          onTertiary: Colors.white,
          surface: isDark ? _surfaceDark : _surfaceLight,
          onSurface: isDark ? _textPrimaryDark : _textPrimaryLight,
          surfaceContainerLowest: isDark
              ? const Color(0xFF05070F)
              : _surfaceLight,
          surfaceContainerLow: isDark
              ? const Color(0xFF0A0F1B)
              : _surfaceLightSoft,
          surfaceContainer: isDark ? _surfaceDark : _surfaceLightSoft,
          surfaceContainerHigh: isDark ? _surfaceDarkSoft : _surfaceLightStrong,
          surfaceContainerHighest: isDark
              ? _surfaceDarkStrong
              : _surfaceLightStrong,
          outline: isDark ? _borderDark : _borderLight,
          outlineVariant: isDark
              ? _borderDark.withAlpha(178)
              : _borderLight.withAlpha(220),
          shadow: Colors.black,
          scrim: Colors.black.withAlpha(210),
          surfaceTint: isDark ? _accentGlow : _accentTealDeep,
        );

    final baseSurfaceColor = isDark
        ? _surfaceDark.withAlpha(214)
        : _surfaceLight.withAlpha(226);
    final filledSurfaceColor = isDark
        ? _surfaceDarkStrong.withAlpha(194)
        : Colors.white.withAlpha(214);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: baseSurfaceColor,
      canvasColor: baseSurfaceColor,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: filledSurfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: filledSurfaceColor,
        hoverColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _errorColor, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withAlpha(190),
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: filledSurfaceColor,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary.withAlpha(isDark ? 84 : 44);
            }
            return filledSurfaceColor;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSurface;
            }
            return colorScheme.onSurfaceVariant;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: colorScheme.outlineVariant),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: filledSurfaceColor,
        selectedColor: colorScheme.primary.withAlpha(isDark ? 70 : 40),
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        tileColor: Colors.transparent,
        selectedTileColor: colorScheme.primary.withAlpha(isDark ? 38 : 24),
        iconColor: colorScheme.onSurfaceVariant,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: baseSurfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: filledSurfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? _surfaceDarkStrong.withAlpha(236)
            : const Color(0xFF111827).withAlpha(232),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 24),
      popupMenuTheme: PopupMenuThemeData(
        color: filledSurfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: colorScheme.primary.withAlpha(isDark ? 76 : 38),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: isSelected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.1,
          );
        }),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        collapsedIconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        collapsedTextColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  /// Monospace text style for terminal and code content.
  static TextStyle get monoStyle =>
      GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w400);

  /// Accent gradient for premium, high-emphasis elements.
  static LinearGradient get accentGradient => const LinearGradient(
    colors: [_accentTeal, _accentBlue, _accentViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Returns a soft glow shadow stack for emphasized UI elements.
  static List<BoxShadow> glowShadow([Color? color]) => [
    BoxShadow(
      color: (color ?? _accentTeal).withAlpha(64),
      blurRadius: 28,
      spreadRadius: -8,
      offset: const Offset(0, 12),
    ),
  ];
}

/// Paints the ambient gradient backdrop used behind the app shell.
class FluttyAmbientBackground extends StatelessWidget {
  /// Creates a [FluttyAmbientBackground].
  const FluttyAmbientBackground({required this.child, super.key});

  /// Descendant content rendered on top of the ambient background.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  FluttyTheme._backgroundDark,
                  const Color(0xFF08111D),
                  FluttyTheme._backgroundDark,
                ]
              : [
                  FluttyTheme._backgroundLight,
                  const Color(0xFFEDF4FF),
                  const Color(0xFFFDFEFF),
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -120,
            left: -90,
            child: _AmbientOrb(
              size: 300,
              colors: [Color(0x663EDBC2), Color(0x003EDBC2)],
            ),
          ),
          const Positioned(
            top: 110,
            right: -120,
            child: _AmbientOrb(
              size: 320,
              colors: [Color(0x4469A7FF), Color(0x0069A7FF)],
            ),
          ),
          Positioned(
            bottom: -150,
            left: MediaQuery.sizeOf(context).width * 0.18,
            child: const _AmbientOrb(
              size: 360,
              colors: [Color(0x338E7CFF), Color(0x008E7CFF)],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withAlpha(isDark ? 12 : 120),
                      Colors.transparent,
                      Colors.black.withAlpha(isDark ? 40 : 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A reusable frosted surface for the app's liquid-glass treatment.
class FluttyGlassSurface extends StatelessWidget {
  /// Creates a [FluttyGlassSurface].
  const FluttyGlassSurface({
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.tintColor,
    this.borderColor,
    this.blurSigma = 22,
    super.key,
  });

  /// Descendant content rendered inside the glass surface.
  final Widget child;

  /// Optional padding applied around [child].
  final EdgeInsetsGeometry? padding;

  /// Optional margin applied outside the glass surface.
  final EdgeInsetsGeometry? margin;

  /// The shared radius used to clip and decorate the surface.
  final BorderRadius borderRadius;

  /// Optional tint blended into the surface fill.
  final Color? tintColor;

  /// Optional border color override.
  final Color? borderColor;

  /// Blur amount applied behind the glass surface.
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final resolvedTint =
        tintColor ??
        (isDark ? const Color(0x33172034) : Colors.white.withAlpha(204));
    final topColor = isDark
        ? Color.alphaBlend(colorScheme.primary.withAlpha(30), resolvedTint)
        : Color.alphaBlend(Colors.white.withAlpha(166), resolvedTint);
    final bottomColor = isDark
        ? Color.alphaBlend(colorScheme.secondary.withAlpha(18), resolvedTint)
        : Color.alphaBlend(colorScheme.primary.withAlpha(18), resolvedTint);
    final resolvedBorderColor =
        borderColor ??
        (isDark
            ? Colors.white.withAlpha(34)
            : colorScheme.outlineVariant.withAlpha(210));

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 72 : 18),
            blurRadius: isDark ? 34 : 24,
            spreadRadius: -10,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: colorScheme.primary.withAlpha(isDark ? 18 : 10),
            blurRadius: 16,
            spreadRadius: -12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: resolvedBorderColor),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [topColor, bottomColor],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withAlpha(isDark ? 94 : 196),
                            Colors.white.withAlpha(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (padding == null)
                  child
                else
                  Padding(padding: padding!, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    ),
  );
}
