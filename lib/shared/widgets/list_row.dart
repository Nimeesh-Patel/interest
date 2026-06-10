import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../constants/app_theme.dart';

/// A list row with the app's hairline bottom border, optionally tappable.
/// Every bordered list row (sources, decks, recent notes, entities, projects)
/// builds on this; the border style changes here and nowhere else.
/// With no [onTap]/[onLongPress] the child is wrapped without an InkWell —
/// useful when the child handles its own taps (e.g. a ListTile).
class ListRow extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const ListRow({
    super.key,
    this.onTap,
    this.onLongPress,
    this.padding =
        const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 14),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: (onTap == null && onLongPress == null)
          ? content
          : InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );
  }
}
