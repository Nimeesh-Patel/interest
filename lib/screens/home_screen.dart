import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/integrations_config_service.dart';
import '../core/vault_service.dart';
import '../features/books/screens/hardcover_screen.dart';
import '../features/entities/models/category.dart';
import '../features/entities/models/entity.dart';
import '../features/entities/models/entity_link.dart';
import '../features/entities/services/markdown_storage_service.dart';
import '../shared/widgets/bottom_sheet_menu.dart';
import '../shared/widgets/input_dialog.dart';
import '../features/entities/screens/entity_screen.dart';
import '../features/anki/screens/anki_screen.dart';
import '../features/projects/screens/projects_screen.dart';
import '../features/resurface/screens/resurface_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/templates/screens/templates_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MarkdownStorageService _storage = MarkdownStorageService();
  final _hardcoverKey = GlobalKey<HardcoverScreenState>();
  final _projectsKey = GlobalKey<ProjectsScreenState>();
  final _resurfaceKey = GlobalKey<ResurfaceScreenState>();
  List<Entity> _entities = [];
  List<Category> _categories = [];
  List<String> _tags = [];
  List<EntityLink> _entityLinks = [];
  String? _selectedCategoryId;
  String _searchQuery = '';
  String _sortOrder = 'latest';
  bool _isLoading = true;
  bool _isAddingCategory = false;
  int _currentTab = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addController.dispose();
    _newCategoryController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final data = await _storage.loadData();
    if (mounted) {
      setState(() {
        _entities = data.entities;
        _categories = data.categories;
        _tags = data.tags;
        _entityLinks = data.entityLinks;
        _isLoading = false;
      });
    }
    final vault = await VaultService.getVaultPath();
    if (vault != null) {
      await IntegrationsConfigService.migrateFromPrefs(vault);
    }
  }

  Future<void> _reloadData() async {
    final data = await _storage.loadData();
    if (mounted) {
      setState(() {
        _entities = data.entities;
        _categories = data.categories;
        _tags = data.tags;
        _entityLinks = data.entityLinks;
      });
    }
  }

  void _save() {
    _storage.saveData(
      entities: _entities,
      categories: _categories,
      tags: _tags,
      entityLinks: _entityLinks,
    );
  }

  // ── Entity operations ─────────────────────────────────────────────────────

  List<Entity> get _filtered {
    var list = _entities;
    if (_selectedCategoryId != null) {
      list = list.where((e) => e.categoryId == _selectedCategoryId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    return MarkdownStorageService.sortEntities(list, _sortOrder);
  }

  String get _effectiveCategoryId {
    if (_selectedCategoryId != null) return _selectedCategoryId!;
    return 'default';
  }

  void _addEntity(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = MarkdownStorageService.generateEntityId(trimmed, _entities);
    final entity = Entity(
      id: id,
      name: trimmed,
      categoryId: _effectiveCategoryId,
      createdAt: now,
      updatedAt: now,
    );
    setState(() => _entities.add(entity));
    _save();
    _addController.clear();
  }

  void _deleteEntity(Entity entity) {
    setState(() {
      _entities.removeWhere((e) => e.id == entity.id);
      _entityLinks.removeWhere((l) => l.from == entity.id || l.to == entity.id);
    });
    _save();
  }

  Future<void> _openEntity(Entity entity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntityScreen(
          entity: entity,
          storage: _storage,
          allEntities: _entities,
          allCategories: _categories,
          allTags: _tags,
          allEntityLinks: _entityLinks,
        ),
      ),
    );
    await _reloadData();
  }

  Future<void> _openTemplates() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesScreen()),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _reloadData();
  }

  Future<void> _openAnki() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnkiScreen()),
    );
  }

  Future<void> _openObsidian() async {
    final launched = await launchUrl(
      Uri.parse('obsidian://'),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obsidian is not installed')),
      );
    }
  }

  // ── Category operations ───────────────────────────────────────────────────

  void _addCategory(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      setState(() => _isAddingCategory = false);
      _newCategoryController.clear();
      return;
    }
    final id = MarkdownStorageService.generateCategoryId(trimmed, _categories);
    setState(() {
      _categories.add(Category(id: id, name: trimmed));
      _isAddingCategory = false;
    });
    _newCategoryController.clear();
    _save();
  }

  void _showCategoryOptions(Category category) {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.edit,
        label: 'Rename',
        onTap: () => _showRenameCategory(category),
      ),
      BottomSheetMenuItem(
        icon: Icons.delete,
        label: 'Delete',
        isDestructive: true,
        onTap: () => _deleteCategory(category),
      ),
    ]);
  }

  void _showRenameCategory(Category category) async {
    final name = await showInputDialog(context,
      title: 'Rename category',
      initialValue: category.name,
      confirmLabel: 'Rename',
    );
    if (name != null) {
      setState(() => category.name = name);
      _save();
    }
  }

  void _deleteCategory(Category category) {
    final inUse = _entities.any((e) => e.categoryId == category.id);
    if (inUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot delete "${category.name}" — it has entities. Reassign them first.'),
        ),
      );
      return;
    }
    setState(() {
      _categories.removeWhere((c) => c.id == category.id);
      if (_selectedCategoryId == category.id) _selectedCategoryId = null;
    });
    _save();
  }

  // ── Entities tab UI ───────────────────────────────────────────────────────

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          _CategoryChip(
            label: 'All',
            selected: _selectedCategoryId == null,
            onTap: () => setState(() => _selectedCategoryId = null),
          ),
          for (final cat in _categories)
            _CategoryChip(
              label: cat.name,
              selected: _selectedCategoryId == cat.id,
              onTap: () => setState(() => _selectedCategoryId = cat.id),
              onLongPress: () => _showCategoryOptions(cat),
            ),
          if (_isAddingCategory)
            Container(
              width: 140,
              margin: const EdgeInsets.only(left: 4),
              child: TextField(
                controller: _newCategoryController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Category name',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _addCategory,
                onEditingComplete: () {},
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _isAddingCategory = true),
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddBar() {
    final catName = _selectedCategoryId != null
        ? _categories
            .firstWhere(
              (c) => c.id == _selectedCategoryId,
              orElse: () => Category(id: '', name: 'entity'),
            )
            .name
        : 'Default';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addController,
              focusNode: _addFocus,
              decoration: InputDecoration(
                hintText: 'Add to $catName…',
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: _addEntity,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _addEntity(_addController.text),
            tooltip: 'Add entity',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          const Text('Sort:', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _sortOrder,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: const [
              DropdownMenuItem(value: 'latest', child: Text('Latest')),
              DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
              DropdownMenuItem(value: 'high_score', child: Text('Highest score')),
              DropdownMenuItem(value: 'low_score', child: Text('Lowest score')),
              DropdownMenuItem(value: 'alpha', child: Text('A–Z')),
              DropdownMenuItem(value: 'alpha_rev', child: Text('Z–A')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _sortOrder = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEntityList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'Nothing here yet.' : 'No results.',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final entity = items[i];
        final catName = _categories
            .firstWhere((c) => c.id == entity.categoryId,
                orElse: () => Category(id: '', name: ''))
            .name;
        return ListTile(
          title: Text(entity.name),
          subtitle: _EntitySubtitle(
            categoryName: catName,
            tags: entity.tags,
            score: entity.score,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: () => _deleteEntity(entity),
          ),
          onTap: () => _openEntity(entity),
        );
      },
    );
  }

  Widget _buildEntitiesTab() {
    return GestureDetector(
      onTap: () {
        if (_isAddingCategory) {
          setState(() {
            _isAddingCategory = false;
            _newCategoryController.clear();
          });
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryFilter(),
          _buildAddBar(),
          _buildSearchBar(),
          _buildSortBar(),
          Expanded(child: _buildEntityList()),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final notesState = _resurfaceKey.currentState;
    final notesCanGoBack = _currentTab == 1 && (notesState?.canGoBack ?? false);
    final tabTitle = _currentTab == 1
        ? (notesState?.navTitle ?? 'Notes')
        : switch (_currentTab) {
            0 => 'Entities',
            2 => 'Hardcover',
            _ => 'Projects',
          };

    return Scaffold(
      appBar: AppBar(
        leading: notesCanGoBack
            ? BackButton(onPressed: () {
                notesState!.goBack();
                setState(() {});
              })
            : null,
        title: Text(tabTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_currentTab == 2)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync with Hardcover',
              onPressed: () => _hardcoverKey.currentState?.sync(),
            ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _openObsidian,
            tooltip: 'Open Obsidian to sync',
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'anki') { _openAnki(); }
              else if (v == 'settings') { _openSettings(); }
              else if (v == 'templates') { _openTemplates(); }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'anki', child: Text('Anki')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'templates', child: Text('Templates')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildEntitiesTab(),
          ResurfaceScreen(
            key: _resurfaceKey,
            onNavigationChanged: () => setState(() {}),
          ),
          HardcoverScreen(key: _hardcoverKey),
          ProjectsScreen(key: _projectsKey),
        ],
      ),
      floatingActionButton: switch (_currentTab) {
        2 => FloatingActionButton(
            onPressed: () => _hardcoverKey.currentState?.openSearchSheet(),
            tooltip: 'Search Hardcover',
            child: const Icon(Icons.search),
          ),
        3 => FloatingActionButton(
            onPressed: () => _projectsKey.currentState?.showCreateDialog(context),
            tooltip: 'New project',
            child: const Icon(Icons.add),
          ),
        _ => null,
      },
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentTab,
        onTap: (i) {
          if (i == 1 && _currentTab == 1) {
            _resurfaceKey.currentState?.resetStack();
          }
          setState(() => _currentTab = i);
        },
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey.shade600,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Entities'),
          BottomNavigationBarItem(icon: Icon(Icons.article_outlined), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_stories), label: 'Hardcover'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), label: 'Projects'),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _EntitySubtitle extends StatelessWidget {
  final String categoryName;
  final List<String> tags;
  final double? score;

  const _EntitySubtitle({
    required this.categoryName,
    required this.tags,
    this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (categoryName.isNotEmpty)
            Text(
              categoryName,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          if (score != null)
            Text(
              '★ ${score!.toStringAsFixed(1)}',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade700),
            ),
          for (final tag in tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tag,
                style: TextStyle(fontSize: 10, color: Colors.indigo.shade700),
              ),
            ),
        ],
      ),
    );
  }
}
