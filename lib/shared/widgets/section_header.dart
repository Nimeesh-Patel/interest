import 'package:flutter/material.dart';

/// A bold section title with an optional trailing widget and a bottom gap.
///
/// Replaces the repeated pattern:
///   Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))
///   SizedBox(height: 8)
class SectionHeader extends StatelessWidget {
  final String title;

  /// Optional widget shown at the trailing edge (e.g. an "Add" TextButton).
  final Widget? trailing;

  final double bottomGap;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.bottomGap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        SizedBox(height: bottomGap),
      ],
    );
  }
}
