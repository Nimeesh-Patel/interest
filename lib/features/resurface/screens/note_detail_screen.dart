import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/constants/app_theme.dart';
import '../../../shared/markdown/md_utils.dart';
import '_note_md_helpers.dart';

/// Body-only note viewer. No Scaffold — the caller (ResurfaceScreen) owns the
/// AppBar. Navigation out of this widget goes via [onNavigateToNote].
class NoteDetailScreen extends StatefulWidget {
  final String filePath;
  final Future<void> Function(String targetName) onNavigateToNote;

  const NoteDetailScreen({
    super.key,
    required this.filePath,
    required this.onNavigateToNote,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  String? _front;
  String? _back;
  String? _plainContent;
  bool _backRevealed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoteDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      setState(() {
        _front = null;
        _back = null;
        _plainContent = null;
        _backRevealed = false;
        _loading = true;
      });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final raw = await File(widget.filePath).readAsString();
      final split = splitFrontmatter(raw);
      final fb = splitFrontBack(split.body);
      if (!mounted) return;
      setState(() {
        if (fb != null) {
          _front = fb.front;
          _back = fb.back;
          _plainContent = null;
        } else {
          _front = null;
          _back = null;
          _plainContent = split.body;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _mdBody(BuildContext context, String data, {Color? textColor}) =>
      noteMarkdownBody(
        context,
        data,
        textColor: textColor,
        onTapLink: (_, href, _) =>
            onNoteLinkTap(href, widget.onNavigateToNote),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_front != null && _back != null) {
      return GestureDetector(
        onTap: () => setState(() => _backRevealed = !_backRevealed),
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _mdBody(context, _front!),
              const SizedBox(height: 24),
              if (!_backRevealed)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'tap to reveal',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                )
              else ...[
                const Divider(thickness: 1, color: AppColors.border),
                const SizedBox(height: 16),
                _mdBody(context, _back!, textColor: AppColors.textPrimary),
              ],
            ],
          ),
        ),
      );
    }

    if (_plainContent != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _mdBody(context, _plainContent!),
      );
    }

    return const Center(child: Text('Could not load note.'));
  }
}
