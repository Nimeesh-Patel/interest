import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import 'vault_service.dart';

typedef AppData = ({
  List<Entity> entities,
  List<Category> categories,
  List<String> tags,
  List<EntityLink> entityLinks,
  List<Board> boards,
  List<BoardEntity> boardEntities,
});

class MarkdownStorageService {
  static final _wikilinkRegex = RegExp(r'\[\[([^\]]+)\]\]');
  String? _vaultPath;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<AppData> loadData() async {
    try {
      _vaultPath = await VaultService.getVaultPath();
      final vaultPath = _vaultPath;
      if (vaultPath == null) return _defaultData();

      await _migrateFromJson(vaultPath);

      final entitiesDirPath = VaultService.entitiesPath(vaultPath);
      final boardsDirPath = VaultService.boardsPath(vaultPath);

      final entities = <Entity>[];
      // entityId → list of related entity names (from ## Related wikilinks)
      final pendingRelated = <String, List<String>>{};
      // categoryId → display name (first encountered wins)
      final catNames = <String, String>{};

      final entitiesDir = Directory(entitiesDirPath);
      if (await entitiesDir.exists()) {
        final all = await entitiesDir.list().toList();
        for (final f in all.whereType<File>().where((f) => f.path.endsWith('.md'))) {
          try {
            final content = await f.readAsString();
            final result = _parseEntityFile(content, f.path);
            entities.add(result.entity);
            pendingRelated[result.entity.id] = result.relatedNames;
            final catId = result.entity.categoryId;
            if (!catNames.containsKey(catId) && result.categoryName.isNotEmpty) {
              catNames[catId] = result.categoryName;
            }
          } catch (_) {}
        }
      }

      // Derive categories from entity frontmatters
      final categories = catNames.isEmpty
          ? [Category(id: 'people', name: 'People')]
          : catNames.entries.map((e) => Category(id: e.key, name: e.value)).toList();

      // Resolve wikilinks → EntityLinks (bidirectional dedup)
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

      // Parse board files
      final boards = <Board>[];
      final boardEntities = <BoardEntity>[];

      final boardsDir = Directory(boardsDirPath);
      if (await boardsDir.exists()) {
        final all = await boardsDir.list().toList();
        for (final f in all.whereType<File>().where((f) => f.path.endsWith('.md'))) {
          try {
            final content = await f.readAsString();
            final boardName = _extractH1(content) ?? p.basenameWithoutExtension(f.path);
            final boardId = _slugify(boardName);
            if (boardId.isEmpty) continue;
            boards.add(Board(id: boardId, name: boardName));

            for (final memberName in _extractWikilinks(content)) {
              final memberId = nameToId[memberName];
              if (memberId == null) continue;
              if (!boardEntryExists(boardId, memberId, boardEntities)) {
                boardEntities.add(BoardEntity(boardId: boardId, entityId: memberId));
              }
            }
          } catch (_) {}
        }
      }

      final tags = entities.expand((e) => e.tags).toSet().toList()..sort();

      return (
        entities: entities,
        categories: categories,
        tags: tags,
        entityLinks: entityLinks,
        boards: boards,
        boardEntities: boardEntities,
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
    required List<Board> boards,
    required List<BoardEntity> boardEntities,
  }) async {
    // Snapshot before any await to avoid races with fire-and-forget callers
    final snapEntities = List<Entity>.from(entities);
    final snapCategories = List<Category>.from(categories);
    final snapLinks = List<EntityLink>.from(entityLinks);
    final snapBoards = List<Board>.from(boards);
    final snapBoardEntities = List<BoardEntity>.from(boardEntities);

    try {
      final vaultPath = _vaultPath;
      if (vaultPath == null) return;

      final entitiesDirPath = VaultService.entitiesPath(vaultPath);
      final boardsDirPath = VaultService.boardsPath(vaultPath);

      await Directory(entitiesDirPath).create(recursive: true);
      await Directory(boardsDirPath).create(recursive: true);

      final catMap = {for (final c in snapCategories) c.id: c.name};
      final entityMap = {for (final e in snapEntities) e.id: e};

      // ── Entities ────────────────────────────────────────────────────────────

      // Build alias → existing file path map (for rename detection + orphan cleanup)
      final existingAliasToPath = <String, String>{};
      final entitiesDir = Directory(entitiesDirPath);
      if (await entitiesDir.exists()) {
        final all = await entitiesDir.list().toList();
        for (final f in all.whereType<File>().where((f) => f.path.endsWith('.md'))) {
          try {
            final content = await f.readAsString();
            final split = _splitFrontmatter(content);
            if (split.frontmatter != null) {
              final yaml = loadYaml(split.frontmatter!);
              if (yaml is YamlMap) {
                final alias = yaml['alias']?.toString();
                if (alias != null) existingAliasToPath[alias] = f.path;
              }
            }
          } catch (_) {}
        }
      }

      final currentAliases = snapEntities.map((e) => e.id).toSet();

      for (final entity in snapEntities) {
        final categoryName = catMap[entity.categoryId] ?? entity.categoryId;

        // Collect names of related entities
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

        final content = _buildEntityMarkdown(
          entity: entity,
          categoryName: categoryName,
          relatedEntityNames: relatedNames,
        );

        final filename = '${_sanitizeFilename(entity.name)}.md';
        final newPath = p.join(entitiesDirPath, filename);

        // Handle rename: delete old file if it had a different name
        final oldPath = existingAliasToPath[entity.id];
        if (oldPath != null && oldPath != newPath) {
          try { await File(oldPath).delete(); } catch (_) {}
        }

        await File(newPath).writeAsString(content);
      }

      // Delete entity files whose alias is no longer in the entities list
      for (final entry in existingAliasToPath.entries) {
        if (!currentAliases.contains(entry.key)) {
          try { await File(entry.value).delete(); } catch (_) {}
        }
      }

      // ── Boards ──────────────────────────────────────────────────────────────

      // Collect existing board file paths for orphan cleanup
      final existingBoardPaths = <String>{};
      final boardsDir = Directory(boardsDirPath);
      if (await boardsDir.exists()) {
        final all = await boardsDir.list().toList();
        for (final f in all.whereType<File>().where((f) => f.path.endsWith('.md'))) {
          existingBoardPaths.add(f.path);
        }
      }

      final writtenBoardPaths = <String>{};

      for (final board in snapBoards) {
        final memberIds = snapBoardEntities
            .where((be) => be.boardId == board.id)
            .map((be) => be.entityId)
            .toSet();
        final memberNames = snapEntities
            .where((e) => memberIds.contains(e.id))
            .map((e) => e.name)
            .toList();

        final content = _buildBoardMarkdown(board: board, memberNames: memberNames);
        final filename = '${_sanitizeFilename(board.name)}.md';
        final filePath = p.join(boardsDirPath, filename);

        await File(filePath).writeAsString(content);
        writtenBoardPaths.add(filePath);
      }

      // Delete orphan board files
      for (final path in existingBoardPaths) {
        if (!writtenBoardPaths.contains(path)) {
          try { await File(path).delete(); } catch (_) {}
        }
      }
    } catch (e, st) {
      debugPrint('MarkdownStorageService.saveData error: $e\n$st');
    }
  }

  // ── Static helpers (identical API to old StorageService) ──────────────────

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

  static bool boardEntryExists(
          String boardId, String entityId, List<BoardEntity> entries) =>
      entries.any((be) => be.boardId == boardId && be.entityId == entityId);

  static String generateEntityId(String name, List<Entity> existing) =>
      _generateId(name, existing.map((e) => e.id).toSet(), fallback: 'entity');

  static String generateCategoryId(String name, List<Category> existing) =>
      _generateId(name, existing.map((c) => c.id).toSet(), fallback: 'category');

  static String generateBoardId(String name, List<Board> existing) =>
      _generateId(name, existing.map((b) => b.id).toSet(), fallback: 'board');

  // ── Private: parse ─────────────────────────────────────────────────────────

  static ({Entity entity, List<String> relatedNames, String categoryName})
      _parseEntityFile(String content, String filePath) {
    final split = _splitFrontmatter(content);
    final body = split.body;
    final basename = p.basenameWithoutExtension(filePath);

    String alias = _slugify(basename).isEmpty ? 'entity' : _slugify(basename);
    String categoryName = '';
    double? score;
    List<String> tags = [];
    final now = DateTime.now().millisecondsSinceEpoch;
    int createdAt = now;
    int updatedAt = now;

    if (split.frontmatter != null && split.frontmatter!.isNotEmpty) {
      try {
        final yaml = loadYaml(split.frontmatter!);
        if (yaml is YamlMap) {
          final rawAlias = yaml['alias'];
          if (rawAlias != null) {
            final a = _slugify(rawAlias.toString());
            if (a.isNotEmpty) { alias = a; }
          }
          categoryName = yaml['category']?.toString() ?? '';
          final rawScore = yaml['score'];
          if (rawScore is num) score = rawScore.toDouble();
          final rawTags = yaml['tags'];
          if (rawTags is YamlList) {
            tags = rawTags.map((t) => t.toString()).toList();
          }
          createdAt = _parseIsoToMs(yaml['created_at']?.toString()) ?? now;
          updatedAt = _parseIsoToMs(yaml['updated_at']?.toString()) ?? createdAt;
        }
      } catch (_) {}
    }

    final name = _extractH1(body) ?? basename;
    final notes = _extractSectionItems(body, 'Why Interesting');
    final links = _extractSectionItems(body, 'Sources');
    final relatedNames = _extractSectionWikilinks(body, 'Related');

    final catId = categoryName.isEmpty
        ? 'uncategorized'
        : (_slugify(categoryName).isEmpty ? 'uncategorized' : _slugify(categoryName));

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
    );

    return (entity: entity, relatedNames: relatedNames, categoryName: categoryName);
  }

  // ── Private: write ─────────────────────────────────────────────────────────

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
    buf.writeln('created_at: ${_msToIso(entity.createdAt)}');
    buf.writeln('updated_at: ${_msToIso(entity.updatedAt)}');
    buf.writeln('---');
    buf.writeln();
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

  static String _buildBoardMarkdown({
    required Board board,
    required List<String> memberNames,
  }) {
    final buf = StringBuffer();
    buf.writeln('# ${board.name}');
    if (memberNames.isNotEmpty) {
      buf.writeln();
      for (final name in memberNames) {
        buf.writeln('- [[$name]]');
      }
    }
    return buf.toString();
  }

  // ── Private: text parsing helpers ─────────────────────────────────────────

  static ({String? frontmatter, String body}) _splitFrontmatter(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines[0].trim() != '---') {
      return (frontmatter: null, body: content);
    }
    int closeIdx = -1;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        closeIdx = i;
        break;
      }
    }
    if (closeIdx == -1) return (frontmatter: null, body: content);
    final frontmatter = lines.sublist(1, closeIdx).join('\n');
    final body = lines.sublist(closeIdx + 1).join('\n').trimLeft();
    return (frontmatter: frontmatter, body: body);
  }

  static String? _extractH1(String body) {
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.startsWith('# ') && !t.startsWith('## ')) {
        return t.substring(2).trim();
      }
    }
    return null;
  }

  static List<String> _extractSectionItems(String body, String sectionName) {
    final lines = body.split('\n');
    final result = <String>[];
    bool inSection = false;
    for (final line in lines) {
      final t = line.trim();
      if (t == '## $sectionName') {
        inSection = true;
        continue;
      }
      if (inSection) {
        if (t.startsWith('## ') || t.startsWith('# ')) break;
        if (t.startsWith('- ') || t.startsWith('* ')) {
          result.add(t.substring(2).trim());
        } else if (t.isNotEmpty) {
          result.add(t);
        }
      }
    }
    return result;
  }

  static List<String> _extractSectionWikilinks(String body, String sectionName) {
    final lines = body.split('\n');
    final result = <String>[];
    bool inSection = false;
    for (final line in lines) {
      final t = line.trim();
      if (t == '## $sectionName') {
        inSection = true;
        continue;
      }
      if (inSection) {
        if (t.startsWith('## ') || t.startsWith('# ')) break;
        for (final m in _wikilinkRegex.allMatches(t)) {
          result.add(m.group(1)!);
        }
      }
    }
    return result;
  }

  static List<String> _extractWikilinks(String text) =>
      _wikilinkRegex.allMatches(text).map((m) => m.group(1)!).toList();

  // ── Private: timestamp helpers ─────────────────────────────────────────────

  static int? _parseIsoToMs(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  static String _msToIso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  // ── Private: string helpers ────────────────────────────────────────────────

  static String _slugify(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  static String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _generateId(String name, Set<String> existing,
      {required String fallback}) {
    var base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    if (base.isEmpty) base = fallback;
    if (!existing.contains(base)) return base;
    var n = 2;
    while (existing.contains('$base-$n')) { n++; }
    return '$base-$n';
  }

  // ── Private: migration ─────────────────────────────────────────────────────

  Future<void> _migrateFromJson(String vaultPath) async {
    // Only migrate if entities dir has no .md files yet
    final entitiesDir = Directory(VaultService.entitiesPath(vaultPath));
    if (await entitiesDir.exists()) {
      final all = await entitiesDir.list().toList();
      final hasMd = all.any((f) => f is File && f.path.endsWith('.md'));
      if (hasMd) return;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final jsonFile = File(p.join(appDir.path, 'entities.json'));
      if (!await jsonFile.exists()) return;

      final content = await jsonFile.readAsString();
      if (content.trim().isEmpty) return;

      final json = jsonDecode(content) as Map<String, dynamic>;

      final migEntities = (json['entities'] as List? ?? [])
          .map((e) => Entity.fromJson(e as Map<String, dynamic>))
          .toList();
      final migCategories = (json['categories'] as List? ?? [])
          .map((c) => Category.fromJson(c as Map<String, dynamic>))
          .toList();
      final migLinks = (json['entity_links'] as List? ?? [])
          .map((l) => EntityLink.fromJson(l as Map<String, dynamic>))
          .toList();
      final migBoards = (json['boards'] as List? ?? [])
          .map((b) => Board.fromJson(b as Map<String, dynamic>))
          .toList();
      final migBoardEntities = (json['board_entities'] as List? ?? [])
          .map((be) => BoardEntity.fromJson(be as Map<String, dynamic>))
          .toList();
      final migTags = (json['tags'] as List? ?? []).cast<String>();

      await saveData(
        entities: migEntities,
        categories: migCategories,
        tags: migTags,
        entityLinks: migLinks,
        boards: migBoards,
        boardEntities: migBoardEntities,
      );

      await jsonFile.rename(p.join(appDir.path, 'entities.json.migrated'));
    } catch (_) {}
  }

  // ── Private: defaults ──────────────────────────────────────────────────────

  AppData _defaultData() => (
        entities: <Entity>[],
        categories: [Category(id: 'people', name: 'People')],
        tags: <String>[],
        entityLinks: <EntityLink>[],
        boards: <Board>[],
        boardEntities: <BoardEntity>[],
      );
}
