import 'package:flutter/material.dart';

/// A single menu item for [showBottomSheetMenu].
class BottomSheetMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const BottomSheetMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

/// Shows a modal bottom sheet with a column of [ListTile] items.
/// Each item's [onTap] is called after the sheet is dismissed.
void showBottomSheetMenu(
  BuildContext context, {
  required List<BottomSheetMenuItem> items,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: items
            .map(
              (item) => ListTile(
                leading: Icon(
                  item.icon,
                  color: item.isDestructive ? Colors.red : null,
                ),
                title: Text(
                  item.label,
                  style: item.isDestructive
                      ? const TextStyle(color: Colors.red)
                      : null,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  item.onTap();
                },
              ),
            )
            .toList(),
      ),
    ),
  );
}
