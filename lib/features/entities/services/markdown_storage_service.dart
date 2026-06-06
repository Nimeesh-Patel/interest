import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:path/path.dart' as p;

import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../../../core/vault_service.dart';
import 'entity_file_parser.dart';
import 'entity_file_writer.dart';

typedef AppData = ({
  List<Entity> entities,
  List<Category> categories,
  List<String> tags,
  List<EntityLink> entityLinks,
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
      final pendingRelated = <String, List<String>>{};
      final catNames = <String, String>{};
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
          pendingRelated[result.entity.id] = result.relatedNames;
          final catId = result.entity.categoryId;
          if (!catNames.containsKey(catId) && result.categoryName.isNotEmpty) {
            catNames[catId] = result.categoryName;
          }
        } catch (_) {}
      }

      if (kDebugMode && corrupted.isNotEmpty) {
        debugPrint('⚠ MarkdownStorageService: ${corrupted.length} possible '
            'corrupted note husk(s) (entity frontmatter over an H1-only body) — '
            'review for content restoration:\n  ${corrupted.join('\n  ')}');
      }

      final categories = catNames.isEmpty
          ? [Category(id: 'people', name: 'People')]
          : catNames.entries.map((e) => Category(id: e.key, name: e.value)).toList();

      final nameToId = {for (final e in entities) e.name: e.id};
      final entityLinks = <EntityLink>[];
      pendingRelated.forEach((fromId, relatedNames) {
        for (final name in relatedNames) {
          final toId = nameToId[name];
          if (toId == null || toId == fromId) continue;
          if (!linkExists(fromId, toId, entityLinks)) {
            entityLinks.add(EntityLink(
              id: generateLinkId(fromId, toId),
              from: fromId,
              to: toId,
            ));
          }
        }
      });

      final tags = entities.expand((e) => e.tags).toSet().toList()..sort();

      return (
        entities: entities,
        categories: categories,
        tags: tags,
        entityLinks: entityLinks,
      );
    } catch (_) {
      return _defaultData();
    }
  }

  Future<void> saveData({
    required List<Entity> entities,
    required List<Category> categories,
    required List<String> tags,
    required List<EntityLink> entityLinks,
  }) async {
    final snapEntities = List<Entity>.from(entities);
    final snapCategories = List<Category>.from(categories);
    final snapLinks = List<EntityLink>.from(entityLinks);

    try {
      final vaultPath = _vaultPath;
      if (vaultPath == null) return;

      final catMap = {for (final c in snapCategories) c.id: c.name};
      final entityMap = {for (final e in snapEntities) e.id: e};

      // ── Entities ────────────────────────────────────────────────────────────

      // Vault-wide alias → path lookup: finds entities wherever they live.
      final existingAliasToPath = <String, String>{};
      await for (final entry in VaultScanner.scan(
        vaultPath,
        excludedFolders: const {'.obsidian', 'Templates'},
      )) {
        try {
          final content = await entry.readAsString();
          final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
          if (!EntityFileParser.isEntityFrontmatter(yaml)) continue;
          final alias = yaml!['alias']?.toString();
          if (alias != null) existingAliasToPath[alias] = entry.path;
        } catch (_) {}
      }

      final currentAliases = snapEntities.map((e) => e.id).toSet();

      for (final entity in snapEntities) {
        try {
          final categoryName = catMap[entity.categoryId] ?? entity.categoryId;

          final relatedNames = <String>[];
          for (final link in snapLinks) {
            String? otherId;
            if (link.from == entity.id) { otherId = link.to; }
            else if (link.to == entity.id) { otherId = link.from; }
            if (otherId != null) {
              final other = entityMap[otherId];
              if (other != null) relatedNames.add(other.name);
            }
          }

          final filename = '${sanitizeFilename(entity.name)}.md';
          final oldPath = existingAliasToPath[entity.id];
          // Existing entity: keep in the same directory (pre- or post-migration).
          // New entity: write to vault root.
          final newPath = oldPath != null
              ? p.join(p.dirname(oldPath), filename)
              : p.join(vaultPath, filename);

          // Resolve the file this write would land on, if one already exists.
          final existingFilePath =
              oldPath ?? (await File(newPath).exists() ? newPath : null);

          String content;
          if (existingFilePath != null) {
            final existingContent = await File(existingFilePath).readAsString();

            // Orchestration guard (primary defence against the June 2026
            // corruption): never overwrite a file that is not itself an entity.
            // A target lacking `alias:` is a problem note or plain note that
            // merely shares this name — skip it, keep the entity in memory, and
            // never destroy the user's content.
            final fm = parseYamlMap(splitFrontmatter(existingContent).frontmatter);
            if (!(fm?.containsKey('alias') ?? false)) {
              debugPrint('MarkdownStorageService.saveData: refusing to overwrite '
                  'non-entity file (no alias:): $existingFilePath');
              continue;
            }

            try {
              content = EntityFileWriter.patchEntityContent(
                existingContent: existingContent,
                entity: entity,
                categoryName: categoryName,
                relatedEntityNames: relatedNames,
              );
            } on StateError {
              // Writer guard fired: do NOT fall back to a rebuild — that would
              // re-create the very corruption this prevents. Re-throw to the
              // per-entity handler, which logs and skips this entity only.
              rethrow;
            } catch (_) {
              content = await EntityFileWriter.buildNewEntityContent(
                vaultPath: vaultPath,
                entity: entity,
                categoryName: categoryName,
                relatedEntityNames: relatedNames,
              );
            }
          } else {
            content = await EntityFileWriter.buildNewEntityContent(
              vaultPath: vaultPath,
              entity: entity,
              categoryName: categoryName,
              relatedEntityNames: relatedNames,
            );
          }

          // Commit: remove the old file only now that content is ready (rename).
          if (oldPath != null && oldPath != newPath) {
            try { await File(oldPath).delete(); } catch (_) {}
          }
          await File(newPath).writeAsString(content);
        } catch (e) {
          debugPrint('MarkdownStorageService.saveData: skipped "${entity.name}": $e');
        }
      }

      for (final entry in existingAliasToPath.entries) {
        if (!currentAliases.contains(entry.key)) {
          try { await File(entry.value).delete(); } catch (_) {}
        }
      }

    } catch (e, st) {
      debugPrint('MarkdownStorageService.saveData error: $e\n$st');
    }
  }

  // ── Static helpers ─────────────────────────────────────────────────────────

  static bool linkExists(String a, String b, List<EntityLink> links) =>
      links.any((l) => (l.from == a && l.to == b) || (l.from == b && l.to == a));

  static List<Entity> getRelatedEntities(
      String entityId, List<EntityLink> links, List<Entity> entities) {
    final ids = links
        .where((l) => l.from == entityId || l.to == entityId)
        .map((l) => l.from == entityId ? l.to : l.from)
        .toSet();
    return entities.where((e) => ids.contains(e.id)).toList();
  }

  static String generateLinkId(String from, String to) => '$from--$to';

  static String generateEntityId(String name, List<Entity> existing) =>
      generateUniqueId(name, existing.map((e) => e.id).toSet(), fallback: 'entity');

  static String generateCategoryId(String name, List<Category> existing) =>
      generateUniqueId(name, existing.map((c) => c.id).toSet(), fallback: 'category');

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
  /// (see [EntityFileParser.isCorruptedHusk]). Returns the matching file paths
  /// for human review. Read-only; never writes; never throws.
  ///
  /// Matches may include legitimately empty, template-less entities — the
  /// husk and the empty entity are structurally indistinguishable. Treat the
  /// result as a candidate list, not a list of certainties.
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

  AppData _defaultData() => (
        entities: <Entity>[],
        categories: [Category(id: 'people', name: 'People')],
        tags: <String>[],
        entityLinks: <EntityLink>[],
      );
}
