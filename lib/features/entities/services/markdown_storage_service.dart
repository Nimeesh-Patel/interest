import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/collection.dart';
import '../models/entity.dart';
import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../core/vault_service.dart';
import 'entity_file_parser.dart';
import 'entity_file_writer.dart';

typedef AppData =
    ({
      List<Entity> entities,
      List<Collection> collections,
      List<String> tags,
      List<String> errors,
    });

class MarkdownStorageService {
  String? _vaultPath;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<AppData> loadData({String? vaultPathOverride}) async {
    try {
      _vaultPath = vaultPathOverride ?? await VaultService.getVaultPath();
      final vaultPath = _vaultPath;
      if (vaultPath == null) return _defaultData();

      final entities = <Entity>[];
      final corrupted = <String>[];
      final errors = <String>[];

      final scanned = await CurrentVaultContent.scan(
        vaultPath,
        use: CurrentVaultUse.entity,
      );
      errors.addAll(scanned.errors);
      for (final entry in scanned.files) {
        try {
          final content = await entry.readAsString();
          if (kDebugMode && EntityFileParser.isCorruptedHusk(content)) {
            corrupted.add(entry.path);
          }
          final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
          if (!EntityFileParser.isEntityFrontmatter(yaml)) continue;
          final result = EntityFileParser.parseEntityFile(content, entry.path);
          entities.add(result.entity);
        } catch (error) {
          final relative = p.relative(entry.path, from: vaultPath);
          errors.add('Could not read collection note "$relative": $error');
        }
      }

      final byId = <String, List<Entity>>{};
      for (final entity in entities) {
        byId.putIfAbsent(entity.id, () => []).add(entity);
      }
      final conflictedIds = <String>{};
      final sortedIds = byId.keys.toList()..sort();
      for (final id in sortedIds) {
        final matches = byId[id]!;
        if (matches.length < 2) continue;
        conflictedIds.add(id);
        final paths =
            matches
                .map(
                  (entity) => p.relative(entity.sourcePath!, from: vaultPath),
                )
                .toList()
              ..sort();
        errors.add('Duplicate active entity id "$id": ${paths.join(', ')}');
      }
      entities.removeWhere((entity) => conflictedIds.contains(entity.id));

      if (kDebugMode && corrupted.isNotEmpty) {
        debugPrint(
          '⚠ MarkdownStorageService: ${corrupted.length} possible '
          'corrupted note husk(s) (entity-ish frontmatter over an H1-only '
          'body) — review for content restoration:\n  ${corrupted.join('\n  ')}',
        );
      }

      final collNames = <String, String>{};
      for (final entity in entities) {
        if (entity.collection.isNotEmpty) {
          collNames.putIfAbsent(entity.collectionId, () => entity.collection);
        }
      }
      final collections =
          collNames.entries
              .map((e) => Collection(id: e.key, name: e.value))
              .toList();
      final tags = entities.expand((e) => e.tags).toSet().toList()..sort();

      return (
        entities: entities,
        collections: collections,
        tags: tags,
        errors: errors,
      );
    } catch (error) {
      return _defaultData(errors: ['Collection discovery failed: $error']);
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
        if (!CurrentVaultContent.isEligible(
          vaultPath,
          existingPath,
          use: CurrentVaultUse.entity,
        )) {
          return null;
        }
        final existing = await File(existingPath).readAsString();
        await File(existingPath).writeAsString(
          EntityFileWriter.patchFrontmatter(
            existingContent: existing,
            entity: entity,
          ),
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
      final vaultPath = _vaultPath ?? await VaultService.getVaultPath();
      if (path != null &&
          vaultPath != null &&
          CurrentVaultContent.isEligible(
            vaultPath,
            path,
            use: CurrentVaultUse.entity,
          )) {
        await File(path).delete();
      }
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
      generateUniqueId(
        name,
        existing.map((e) => e.id).toSet(),
        fallback: 'entity',
      );

  static String generateCollectionId(String name, List<Collection> existing) =>
      generateUniqueId(
        name,
        existing.map((c) => c.id).toSet(),
        fallback: 'collection',
      );

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
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case 'alpha_rev':
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
      default:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return sorted;
  }

  // ── Diagnostics ──────────────────────────────────────────────────────────

  /// Scans [vaultPath] for notes matching the June 2026 corruption signature
  /// (see [EntityFileParser.isCorruptedHusk]). Read-only; never writes.
  static Future<List<String>> findCorruptedNotes(String vaultPath) async {
    final hits = <String>[];
    try {
      final scanned = await CurrentVaultContent.scan(
        vaultPath,
        use: CurrentVaultUse.entity,
      );
      for (final entry in scanned.files) {
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

  AppData _defaultData({List<String> errors = const []}) => (
    entities: <Entity>[],
    collections: <Collection>[],
    tags: <String>[],
    errors: errors,
  );
}
