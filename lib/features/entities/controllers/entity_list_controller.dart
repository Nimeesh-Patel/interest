import '../models/collection.dart';
import '../models/entity.dart';
import '../services/markdown_storage_service.dart';

/// Plain-class controller owning entity/collection data, filter state, and all
/// persistence operations. [onDataChanged] is called after every mutation and
/// after reloadData(); the parent should call setState + refresh child screens.
///
/// Persistence is per-file: each mutation touches exactly one entity file (or,
/// for a collection rename, only its members). There is no bulk save.
class EntityListController {
  final void Function() onDataChanged;

  final MarkdownStorageService storage = MarkdownStorageService();

  List<Entity> entities = [];
  List<Collection> collections = [];
  List<String> tags = [];

  String? selectedCollectionId;
  String searchQuery = '';
  String sortOrder = 'latest';

  EntityListController({required this.onDataChanged});

  // ── Data access ────────────────────────────────────────────────────────────

  /// Raw collection name new entities land in (selected collection, else first,
  /// else empty — no collection is invented).
  String get effectiveCollectionName {
    if (selectedCollectionId != null) {
      final match = collections.where((c) => c.id == selectedCollectionId);
      if (match.isNotEmpty) return match.first.name;
    }
    return collections.isNotEmpty ? collections.first.name : '';
  }

  List<Entity> get filtered {
    var list = entities;
    if (selectedCollectionId != null) {
      list = list.where((e) => e.collectionId == selectedCollectionId).toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    return MarkdownStorageService.sortEntities(list, sortOrder);
  }

  // ── Load / reload ──────────────────────────────────────────────────────────

  void _apply(AppData data) {
    entities = data.entities;
    collections = data.collections;
    tags = data.tags;
  }

  /// Initial load; caller is responsible for triggering setState after this.
  Future<void> loadData() async => _apply(await storage.loadData());

  /// Reload after external mutations; calls [onDataChanged] on completion.
  Future<void> reloadData() async {
    _apply(await storage.loadData());
    onDataChanged();
  }

  // ── Entity CRUD ────────────────────────────────────────────────────────────

  /// Adds a note to [collectionName] (defaults to the active collection). A
  /// collection name is required — an entity is defined by its `collection:`.
  Future<void> addEntity(String name, {String? collectionName}) async {
    final trimmed = name.trim();
    final collection = (collectionName ?? effectiveCollectionName).trim();
    if (trimmed.isEmpty || collection.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final entity = Entity(
      id: MarkdownStorageService.generateEntityId(trimmed, entities),
      name: trimmed,
      collection: collection,
      createdAt: now,
      updatedAt: now,
    );
    entities.add(entity);
    await storage.saveEntity(entity);
    onDataChanged();
  }

  Future<void> deleteEntity(Entity entity) async {
    await storage.deleteEntity(entity);
    entities.removeWhere((e) => e.id == entity.id);
    onDataChanged();
  }

  // ── Collection CRUD ──────────────────────────────────────────────────────────

  /// Adds an in-memory collection so new entities can be filed under it.
  /// Collections are derived from `collection:` values, so an empty one is
  /// session-only until an entity adopts it.
  void addCollection(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = MarkdownStorageService.generateCollectionId(trimmed, collections);
    collections.add(Collection(id: id, name: trimmed));
    onDataChanged();
  }

  /// Renames a collection by patching every member file, then reloads so the
  /// derived collection list reflects the new value.
  Future<void> renameCollection(Collection collection, String newName) async {
    final members =
        entities.where((e) => e.collectionId == collection.id).toList();
    await storage.renameCollection(members, newName);
    await reloadData();
  }

  /// Returns an error string if the collection cannot be deleted (has entities),
  /// or null on success.
  String? deleteCollection(Collection collection) {
    final inUse = entities.any((e) => e.collectionId == collection.id);
    if (inUse) {
      return 'Cannot delete "${collection.name}" — it has notes. Reassign them first.';
    }
    collections.removeWhere((c) => c.id == collection.id);
    if (selectedCollectionId == collection.id) selectedCollectionId = null;
    onDataChanged();
    return null;
  }
}
