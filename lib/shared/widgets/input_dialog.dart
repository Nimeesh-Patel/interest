import 'package:flutter/material.dart';

/// Shows a modal AlertDialog with a single text field.
/// Returns the trimmed entered text, or null if cancelled / empty.
/// Manages its own [TextEditingController] internally.
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hintText,
  String confirmLabel = 'OK',
  TextCapitalization capitalization = TextCapitalization.sentences,
}) async {
  final ctrl = TextEditingController(text: initialValue);
  String? result;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: hintText),
        textCapitalization: capitalization,
        onSubmitted: (v) {
          final trimmed = v.trim();
          if (trimmed.isNotEmpty) result = trimmed;
          Navigator.pop(ctx);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final trimmed = ctrl.text.trim();
            if (trimmed.isNotEmpty) result = trimmed;
            Navigator.pop(ctx);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  ctrl.dispose();
  return result;
}
