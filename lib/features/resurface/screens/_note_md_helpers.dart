import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/constants/app_theme.dart';
import '../../../shared/markdown/md_utils.dart';

MarkdownStyleSheet noteMarkdownStyle(BuildContext context, {Color? textColor}) {
  final color = textColor ?? AppColors.textPrimary;
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    h1: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.3,
        color: color),
    h2: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.35, color: color),
    h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: color),
    p: TextStyle(fontSize: 16, height: 1.6, color: color),
    listBullet: TextStyle(fontSize: 16, height: 1.6, color: color),
    a: const TextStyle(color: AppColors.accent, decoration: TextDecoration.none),
  );
}

Widget noteMarkdownBody(
  BuildContext context,
  String data, {
  Color? textColor,
  required void Function(String text, String? href, String title) onTapLink,
}) =>
    MarkdownBody(
      data: substituteWikilinks(data),
      styleSheet: noteMarkdownStyle(context, textColor: textColor),
      onTapLink: onTapLink,
    );

void onNoteLinkTap(
  String? href,
  Future<void> Function(String targetName) onNavigateToNote,
) {
  if (href == null) return;
  if (href.startsWith('wikilink:')) {
    final target = Uri.decodeComponent(href.substring('wikilink:'.length));
    onNavigateToNote(target);
  } else if (href.startsWith('http:') || href.startsWith('https:')) {
    launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
  }
}
