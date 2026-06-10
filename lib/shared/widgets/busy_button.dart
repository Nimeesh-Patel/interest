import 'package:flutter/material.dart';

import 'progress.dart';

/// A 44px ElevatedButton that disables itself and shows a spinner while an
/// async action runs. Used by every save/import/test action in Settings.
class BusyButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const BusyButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        child: busy ? const InlineSpinner(size: 20) : Text(label),
      ),
    );
  }
}
