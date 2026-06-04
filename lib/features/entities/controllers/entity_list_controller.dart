import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/markdown_storage_service.dart';

/// Plain-class controller owning entity/category data, filter state, and all
/// persistence operations. [onDataChanged] is called after every mutation and
/// after reloadData(); the parent should call setState + refresh child screens.
class EntityListController {
  final void Function() onDataChanged;

  final MarkdownStorageService storage = MarkdownStorageService();

  List<Entity> entities = [];
  List<Category> categories = [];
  List<String> tags = [];
  List<EntityLink> entityLinks = [];

  String? selectedCategoryId;
  String searchQuery = '';
  String sortOrder = 'latest';

  EntityListController({required this.onDataChanged});

  // ── Data access ────────────────────────────────────────────────────────────

  String get effectiveCategoryId => selectedCategoryId ?? 'default';

  List<Entity> get filtered {
    var list = entities;
    if (selectedCategoryId != null) {
      list = list.where((e) => e.categoryId == selectedCategoryId).toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    return MarkdownStorageService.sortEntities(list, sortOrder);
  }

  // ── Load / reload ──────────────────────────────────────────────────────────

  /// Initial load; caller is responsible for triggering setState after this.
  Future<void> loadData() async {
    final data = await storage.loadData();
    entities = data.entities;
    categories = data.categories;
    tags = data.tags;
    entityLinks = data.entityLinks;
  }

  /// Reload after external mutations; calls [onDataChanged] on completion.
  Future<void> reloadData() async {
    final data = await storage.loadData();
    entities = data.entities;
    categories = data.categories;
    tags = data.tags;
    entityLinks = data.entityLinks;
    onDataChanged();
  }

  void save() {
    storage.saveData(
      entities: entities,
      categories: categories,
      tags: tags,
      entityLinks: entityLinks,
    );
  }

  // ── Entity CRUD ────────────────────────────────────────────────────────────

  void addEntity(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = MarkdownStorageService.generateEntityId(trimmed, entities);
    entities.add(Entity(
      id: id,
      name: trimmed,
      categoryId: effectiveCategoryId,
      createdAt: now,
      updatedAt: now,
    ));
    save();
    onDataChanged();
  }

  void deleteEntity(Entity entity) {
    entities.removeWhere((e) => e.id == entity.id);
    entityLinks.removeWhere((l) => l.from == entity.id || l.to == entity.id);
    save();
    onDataChanged();
  }

  // ── Category CRUD ──────────────────────────────────────────────────────────

  void addCategory(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = MarkdownStorageService.generateCategoryId(trimmed, categories);
    categories.add(Category(id: id, name: trimmed));
    save();
    onDataChanged();
  }

  void renameCategory(Category category, String newName) {
    category.name = newName;
    save();
    onDataChanged();
  }

  /// Returns an error string if the category cannot be deleted (has entities),
  /// or null on success.
  String? deleteCategory(Category category) {
    final inUse = entities.any((e) => e.categoryId == category.id);
    if (inUse) {
      return 'Cannot delete "${category.name}" — it has entities. Reassign them first.';
    }
    categories.removeWhere((c) => c.id == category.id);
    if (selectedCategoryId == category.id) selectedCategoryId = null;
    save();
    onDataChanged();
    return null;
  }
}
