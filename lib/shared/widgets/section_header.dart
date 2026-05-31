import 'package:flutter/material.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final double bottomGap;
  final double topGap;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.bottomGap = 8,
    this.topGap = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: bottomGap),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: AppTextStyles.sectionHeader.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
