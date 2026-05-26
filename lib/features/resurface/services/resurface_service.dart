import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_utils.dart';
import '../models/resurface_card.dart';

class ResurfaceService {
  static const _defaultExcludedFolders = [
    'Interesting',
    '.obsidian',
    'Templates',
    'Attachments',
  ];

  static Future<List<ResurfaceCard>> scan(
    String vaultPath, {
    List<String> excludedFolders = _defaultExcludedFolders,
  }) async {
    final cards = <ResurfaceCard>[];
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
          final card = _extractFrontBack(entry.path, content);
          if (card != null) cards.add(card);
        } catch (_) {}
      }
    } catch (_) {}
    return cards;
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

  static ResurfaceCard? _extractFrontBack(String filePath, String content) {
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

      return ResurfaceCard(
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
