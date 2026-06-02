import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_utils.dart';
import '../models/problem_note.dart';
import '../models/resurface_note.dart';

class ResurfaceService {
  static const _defaultExcludedFolders = [
    '.obsidian',
    'Templates',
    'Attachments',
  ];

  static Future<List<ProblemNote>> scan(
    String vaultPath, {
    List<String> excludedFolders = _defaultExcludedFolders,
  }) async {
    final problemNotes = <ProblemNote>[];
    try {
      final vaultDir = Directory(vaultPath);
      await for (final entry in vaultDir.list(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final relative = p.relative(entry.path, from: vaultPath);
        final segments = p.split(relative);
        // Skip filename itself (last segment), check folder segments only
        final folders = segments.sublist(0, segments.length - 1);
        if (folders.any((seg) => excludedFolders.contains(seg))) continue;
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml != null && yaml['exclude_resurface'] == true) continue;
          final card = _extractFrontBack(entry.path, content);
          if (card != null) problemNotes.add(card);
        } catch (_) {}
      }
    } catch (_) {}
    return problemNotes;
  }

  /// Searches the whole vault (no folder exclusions) for a .md file whose
  /// basename without extension matches [targetName] case-insensitively.
  /// Returns the absolute path on match, null otherwise. Never throws.
  static Future<String?> resolveWikilink(
    String vaultPath,
    String targetName,
  ) async {
    try {
      final target = targetName.toLowerCase();
      final vaultDir = Directory(vaultPath);
      await for (final entry in vaultDir.list(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        if (p.basenameWithoutExtension(entry.path).toLowerCase() == target) {
          return entry.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns every vault note that passes folder exclusion, regardless of `***` presence.
  /// Single scan; `isProblemNote`/`front`/`back` indicate whether a separator was found.
  /// Never throws.
  static Future<List<ResurfaceNote>> getAllNotes(
    String vaultPath, {
    List<String> excludedFolders = _defaultExcludedFolders,
  }) async {
    final notes = <ResurfaceNote>[];
    try {
      final vaultDir = Directory(vaultPath);
      await for (final entry in vaultDir.list(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final relative = p.relative(entry.path, from: vaultPath);
        final segments = p.split(relative);
        final folders = segments.sublist(0, segments.length - 1);
        if (folders.any((seg) => excludedFolders.contains(seg))) continue;
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml != null && yaml['exclude_resurface'] == true) continue;
          final fb = splitFrontBack(split.body);
          notes.add(ResurfaceNote(
            sourcePath: entry.path,
            sourceFile: p.basename(entry.path),
            body: split.body,
            isProblemNote: fb != null,
            front: fb?.front,
            back: fb?.back,
            decks: parseDeckMetadata(split.frontmatter),
            category: yaml != null && yaml['category'] is String
                ? yaml['category'] as String
                : null,
            tags: yaml != null && yaml['tags'] is List
                ? (yaml['tags'] as List).whereType<String>().toList()
                : const [],
            ankiNoteId: yaml != null && yaml['anki_note_id'] != null
                ? '${yaml['anki_note_id']}'
                : null,
          ));
        } catch (_) {}
      }
    } catch (_) {}
    return notes;
  }

  static ProblemNote? _extractFrontBack(String filePath, String content) {
    try {
      final split = splitFrontmatter(content);
      final body = split.body;
      final decks = parseDeckMetadata(split.frontmatter);
      final lines = body.split('\n');
      bool inCodeFence = false;
      int? separatorIdx;

      final hrPattern = RegExp(r'^\*{3,}\s*$');

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('```')) {
          inCodeFence = !inCodeFence;
          continue;
        }
        if (!inCodeFence && hrPattern.hasMatch(line)) {
          separatorIdx = i;
          break;
        }
      }

      if (separatorIdx == null) return null;

      final front = lines.sublist(0, separatorIdx).join('\n').trim();
      final back = lines.sublist(separatorIdx + 1).join('\n').trim();

      if (front.isEmpty || back.isEmpty) return null;

      return ProblemNote(
        sourcePath: filePath,
        sourceFile: p.basename(filePath),
        front: front,
        back: back,
        decks: decks,
      );
    } catch (_) {
      return null;
    }
  }
}
