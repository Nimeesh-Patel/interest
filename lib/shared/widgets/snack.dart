import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// Canonical transient feedback. Every snackbar in the app goes through this —
/// never call ScaffoldMessenger/SnackBar directly in screens.
void showSnack(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      backgroundColor: isError ? AppColors.destructive : null,
    ),
  );
}
