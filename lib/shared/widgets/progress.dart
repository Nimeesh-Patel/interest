import 'package:flutter/material.dart';

/// Screen-level loading state: the body to show while a screen's data loads.
/// Same structural role as [EmptyState] — a full-area placeholder.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Inline busy indicator for buttons, list-row trailings, and text fields.
class InlineSpinner extends StatelessWidget {
  final double size;
  final Color? color;

  const InlineSpinner({super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}
