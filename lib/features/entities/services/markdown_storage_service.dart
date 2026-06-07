import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/collection.dart';
import '../models/entity.dart';
import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../../../core/vault_service.dart';
import 'entity_file_parser.dart';
import 'entity_file_writer.dart';

typedef AppData = ({
  List<Entity> entities,
  List<Collection> collections,
  List<String> tags,
});

class MarkdownStorageService {
  String? _vaultPath;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<AppData> loadData() async {
    try {
      _vaultPath = await VaultService.getVaultPath();
      final vaultPath = _vaultPath;
      if (vaultPath == null) return _defaultData();

      final entities = <Entity>[];
      final collNames = <String, String>{};
      final corrupted = <String>[];

      await for (final entry in VaultScanner.scan(
        vaultPath,
        excludedFolders: const {'.obsidian', 'Templates'},
      )) {
        try {
          final content = await entry.readAsString();
          if (kDebugMode && EntityFileParser.isCorruptedHusk(content)) {
            corrupted.add(entry.path);
          }
          final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
          if (!EntityFileParser.isEntityFrontmatter(yaml)) continue;
          final result = EntityFileParser.parseEntityFile(content, entry.path);
          entities.add(result.entity);
          final cid = result.entity.collectionId;
          if (!collNames.containsKey(cid) && result.collectionName.isNotEmpty) {
            collNames[cid] = result.collectionName;
          }
        } catch (_) {}
      }

      if (kDebugMode && corrupted.isNotEmpty) {
        debugPrint('⚠ MarkdownStorageService: ${corrupted.length} possible '
            'corrupted note husk(s) (entity-ish frontmatter over an H1-only '
            'body) — review for content restoration:\n  ${corrupted.join('\n  ')}');
      }

      final collections = collNames.entries
          .map((e) => Collection(id: e.key, name: e.value))
          .toList();
      final tags = entities.expand((e) => e.tags).toSet().toList()..sort();

      return (entities: entities, collections: collections, tags: tags);
    } catch (_) {
      return _defaultData();
    }
  }

  // ── Per-file writes ─────────────────────────────────────────────────────────
  // Each mutation touches exactly one entity file and never rewrites a body.

  /// Creates the entity's file if it has no [Entity.sourcePath] yet, otherwise
  /// patches that file's frontmatter in place (body preserved verbatim).
  /// Sets [Entity.sourcePath] on creation. Returns the path, or null on error.
  Future<String?> saveEntity(Entity entity) async {
    try {
      final vaultPath = _vaultPath ?? await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      _vaultPath = vaultPath;

      final existingPath = entity.sourcePath;
      if (existingPath != null && await File(existingPath).exists()) {
        final existing = await File(existingPath).readAsString();
        await File(existingPath).writeAsString(
          EntityFileWriter.patchFrontmatter(
              existingContent: existing, entity: entity),
        );
        return existingPath;
      }

      // New entity: write to vault root under a non-colliding filename.
      final base = sanitizeFilename(entity.name);
      var newPath = p.join(vaultPath, '$base.md');
      var n = 2;
      while (await File(newPath).exists()) {
        newPath = p.join(vaultPath, '$base $n.md');
        n++;
      }
      await File(newPath).writeAsString(
        EntityFileWriter.buildNewEntity(collection: entity.collection),
      );
      entity.sourcePath = newPath;
      return newPath;
    } catch (e, st) {
      debugPrint('MarkdownStorageService.saveEntity error: $e\n$st');
      return null;
    }
  }

  /// Deletes the entity's backing file. Never throws.
  Future<void> deleteEntity(Entity entity) async {
    try {
      final path = entity.sourcePath;
      if (path != null) await File(path).delete();
    } catch (_) {}
  }

  /// Repoints [members] to collection [newName] by patching each file's
  /// `collection:` value in place.
  Future<void> renameCollection(List<Entity> members, String newName) async {
    for (final e in members) {
      e.collection = newName;
      await saveEntity(e);
    }
  }

  // ── Static helpers ─────────────────────────────────────────────────────────

  static String generateEntityId(String name, List<Entity> existing) =>
      generateUniqueId(name, existing.map((e) => e.id).toSet(), fallback: 'entity');

  static String generateCollectionId(String name, List<Collection> existing) =>
      generateUniqueId(name, existing.map((c) => c.id).toSet(), fallback: 'collection');

  static List<Entity> sortEntities(List<Entity> entities, String sortOrder) {
    final sorted = List<Entity>.from(entities);
    switch (sortOrder) {
      case 'latest':
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case 'oldest':
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'high_score':
        sorted.sort((a, b) {
          if (a.score == null && b.score == null) return 0;
          if (a.score == null) return 1;
          if (b.score == null) return -1;
          return b.score!.compareTo(a.score!);
        });
      case 'low_score':
        sorted.sort((a, b) {
          if (a.score == null && b.score == null) return 0;
          if (a.score == null) return 1;
          if (b.score == null) return -1;
          return a.score!.compareTo(b.score!);
        });
      case 'alpha':
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'alpha_rev':
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      default:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return sorted;
  }

  // ── Frontmatter patches ────────────────────────────────────────────────────

  static Future<void> patchAnkiNoteId(String filePath, int noteId) =>
      patchFrontmatterField(filePath, 'anki_note_id', '$noteId');

  // ── Diagnostics ──────────────────────────────────────────────────────────

  /// Scans [vaultPath] for notes matching the June 2026 corruption signature
  /// (see [EntityFileParser.isCorruptedHusk]). Read-only; never writes.
  static Future<List<String>> findCorruptedNotes(String vaultPath) async {
    final hits = <String>[];
    try {
      await for (final entry in VaultScanner.scan(
        vaultPath,
        excludedFolders: const {'.obsidian', 'Templates'},
      )) {
        try {
          if (EntityFileParser.isCorruptedHusk(await entry.readAsString())) {
            hits.add(entry.path);
          }
        } catch (_) {}
      }
    } catch (_) {}
    return hits;
  }

  // ── Private: defaults ──────────────────────────────────────────────────────

  AppData _defaultData() =>
      (entities: <Entity>[], collections: <Collection>[], tags: <String>[]);
}
