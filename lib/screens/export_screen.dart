import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
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
  bool _isImporting = false;
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

  // ── Export ────────────────────────────────────────────────────────────────

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

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _import() async {
    if (_isImporting) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file picker: $e')),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid JSON file.')),
        );
      }
      return;
    }

    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import data'),
        content: const Text(
          'Merge adds new items without removing existing ones.\n'
          'Replace all overwrites everything.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Merge')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Replace all')),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    setState(() => _isImporting = true);
    try {
      if (choice == 'replace') {
        await _replaceData(parsed);
      } else {
        await _mergeData(parsed);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import complete.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _mergeData(Map<String, dynamic> parsed) async {
    final current = _data.raw;

    final importedEntities = (parsed['entities'] as List? ?? [])
        .map((e) => Entity.fromJson(e as Map<String, dynamic>))
        .toList();
    final importedCategories = (parsed['categories'] as List? ?? [])
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
    final importedLinks = (parsed['entity_links'] as List? ?? [])
        .map((l) => EntityLink.fromJson(l as Map<String, dynamic>))
        .toList();
    final importedBoards = (parsed['boards'] as List? ?? [])
        .map((b) => Board.fromJson(b as Map<String, dynamic>))
        .toList();
    final importedBoardEntities = (parsed['board_entities'] as List? ?? [])
        .map((be) => BoardEntity.fromJson(be as Map<String, dynamic>))
        .toList();
    final importedTags = (parsed['tags'] as List? ?? []).cast<String>();

    final existingEntityIds = current.entities.map((e) => e.id).toSet();
    final existingCategoryIds = current.categories.map((c) => c.id).toSet();
    final existingLinkIds = current.entityLinks.map((l) => l.id).toSet();
    final existingBoardIds = current.boards.map((b) => b.id).toSet();
    final existingBoardEntityKeys = current.boardEntities
        .map((be) => '${be.boardId}|${be.entityId}')
        .toSet();

    final mergedEntities = [
      ...current.entities,
      ...importedEntities.where((e) => !existingEntityIds.contains(e.id)),
    ];
    final mergedCategories = [
      ...current.categories,
      ...importedCategories.where((c) => !existingCategoryIds.contains(c.id)),
    ];
    final mergedLinks = [
      ...current.entityLinks,
      ...importedLinks.where((l) => !existingLinkIds.contains(l.id)),
    ];
    final mergedBoards = [
      ...current.boards,
      ...importedBoards.where((b) => !existingBoardIds.contains(b.id)),
    ];
    final mergedBoardEntities = [
      ...current.boardEntities,
      ...importedBoardEntities.where((be) =>
          !existingBoardEntityKeys.contains('${be.boardId}|${be.entityId}')),
    ];
    final mergedTags = {...current.tags, ...importedTags}.toList();

    widget.storage.saveData(
      entities: mergedEntities,
      categories: mergedCategories,
      tags: mergedTags,
      entityLinks: mergedLinks,
      boards: mergedBoards,
      boardEntities: mergedBoardEntities,
    );
    await _loadData();
  }

  Future<void> _replaceData(Map<String, dynamic> parsed) async {
    final entities = (parsed['entities'] as List? ?? [])
        .map((e) => Entity.fromJson(e as Map<String, dynamic>))
        .toList();
    final categories = (parsed['categories'] as List? ?? [])
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
    final links = (parsed['entity_links'] as List? ?? [])
        .map((l) => EntityLink.fromJson(l as Map<String, dynamic>))
        .toList();
    final boards = (parsed['boards'] as List? ?? [])
        .map((b) => Board.fromJson(b as Map<String, dynamic>))
        .toList();
    final boardEntities = (parsed['board_entities'] as List? ?? [])
        .map((be) => BoardEntity.fromJson(be as Map<String, dynamic>))
        .toList();
    final tags = (parsed['tags'] as List? ?? []).cast<String>();

    widget.storage.saveData(
      entities: entities,
      categories: categories,
      tags: tags,
      entityLinks: links,
      boards: boards,
      boardEntities: boardEntities,
    );
    await _loadData();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
        title: const Text('Export / Import'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '$entityCount ${entityCount == 1 ? 'entity' : 'entities'}'
              '${boardCount > 0 ? ' · $boardCount ${boardCount == 1 ? 'board' : 'boards'}' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Exported files are saved to the app documents directory.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Divider(),

          // Import section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Import',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey)),
          ),
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Importing…'),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import JSON'),
            subtitle: const Text(
                'Merge or replace from a previously exported file',
                style: TextStyle(fontSize: 12)),
            onTap: (_isImporting || _isExporting) ? null : _import,
          ),
          const Divider(),

          // Export section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Export',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey)),
          ),
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            onTap: (_isExporting || _isImporting) ? null : () => _export('json'),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Export Markdown'),
            subtitle: const Text('Structured readable format',
                style: TextStyle(fontSize: 12)),
            onTap: (_isExporting || _isImporting) ? null : () => _export('md'),
          ),
          ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Export TXT'),
            subtitle: const Text('Plain text', style: TextStyle(fontSize: 12)),
            onTap: (_isExporting || _isImporting) ? null : () => _export('txt'),
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
