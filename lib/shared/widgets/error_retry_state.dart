import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// Screen-level error state with a retry action. Same structural role as
/// [EmptyState] and [LoadingState] — a full-area placeholder body.
class ErrorRetryState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  const ErrorRetryState({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.destructive, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
