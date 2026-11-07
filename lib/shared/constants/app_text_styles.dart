import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Two voices: IBM Plex Sans for the app's own chrome, IBM Plex Serif for the
/// author's words (a card's problem and conjecture), so it is always clear
/// whose text is on screen. Hierarchy comes from colour and weight before
/// size; nothing is set below 13 px or in all caps.
class AppTextStyles {
  AppTextStyles._();

  /// Screen titles.
  static TextStyle get title => GoogleFonts.ibmPlexSans(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: AppColors.ink,
  );

  /// The single most important statement on a screen (sync status).
  static TextStyle get statement => GoogleFonts.ibmPlexSans(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.ink,
  );

  /// Section and card headings.
  static TextStyle get heading => GoogleFonts.ibmPlexSans(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.ink,
  );

  static TextStyle get body =>
      GoogleFonts.ibmPlexSans(fontSize: 16, height: 1.5, color: AppColors.ink);

  static TextStyle get bodyMuted => GoogleFonts.ibmPlexSans(
    fontSize: 15,
    height: 1.5,
    color: AppColors.inkMuted,
  );

  /// Labels, counts and metadata.
  static TextStyle get small => GoogleFonts.ibmPlexSans(
    fontSize: 13,
    height: 1.4,
    color: AppColors.inkFaint,
  );

  static TextStyle get smallStrong => GoogleFonts.ibmPlexSans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.inkMuted,
  );

  /// The author's problem side.
  static TextStyle get problem => GoogleFonts.ibmPlexSerif(
    fontSize: 17,
    height: 1.55,
    color: AppColors.ink,
  );

  /// The author's conjecture side: quieter than the problem it answers.
  static TextStyle get conjecture => GoogleFonts.ibmPlexSerif(
    fontSize: 16,
    height: 1.6,
    color: AppColors.inkMuted,
  );
}
