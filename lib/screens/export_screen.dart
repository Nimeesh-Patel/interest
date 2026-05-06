import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/category.dart';
import '../services/storage_service.dart';

class ExportScreen extends StatefulWidget {
  final StorageService storage;

  const ExportScreen({super.key, required this.storage});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isLoading = true;
  bool _isExporting = false;
  late _ExportData _data;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final raw = await widget.storage.loadData();
    if (mounted) {
      setState(() {
        _data = _ExportData(raw);
        _isLoading = false;
      });
    }
  }

  Future<void> _export(String format) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      late String content;
      late String ext;

      switch (format) {
        case 'json':
          ext = 'json';
          content = _buildJson();
        case 'md':
          ext = 'md';
          content = _buildMarkdown();
        case 'txt':
          ext = 'txt';
          content = _buildTxt();
        default:
          return;
      }

      final file = File('${dir.path}/export_$ts.$ext');
      await file.writeAsString(content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${file.path}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _buildJson() {
    final raw = _data.raw;
    final map = {
      'entities': raw.entities.map((e) => e.toJson()).toList(),
      'categories': raw.categories.map((c) => c.toJson()).toList(),
      'tags': raw.tags,
      'entity_links': raw.entityLinks.map((l) => l.toJson()).toList(),
      'boards': raw.boards.map((b) => b.toJson()).toList(),
      'board_entities': raw.boardEntities.map((be) => be.toJson()).toList(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(map);
  }

  String _buildMarkdown() {
    final raw = _data.raw;
    final buf = StringBuffer();

    buf.writeln('# Entities');
    buf.writeln();

    for (final e in raw.entities) {
      buf.writeln('## ${e.name}');
      buf.writeln();
      final cat = raw.categories
          .firstWhere((c) => c.id == e.categoryId,
              orElse: () => Category(id: '', name: ''))
          .name;
      if (cat.isNotEmpty) buf.writeln('Category: $cat  ');
      if (e.tags.isNotEmpty) buf.writeln('Tags: ${e.tags.join(', ')}  ');
      if (e.score != null) buf.writeln('Score: ${e.score!.toStringAsFixed(1)}  ');
      buf.writeln();

      if (e.notes.isNotEmpty) {
        buf.writeln('### Why it matters');
        buf.writeln();
        for (final n in e.notes) {
          buf.writeln('* $n');
        }
        buf.writeln();
      }

      if (e.links.isNotEmpty) {
        buf.writeln('### Sources');
        buf.writeln();
        for (final l in e.links) {
          buf.writeln('* $l');
        }
        buf.writeln();
      }

      buf.writeln('---');
      buf.writeln();
    }

    if (raw.boards.isNotEmpty) {
      buf.writeln('# Boards');
      buf.writeln();
      for (final b in raw.boards) {
        buf.writeln('## ${b.name}');
        buf.writeln();
        final memberIds = raw.boardEntities
            .where((be) => be.boardId == b.id)
            .map((be) => be.entityId)
            .toSet();
        final members =
            raw.entities.where((e) => memberIds.contains(e.id)).toList();
        if (members.isEmpty) {
          buf.writeln('*(empty)*');
        } else {
          for (final e in members) {
            buf.writeln('* ${e.name}');
          }
        }
        buf.writeln();
      }
    }

    return buf.toString();
  }

  String _buildTxt() {
    final raw = _data.raw;
    final buf = StringBuffer();

    for (final e in raw.entities) {
      buf.writeln('ENTITY: ${e.name}');
      final cat = raw.categories
          .firstWhere((c) => c.id == e.categoryId,
              orElse: () => Category(id: '', name: ''))
          .name;
      if (cat.isNotEmpty) buf.writeln('  Category: $cat');
      if (e.tags.isNotEmpty) buf.writeln('  Tags: ${e.tags.join(', ')}');
      if (e.score != null) buf.writeln('  Score: ${e.score!.toStringAsFixed(1)}');
      if (e.notes.isNotEmpty) {
        buf.writeln('  Notes:');
        for (final n in e.notes) {
          buf.writeln('    - $n');
        }
      }
      if (e.links.isNotEmpty) {
        buf.writeln('  Sources:');
        for (final l in e.links) {
          buf.writeln('    - $l');
        }
      }
      buf.writeln();
    }

    if (raw.boards.isNotEmpty) {
      for (final b in raw.boards) {
        buf.writeln('BOARD: ${b.name}');
        final memberIds = raw.boardEntities
            .where((be) => be.boardId == b.id)
            .map((be) => be.entityId)
            .toSet();
        final members =
            raw.entities.where((e) => memberIds.contains(e.id)).toList();
        for (final e in members) {
          buf.writeln('  - ${e.name}');
        }
        buf.writeln();
      }
    }

    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final raw = _data.raw;
    final entityCount = raw.entities.length;
    final boardCount = raw.boards.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '$entityCount ${entityCount == 1 ? 'entity' : 'entities'}'
              '${boardCount > 0 ? ' · $boardCount ${boardCount == 1 ? 'board' : 'boards'}' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Files are saved to the app documents directory.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Divider(),
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Exporting…'),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('Export JSON'),
            subtitle: const Text('Full data dump', style: TextStyle(fontSize: 12)),
            onTap: _isExporting ? null : () => _export('json'),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Export Markdown'),
            subtitle: const Text('Structured readable format',
                style: TextStyle(fontSize: 12)),
            onTap: _isExporting ? null : () => _export('md'),
          ),
          ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Export TXT'),
            subtitle:
                const Text('Plain text', style: TextStyle(fontSize: 12)),
            onTap: _isExporting ? null : () => _export('txt'),
          ),
        ],
      ),
    );
  }
}

class _ExportData {
  final AppData raw;
  _ExportData(this.raw);
}
