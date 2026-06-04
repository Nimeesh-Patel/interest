import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../models/resurface_note.dart';

class ResurfaceService {
  static const _defaultExcludedFolders = [
    '.obsidian',
    'Templates',
    'Attachments',
  ];

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
      await for (final entry in VaultScanner.scan(
        vaultPath,
        excludedFolders: excludedFolders.toSet(),
      )) {
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

  /// Reads a single vault file and returns a [ResurfaceNote].
  /// Returns null if the file cannot be read. Never throws.
  static Future<ResurfaceNote?> loadSingleNote(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final split = splitFrontmatter(content);
      final yaml = parseYamlMap(split.frontmatter);
      final fb = splitFrontBack(split.body);
      return ResurfaceNote(
        sourcePath: filePath,
        sourceFile: p.basename(filePath),
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
      );
    } catch (_) {
      return null;
    }
  }
}
