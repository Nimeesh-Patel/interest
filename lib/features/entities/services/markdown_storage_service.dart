import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../core/vault_service.dart';

typedef AppData = ({
  List<Entity> entities,
  List<Category> categories,
  List<String> tags,
  List<EntityLink> entityLinks,
});

// ── Section type registry ────────────────────────────────────────────────────

enum SectionType { wikilinks, list, generic }

// Sections the app owns semantically. Everything else is user territory.
const Map<String, SectionType> _semanticSections = {
  'Why Interesting': SectionType.list,
  'Related': SectionType.wikilinks,
  'Sources': SectionType.list,
};

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

      final vaultDir = Directory(vaultPath);
      await for (final entry in vaultDir.list(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final rel = p.relative(entry.path, from: vaultPath);
        final folders = p.split(rel)..removeLast();
        if (folders.any((s) => s == '.obsidian' || s == 'Templates')) continue;
        try {
          final content = await entry.readAsString();
          final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
          if (yaml == null || !yaml.containsKey('category')) continue;
          final result = _parseEntityFile(content, entry.path);
          entities.add(result.entity);
          pendingRelated[result.entity.id] = result.relatedNames;
          final catId = result.entity.categoryId;
          if (!catNames.containsKey(catId) && result.categoryName.isNotEmpty) {
            catNames[catId] = result.categoryName;
          }
        } catch (_) {}
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
      final scanDir = Directory(vaultPath);
      await for (final entry in scanDir.list(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final rel = p.relative(entry.path, from: vaultPath);
        final folders = p.split(rel)..removeLast();
        if (folders.any((s) => s == '.obsidian' || s == 'Templates')) continue;
        try {
          final content = await entry.readAsString();
          final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
          if (yaml == null || !yaml.containsKey('category')) continue;
          final alias = yaml['alias']?.toString();
          if (alias != null) existingAliasToPath[alias] = entry.path;
        } catch (_) {}
      }

      final currentAliases = snapEntities.map((e) => e.id).toSet();

      for (final entity in snapEntities) {
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

        if (oldPath != null && oldPath != newPath) {
          try { await File(oldPath).delete(); } catch (_) {}
        }

        // Patch existing file or build from template for new entities
        final existingFilePath = oldPath ?? (await File(newPath).exists() ? newPath : null);
        String content;

        if (existingFilePath != null) {
          try {
            final existingContent = await File(existingFilePath).readAsString();
            content = _patchEntityContent(
              existingContent: existingContent,
              entity: entity,
              categoryName: categoryName,
              relatedEntityNames: relatedNames,
            );
          } catch (_) {
            content = await _buildNewEntityContent(
              entity: entity,
              categoryName: categoryName,
              relatedEntityNames: relatedNames,
            );
          }
        } else {
          content = await _buildNewEntityContent(
            entity: entity,
            categoryName: categoryName,
            relatedEntityNames: relatedNames,
          );
        }

        await File(newPath).writeAsString(content);
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

  // ── Private: parse ─────────────────────────────────────────────────────────

  static ({Entity entity, List<String> relatedNames, String categoryName})
      _parseEntityFile(String content, String filePath) {
    final split = splitFrontmatter(content);
    final body = split.body;
    final basename = p.basenameWithoutExtension(filePath);

    String alias = slugify(basename).isEmpty ? 'entity' : slugify(basename);
    String categoryName = '';
    double? score;
    List<String> tags = [];
    String? watchedDate;
    String? letterboxdUrl;
    String? tmdbId;
    final now = DateTime.now().millisecondsSinceEpoch;
    int createdAt = now;
    int updatedAt = now;

    final yaml = parseYamlMap(split.frontmatter);
    if (yaml != null) {
      final rawAlias = yaml['alias'];
      if (rawAlias != null) {
        final a = slugify(rawAlias.toString());
        if (a.isNotEmpty) { alias = a; }
      }
      categoryName = yaml['category']?.toString() ?? '';
      final rawScore = yaml['score'];
      if (rawScore is num) score = rawScore.toDouble();
      final rawTags = yaml['tags'];
      if (rawTags is YamlList) {
        tags = rawTags.map((t) => t.toString()).toList();
      }
      createdAt = parseIsoToMs(yaml['created_at']?.toString()) ?? now;
      updatedAt = parseIsoToMs(yaml['updated_at']?.toString()) ?? createdAt;
      watchedDate = yaml['watched_date']?.toString();
      letterboxdUrl = yaml['letterboxd_url']?.toString();
      tmdbId = yaml['tmdb_id']?.toString();
    }

    final name = extractH1(body) ?? basename;

    // Dynamic section parse — discovers ALL sections in the file
    final rawSections = parseSectionsH2(body);
    final notes = parseSectionAsList(rawSections['Why Interesting'] ?? '');
    final links = parseSectionAsList(rawSections['Sources'] ?? '');
    final relatedNames = {
      ...parseSectionAsWikilinks(rawSections['Related'] ?? ''),
      ...extractWikilinks(body),
    }.toList();

    final catId = categoryName.isEmpty
        ? 'uncategorized'
        : (slugify(categoryName).isEmpty ? 'uncategorized' : slugify(categoryName));

    final entity = Entity(
      id: alias,
      name: name,
      categoryId: catId,
      notes: notes,
      links: links,
      tags: tags,
      score: score,
      createdAt: createdAt,
      updatedAt: updatedAt,
      rawSections: rawSections,
      watchedDate: watchedDate,
      letterboxdUrl: letterboxdUrl,
      tmdbId: tmdbId,
    );

    return (entity: entity, relatedNames: relatedNames, categoryName: categoryName);
  }

  // ── Private: frontmatter builder ───────────────────────────────────────────

  static String _buildFrontmatter({
    required Entity entity,
    required String categoryName,
  }) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('alias: ${entity.id}');
    buf.writeln('category: $categoryName');
    if (entity.score != null) {
      buf.writeln('score: ${entity.score!.toStringAsFixed(1)}');
    }
    if (entity.watchedDate != null) buf.writeln('watched_date: ${entity.watchedDate}');
    if (entity.letterboxdUrl != null) buf.writeln('letterboxd_url: ${entity.letterboxdUrl}');
    if (entity.tmdbId != null) buf.writeln('tmdb_id: ${entity.tmdbId}');
    if (entity.tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final tag in entity.tags) {
        buf.writeln('  - $tag');
      }
    }
    buf.writeln('created_at: ${msToIso(entity.createdAt)}');
    buf.writeln('updated_at: ${msToIso(entity.updatedAt)}');
    buf.write('---');
    return buf.toString();
  }

  // ── Private: semantic section renderer ─────────────────────────────────────

  static String _renderSemanticSection(
    String sectionName,
    Entity entity,
    List<String> relatedEntityNames,
  ) {
    switch (sectionName) {
      case 'Why Interesting':
        return entity.notes.map((n) => '- $n').join('\n');
      case 'Sources':
        return entity.links.map((l) => '- $l').join('\n');
      case 'Related':
        return relatedEntityNames.map((n) => '- [[$n]]').join('\n');
      default:
        return '';
    }
  }

  // ── Private: section-aware patch ───────────────────────────────────────────

  static String _patchEntityContent({
    required String existingContent,
    required Entity entity,
    required String categoryName,
    required List<String> relatedEntityNames,
  }) {
    final split = splitFrontmatter(existingContent);
    final body = split.body;
    final rawSections = parseSectionsH2(body);

    final newFrontmatter = _buildFrontmatter(
      entity: entity,
      categoryName: categoryName,
    );

    final buf = StringBuffer();
    buf.writeln('# ${entity.name}');

    for (final sectionName in rawSections.keys) {
      buf.writeln();
      buf.writeln('## $sectionName');

      if (_semanticSections.containsKey(sectionName)) {
        final rendered = _renderSemanticSection(sectionName, entity, relatedEntityNames);
        if (rendered.isNotEmpty) {
          buf.writeln();
          buf.write(rendered);
        }
      } else {
        // Unknown section — preserve exactly as found
        final raw = rawSections[sectionName]!;
        if (raw.isNotEmpty) {
          buf.writeln();
          buf.write(raw);
        }
      }
    }

    // Append semantic sections that exist in app data but were absent from the file
    for (final sectionName in _semanticSections.keys) {
      if (!rawSections.containsKey(sectionName)) {
        final rendered = _renderSemanticSection(sectionName, entity, relatedEntityNames);
        if (rendered.isNotEmpty) {
          buf.writeln();
          buf.writeln('## $sectionName');
          buf.writeln();
          buf.write(rendered);
        }
      }
    }

    return '$newFrontmatter\n${buf.toString().trimRight()}\n';
  }

  // ── Private: template system ───────────────────────────────────────────────

  Future<String?> _loadTemplate(String categoryName) async {
    try {
      final vaultPath = _vaultPath;
      if (vaultPath == null) return null;
      final tdir = VaultService.templatesPath(vaultPath);
      final slug = slugify(categoryName);

      if (slug.isNotEmpty) {
        final catFile = File(p.join(tdir, '$slug.md'));
        if (await catFile.exists()) {
          final content = await catFile.readAsString();
          if (_isTemplate(content)) return content;
        }
      }

      final defaultFile = File(p.join(tdir, 'default.md'));
      if (await defaultFile.exists()) {
        final content = await defaultFile.readAsString();
        if (_isTemplate(content)) return content;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isTemplate(String content) {
    final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
    return yaml != null && yaml['template'] == true;
  }

  static String _instantiateTemplate(String templateContent, String title) =>
      templateContent.replaceAll('{{title}}', title);

  // ── Private: new entity content builder ────────────────────────────────────

  Future<String> _buildNewEntityContent({
    required Entity entity,
    required String categoryName,
    required List<String> relatedEntityNames,
  }) async {
    final templateContent = await _loadTemplate(categoryName);
    if (templateContent != null) {
      final instantiated = _instantiateTemplate(templateContent, entity.name);
      return _patchEntityContent(
        existingContent: instantiated,
        entity: entity,
        categoryName: categoryName,
        relatedEntityNames: relatedEntityNames,
      );
    }
    // legacy-fallback
    return _buildEntityMarkdown(
      entity: entity,
      categoryName: categoryName,
      relatedEntityNames: relatedEntityNames,
    );
  }

  // ── Private: write (legacy-fallback) ───────────────────────────────────────

  // Kept as ultimate fallback for when no template is available and no existing
  // file can be patched. Intentionally does NOT include movie-specific fields
  // (watchedDate, letterboxdUrl, tmdbId) — those are only written by _buildFrontmatter.
  static String _buildEntityMarkdown({
    required Entity entity,
    required String categoryName,
    required List<String> relatedEntityNames,
  }) {
    final buf = StringBuffer();

    buf.writeln('---');
    buf.writeln('alias: ${entity.id}');
    buf.writeln('category: $categoryName');
    if (entity.score != null) {
      buf.writeln('score: ${entity.score!.toStringAsFixed(1)}');
    }
    if (entity.tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final tag in entity.tags) {
        buf.writeln('  - $tag');
      }
    }
    buf.writeln('created_at: ${msToIso(entity.createdAt)}');
    buf.writeln('updated_at: ${msToIso(entity.updatedAt)}');
    buf.writeln('---');
    buf.writeln('# ${entity.name}');

    if (entity.notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Why Interesting');
      buf.writeln();
      for (final note in entity.notes) {
        buf.writeln('- $note');
      }
    }

    if (relatedEntityNames.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Related');
      buf.writeln();
      for (final name in relatedEntityNames) {
        buf.writeln('- [[$name]]');
      }
    }

    if (entity.links.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Sources');
      buf.writeln();
      for (final link in entity.links) {
        buf.writeln('- $link');
      }
    }

    return buf.toString();
  }

  // ── Frontmatter patches ────────────────────────────────────────────────────

  static Future<void> patchAnkiNoteId(String filePath, int noteId) =>
      patchFrontmatterField(filePath, 'anki_note_id', '$noteId');

  // ── Private: defaults ──────────────────────────────────────────────────────

  AppData _defaultData() => (
        entities: <Entity>[],
        categories: [Category(id: 'people', name: 'People')],
        tags: <String>[],
        entityLinks: <EntityLink>[],
      );
}
