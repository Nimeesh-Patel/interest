import 'package:flutter/material.dart';

import '../constants/app_text_styles.dart';
import '../constants/app_theme.dart';

/// Filled accent pill — the primary action button (card viewer "Next",
/// quick-add "Add"). Dims to [AppColors.accentDim] when [enabled] is false.
class AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final IconData? trailingIcon;
  final EdgeInsetsGeometry padding;

  const AccentButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.trailingIcon,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: enabled ? AppColors.accent : AppColors.accentDim,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                )),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              Icon(trailingIcon, size: 14, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}
