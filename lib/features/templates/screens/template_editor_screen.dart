import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/progress.dart';
import '../../../shared/widgets/snack.dart';

class TemplateEditorScreen extends StatefulWidget {
  final String filePath;
  final String displayName;

  const TemplateEditorScreen({
    super.key,
    required this.filePath,
    required this.displayName,
  });

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  late TextEditingController _controller;
  bool _dirty = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final content = await File(widget.filePath).readAsString();
      if (mounted) {
        _controller.text = content;
        _controller.addListener(_onChanged);
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    try {
      await File(widget.filePath).writeAsString(_controller.text);
      if (mounted) {
        setState(() => _dirty = false);
        showSnack(context, 'Saved', duration: const Duration(seconds: 1));
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Failed to save');
    }
  }

  Future<bool> _maybeDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your unsaved edits will be lost.',
      confirmLabel: 'Discard',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _maybeDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.displayName),
          backgroundColor: AppColors.background,
          actions: [
            TextButton(
              onPressed: _dirty ? _save : null,
              child: Text(
                'Save',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _dirty ? AppColors.accent : AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const LoadingState()
            : Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
      ),
    );
  }
}
