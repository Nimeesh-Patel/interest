import 'package:flutter/material.dart';

/// A centered empty-state widget with an optional icon and a message.
class EmptyState extends StatelessWidget {
  final String message;
  final IconData? icon;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.message,
    this.icon,
    this.iconSize = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: Colors.grey.shade400),
            const SizedBox(height: 16),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
