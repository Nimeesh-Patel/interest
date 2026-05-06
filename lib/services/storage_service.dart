import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';

typedef AppData = ({
  List<Entity> entities,
  List<Category> categories,
  List<String> tags,
  List<EntityLink> entityLinks,
  List<Board> boards,
  List<BoardEntity> boardEntities,
});

class StorageService {
  static const _fileName = 'entities.json';
  static const _legacyFileName = 'people.json';

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  Future<AppData> loadData() async {
    try {
      final file = await _getFile(_fileName);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) return _defaultData();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return _parseNew(json);
      }

      final legacy = await _getFile(_legacyFileName);
      if (await legacy.exists()) {
        final content = await legacy.readAsString();
        if (content.trim().isEmpty) return _defaultData();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final migrated = _migrate(json);
        await saveData(
          entities: migrated.entities,
          categories: migrated.categories,
          tags: migrated.tags,
          entityLinks: migrated.entityLinks,
          boards: migrated.boards,
          boardEntities: migrated.boardEntities,
        );
        return migrated;
      }
    } catch (_) {}
    return _defaultData();
  }

  AppData _parseNew(Map<String, dynamic> json) {
    final entities = (json['entities'] as List<dynamic>? ?? [])
        .map((e) => Entity.fromJson(e as Map<String, dynamic>))
        .toList();
    final categories = (json['categories'] as List<dynamic>? ?? [])
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
    final tags = (json['tags'] as List<dynamic>? ?? []).cast<String>();
    final entityLinks = (json['entity_links'] as List<dynamic>? ?? [])
        .map((l) => EntityLink.fromJson(l as Map<String, dynamic>))
        .toList();
    final boards = (json['boards'] as List<dynamic>? ?? [])
        .map((b) => Board.fromJson(b as Map<String, dynamic>))
        .toList();
    final boardEntities = (json['board_entities'] as List<dynamic>? ?? [])
        .map((be) => BoardEntity.fromJson(be as Map<String, dynamic>))
        .toList();
    return (
      entities: entities,
      categories: categories,
      tags: tags,
      entityLinks: entityLinks,
      boards: boards,
      boardEntities: boardEntities,
    );
  }

  AppData _migrate(Map<String, dynamic> json) {
    final people = json['people'] as List<dynamic>? ?? [];
    final defaultCategory = Category(id: 'people', name: 'People');
    final entities = people.map((p) {
      final map = p as Map<String, dynamic>;
      final status = map['status'] as String? ?? 'active';
      return Entity(
        id: map['id'] as String,
        name: map['name'] as String,
        categoryId: 'people',
        notes: (map['notes'] as List<dynamic>?)?.cast<String>() ?? [],
        links: (map['links'] as List<dynamic>?)?.cast<String>() ?? [],
        tags: [status],
        createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();

    final tags = entities.expand((e) => e.tags).toSet().toList();
    return (
      entities: entities,
      categories: [defaultCategory],
      tags: tags,
      entityLinks: [],
      boards: [],
      boardEntities: [],
    );
  }

  AppData _defaultData() {
    return (
      entities: <Entity>[],
      categories: [Category(id: 'people', name: 'People')],
      tags: <String>[],
      entityLinks: <EntityLink>[],
      boards: <Board>[],
      boardEntities: <BoardEntity>[],
    );
  }

  Future<void> saveData({
    required List<Entity> entities,
    required List<Category> categories,
    required List<String> tags,
    required List<EntityLink> entityLinks,
    required List<Board> boards,
    required List<BoardEntity> boardEntities,
  }) async {
    try {
      final snapshot = List<Entity>.from(entities);
      final snapshotCats = List<Category>.from(categories);
      final snapshotLinks = List<EntityLink>.from(entityLinks);
      final snapshotBoards = List<Board>.from(boards);
      final snapshotBoardEntities = List<BoardEntity>.from(boardEntities);
      final liveTags = snapshot.expand((e) => e.tags).toSet().toList()..sort();
      final file = await _getFile(_fileName);
      await file.writeAsString(jsonEncode({
        'entities': snapshot.map((e) => e.toJson()).toList(),
        'categories': snapshotCats.map((c) => c.toJson()).toList(),
        'tags': liveTags,
        'entity_links': snapshotLinks.map((l) => l.toJson()).toList(),
        'boards': snapshotBoards.map((b) => b.toJson()).toList(),
        'board_entities': snapshotBoardEntities.map((be) => be.toJson()).toList(),
      }));
    } catch (_) {}
  }

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

  static String generateEntityId(String name, List<Entity> existing) {
    return _generateId(
      name,
      existing.map((e) => e.id).toSet(),
      fallback: 'entity',
    );
  }

  static String generateCategoryId(String name, List<Category> existing) {
    return _generateId(
      name,
      existing.map((c) => c.id).toSet(),
      fallback: 'category',
    );
  }

  static String generateBoardId(String name, List<Board> existing) {
    return _generateId(
      name,
      existing.map((b) => b.id).toSet(),
      fallback: 'board',
    );
  }

  static String _generateId(String name, Set<String> existing, {required String fallback}) {
    var base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    if (base.isEmpty) base = fallback;
    if (!existing.contains(base)) return base;
    var n = 2;
    while (existing.contains('$base-$n')) {
      n++;
    }
    return '$base-$n';
  }
}
