import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get appTitle => GoogleFonts.ibmPlexSans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get sectionHeader => GoogleFonts.ibmPlexSans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 1.3,
      );

  static TextStyle get entityName => GoogleFonts.ibmPlexSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyLarge => GoogleFonts.ibmPlexSans(
        fontSize: 16,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => GoogleFonts.ibmPlexSans(
        fontSize: 14,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodySmall => GoogleFonts.ibmPlexSans(
        fontSize: 13,
        color: AppColors.textSecondary,
      );

  static TextStyle get meta => GoogleFonts.ibmPlexSans(
        fontSize: 12,
        color: AppColors.textSecondary,
      );

  static TextStyle get metaMuted => GoogleFonts.ibmPlexSans(
        fontSize: 11,
        color: AppColors.textTertiary,
      );

  static TextStyle get cardAnswer => GoogleFonts.ibmPlexSerif(
        fontSize: 17,
        height: 1.78,
        color: AppColors.textPrimary,
      );

  static TextStyle get navLabel => GoogleFonts.ibmPlexSans(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );
}
