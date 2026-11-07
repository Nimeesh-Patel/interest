import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Interest's palette, taken from its own icon (#5BA8C4) on a blue-tinted
/// charcoal rather than pure black.
///
/// Every text colour clears WCAG AA (4.5:1) on every surface it can sit on;
/// the faintest, [inkFaint], is 5.0:1 on [raised]. Measured ratios are noted
/// beside each token: re-measure before changing one, because unreadable
/// secondary text (2.8:1 and 1.4:1) was the previous palette's main failure.
class AppColors {
  AppColors._();

  // Surfaces, darkest to lightest.
  static const Color canvas = Color(0xFF121518);
  static const Color card = Color(0xFF1B1F24);
  static const Color raised = Color(0xFF252A31);

  /// Hairline separators only; not a component boundary.
  static const Color line = Color(0xFF2F353D);

  /// Boundaries of interactive controls (≥3:1 against [card]).
  static const Color outline = Color(0xFF6B7480);

  static const Color ink = Color(0xFFE8ECF0); // 13.9:1 on card
  static const Color inkMuted = Color(0xFFB3BBC5); // 8.5:1 on card
  static const Color inkFaint = Color(0xFF9199A4); // 5.8:1 on card, 5.0 raised

  static const Color accent = Color(0xFF73C2DD); // 8.3:1 on card
  static const Color onAccent = Color(0xFF0B2632); // 7.8:1 on accent
  static const Color accentTint = Color(0xFF173341);

  static const Color success = Color(0xFF7FD3A2);
  static const Color successTint = Color(0xFF16302A);
  static const Color warning = Color(0xFFEDC36B);
  static const Color warningTint = Color(0xFF33291A);
  static const Color danger = Color(0xFFF38B83);
  static const Color dangerTint = Color(0xFF3A2224);
}

/// Spacing scale (logical pixels). Layouts use these, never ad-hoc numbers.
class Space {
  Space._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter.
  static const double gutter = 20;
}

class Radii {
  Radii._();
  static const double control = 12;
  static const double card = 18;
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    primaryContainer: AppColors.accentTint,
    onPrimaryContainer: AppColors.accent,
    secondary: AppColors.inkMuted,
    onSecondary: AppColors.canvas,
    error: AppColors.danger,
    onError: AppColors.canvas,
    errorContainer: AppColors.dangerTint,
    onErrorContainer: AppColors.danger,
    surface: AppColors.canvas,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    surfaceContainerLowest: AppColors.canvas,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.raised,
    surfaceContainerHighest: AppColors.raised,
    outline: AppColors.outline,
    outlineVariant: AppColors.line,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.canvas,
    inversePrimary: AppColors.onAccent,
  );
  final sans = GoogleFonts.ibmPlexSansTextTheme(
    ThemeData.dark().textTheme,
  ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.control),
  );
  const controlPadding = EdgeInsets.symmetric(
    horizontal: Space.xl,
    vertical: 14,
  );
  final buttonLabel = GoogleFonts.ibmPlexSans(
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: sans,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      actionsIconTheme: const IconThemeData(color: AppColors.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        disabledBackgroundColor: AppColors.raised,
        disabledForegroundColor: AppColors.inkFaint,
        minimumSize: const Size.fromHeight(52),
        padding: controlPadding,
        shape: controlShape,
        textStyle: buttonLabel,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.outline),
        minimumSize: const Size.fromHeight(48),
        padding: controlPadding,
        shape: controlShape,
        textStyle: buttonLabel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: buttonLabel,
        shape: controlShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.inkMuted,
        minimumSize: const Size(48, 48),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.inkMuted,
      textColor: AppColors.ink,
      titleTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        color: AppColors.ink,
      ),
      subtitleTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 14,
        color: AppColors.inkMuted,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      minVerticalPadding: Space.md,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      titleTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 19,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
      ),
      contentTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 15,
        height: 1.5,
        color: AppColors.inkMuted,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.raised,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 15,
        color: AppColors.ink,
      ),
      actionTextColor: AppColors.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: const TextStyle(color: AppColors.inkFaint),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: 14,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.line,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
