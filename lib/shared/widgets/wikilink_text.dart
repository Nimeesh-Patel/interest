import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// Renders [text] as a [RichText] with `[[wikilinks]]` highlighted in the
/// theme's primary color with an underline. Non-link spans use [style].
///
/// When [strikethrough] is true, applies strikethrough decoration to the
/// entire run (used for completed task items).
class WikilinkText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool strikethrough;

  const WikilinkText({
    super.key,
    required this.text,
    required this.style,
    this.strikethrough = false,
  });

  @override
  Widget build(BuildContext context) {
    const linkColor = AppColors.accent;
    final baseDecoration =
        strikethrough ? TextDecoration.lineThrough : TextDecoration.none;

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in RegExp(r'\[\[([^\]]+)\]\]').allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: style.copyWith(decoration: baseDecoration),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: style.copyWith(
          color: linkColor,
          decoration: strikethrough
              ? TextDecoration.lineThrough
              : TextDecoration.none,
        ),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: style.copyWith(decoration: baseDecoration),
      ));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: text,
        style: style.copyWith(decoration: baseDecoration),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }
}
