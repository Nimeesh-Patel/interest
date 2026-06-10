import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// The app's floating action button: every screen-level primary action uses
/// this one widget, parameterized by icon and action. 52×52, dim accent fill,
/// translucent accent border — calmer than the Material default.
class AppFab extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;

  const AppFab({
    super.key,
    this.icon = Icons.add,
    this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fab = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.accentDim,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.33)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.accent, size: 24),
      ),
    );
    return tooltip == null ? fab : Tooltip(message: tooltip!, child: fab);
  }
}
