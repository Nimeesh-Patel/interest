import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/constants/app_theme.dart';
import '../../../shared/markdown/md_utils.dart';

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

  MarkdownStyleSheet _mdStyle(BuildContext context, {Color? textColor}) {
    final color = textColor ?? AppColors.textPrimary;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      h1: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.3, color: color),
      h2: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.35, color: color),
      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: color),
      p: TextStyle(fontSize: 16, height: 1.6, color: color),
      listBullet: TextStyle(fontSize: 16, height: 1.6, color: color),
      a: const TextStyle(color: AppColors.accent, decoration: TextDecoration.none),
    );
  }

  void _onTapLink(String text, String? href, String title) {
    if (href == null) return;
    if (href.startsWith('wikilink:')) {
      final target = Uri.decodeComponent(href.substring('wikilink:'.length));
      widget.onNavigateToNote(target);
    } else if (href.startsWith('http:') || href.startsWith('https:')) {
      launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    }
  }

  Widget _mdBody(BuildContext context, String data, {Color? textColor}) =>
      MarkdownBody(
        data: substituteWikilinks(data),
        styleSheet: _mdStyle(context, textColor: textColor),
        onTapLink: _onTapLink,
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
