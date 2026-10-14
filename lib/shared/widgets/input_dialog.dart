import 'package:flutter/material.dart';

/// The dialog widget owns its controller through the entire route transition.
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hintText,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  TextCapitalization capitalization = TextCapitalization.sentences,
}) => showDialog<String>(
  context: context,
  builder:
      (_) => _InputDialog(
        title: title,
        initialValue: initialValue,
        hintText: hintText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        capitalization: capitalization,
      ),
);

class _InputDialog extends StatefulWidget {
  final String title, initialValue, confirmLabel, cancelLabel;
  final String? hintText;
  final TextCapitalization capitalization;
  const _InputDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.capitalization,
  });
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _controller.text.trim();
    Navigator.pop(context, value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.hintText),
      textCapitalization: widget.capitalization,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _confirm(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.cancelLabel),
      ),
      TextButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
    ],
  );
}
