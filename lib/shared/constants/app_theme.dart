import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF111111);
  static const Color surfaceElevated = Color(0xFF161616);
  static const Color border = Color(0xFF1E1E1E);
  static const Color borderMid = Color(0xFF282828);
  static const Color textPrimary = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFF595959);
  static const Color textTertiary = Color(0xFF2C2C2C);
  static const Color accent = Color(0xFF8B7CF6);
  static const Color accentDim = Color(0xFF1C1835);
  static const Color destructive = Color(0xFFE05252);
  // Semantic score colour — amber is meaningful (rating/quality signal)
  static const Color score = Color(0xFFFFB800);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: AppColors.background,
    secondary: AppColors.accentDim,
    onSecondary: AppColors.accent,
    error: AppColors.destructive,
    onError: AppColors.background,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    inverseSurface: AppColors.textPrimary,
    onInverseSurface: AppColors.background,
    inversePrimary: AppColors.accentDim,
    surfaceContainerHighest: AppColors.surfaceElevated,
    surfaceContainer: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    surfaceDim: AppColors.background,
    surfaceBright: AppColors.surfaceElevated,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      actionsIconTheme: const IconThemeData(color: AppColors.textSecondary),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textTertiary,
      selectedIconTheme: const IconThemeData(size: 24),
      unselectedIconTheme: const IconThemeData(size: 24),
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: GoogleFonts.ibmPlexSans(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      unselectedLabelStyle: GoogleFonts.ibmPlexSans(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: AppColors.surface,
      filled: true,
      hintStyle: const TextStyle(color: AppColors.textTertiary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 0,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
      subtitleTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      minVerticalPadding: 12,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accentDim,
      foregroundColor: AppColors.accent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: AppColors.textPrimary),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(AppColors.background),
      side: const BorderSide(color: AppColors.accentDim, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.surface,
      side: BorderSide(color: AppColors.border),
      labelStyle: TextStyle(color: AppColors.textSecondary),
      selectedColor: AppColors.accentDim,
      secondaryLabelStyle: TextStyle(color: AppColors.accent),
      secondarySelectedColor: AppColors.accentDim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      linearTrackColor: AppColors.border,
      color: AppColors.accent,
    ),
    textTheme: TextTheme(
      bodyLarge: GoogleFonts.ibmPlexSans(color: AppColors.textPrimary, fontSize: 16),
      bodyMedium: GoogleFonts.ibmPlexSans(color: AppColors.textPrimary, fontSize: 14),
      bodySmall: GoogleFonts.ibmPlexSans(color: AppColors.textSecondary, fontSize: 12),
      labelSmall: GoogleFonts.ibmPlexSans(color: AppColors.textTertiary, fontSize: 11),
      titleLarge: GoogleFonts.ibmPlexSans(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleMedium: GoogleFonts.ibmPlexSans(color: AppColors.textPrimary, fontSize: 16),
      titleSmall: GoogleFonts.ibmPlexSans(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
      ),
      headlineSmall: GoogleFonts.ibmPlexSans(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surfaceElevated),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
  );
}
