import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// Canonical transient feedback. Every snackbar in the app goes through this.
void showSnack(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: isError ? const TextStyle(color: AppColors.danger) : null,
      ),
      duration: duration,
    ),
  );
}
