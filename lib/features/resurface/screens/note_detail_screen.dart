import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_utils.dart';
import '../services/resurface_service.dart';

class NoteDetailScreen extends StatefulWidget {
  final String vaultPath;
  final String filePath;

  const NoteDetailScreen({
    super.key,
    required this.vaultPath,
    required this.filePath,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await File(widget.filePath).readAsString();
      final split = splitFrontmatter(raw);
      if (!mounted) return;
      setState(() {
        _content = split.body;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String get _title {
    final basename = p.basename(widget.filePath);
    final dot = basename.lastIndexOf('.');
    return dot > 0 ? basename.substring(0, dot) : basename;
  }

  MarkdownStyleSheet _mdStyle(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      h1: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.3, color: color),
      h2: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.35, color: color),
      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: color),
      p: TextStyle(fontSize: 15, height: 1.55, color: color),
      listBullet: TextStyle(fontSize: 15, height: 1.55, color: color),
    );
  }

  void _onTapLink(String text, String? href, String title) {
    if (href == null || !href.startsWith('wikilink:')) return;
    final target = Uri.decodeComponent(href.substring('wikilink:'.length));
    _navigateToNote(target);
  }

  Future<void> _navigateToNote(String targetName) async {
    final path = await ResurfaceService.resolveWikilink(widget.vaultPath, targetName);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note not found: $targetName')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          vaultPath: widget.vaultPath,
          filePath: path,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_content == null) {
      body = const Center(child: Text('Could not load note.'));
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: MarkdownBody(
          data: substituteWikilinks(_content!),
          styleSheet: _mdStyle(context),
          onTapLink: _onTapLink,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        child: body,
      ),
    );
  }
}
