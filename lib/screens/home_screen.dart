import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/integrations_config_service.dart';
import '../core/vault_service.dart';
import '../features/entities/models/category.dart';
import '../features/entities/models/entity.dart';
import '../features/entities/models/entity_link.dart';
import '../features/entities/services/markdown_storage_service.dart';
import '../shared/constants/app_spacing.dart';
import '../shared/constants/app_theme.dart';
import '../shared/widgets/bottom_sheet_menu.dart';
import '../shared/widgets/input_dialog.dart';
import '../features/entities/screens/entity_screen.dart';
import '../features/projects/screens/projects_screen.dart';
import '../features/resurface/screens/resurface_screen.dart';
import '../features/bookmarks/x_bookmark_service.dart';
import '../features/bookmarks/x_bookmark_storage_service.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/templates/screens/templates_screen.dart';
import 'sources_screen.dart';
import '../features/home/screens/home_dashboard_screen.dart';
import '../shared/widgets/quick_add_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _shareChannel = MethodChannel('people.nimee/share');

  final MarkdownStorageService _storage = MarkdownStorageService();
  final _projectsKey = GlobalKey<ProjectsScreenState>();
  final _resurfaceKey = GlobalKey<ResurfaceScreenState>();
  final _homeDashboardKey = GlobalKey<HomeDashboardScreenState>();
  List<Entity> _entities = [];
  List<Category> _categories = [];
  List<String> _tags = [];
  List<EntityLink> _entityLinks = [];
  String? _selectedCategoryId;
  String _searchQuery = '';
  String _sortOrder = 'latest';
  bool _isLoading = true;
  bool _isAddingCategory = false;
  // Tabs: 0=Home, 1=Notes, 2=Entities, 3=Projects
  int _currentTab = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
    _shareChannel.setMethodCallHandler(_onShareMethod);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final url =
          await _shareChannel.invokeMethod<String?>('getInitialShareUrl');
      if (url != null && mounted) _ingestShareUrl(url);
    });
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

  Future<void> _onShareMethod(MethodCall call) async {
    if (call.method == 'onShareIntent') {
      final url = call.arguments as String?;
      if (url != null && mounted) _ingestShareUrl(url);
    }
  }

  Future<void> _ingestShareUrl(String url) async {
    final vault = await VaultService.getVaultPath();
    if (vault == null || !mounted) return;

    final (error, meta) = await XBookmarkService.fetchMetadata(url);
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    if (!mounted) return;

    final name = await showInputDialog(
      context,
      title: 'Save bookmark',
      hintText: 'Note name (optional)',
      confirmLabel: 'Save',
      cancelLabel: 'Skip',
      capitalization: TextCapitalization.none,
    );
    if (!mounted) return;

    final String baseSlug;
    if (name != null && name.isNotEmpty) {
      baseSlug = name;
    } else if (meta?.tweetText != null && meta!.tweetText!.isNotEmpty) {
      final words =
          meta.tweetText!.trim().split(RegExp(r'\s+')).take(7).join(' ');
      baseSlug = words;
    } else {
      baseSlug = 'x-${meta?.tweetId ?? 'bookmark'}';
    }

    final dirPath = VaultService.bookmarksPath(vault);
    final slug = XBookmarkStorageService.uniqueSlug(
        baseSlug.isNotEmpty ? baseSlug : 'x-${meta?.tweetId ?? 'bookmark'}',
        dirPath);

    if (meta == null) return;
    final saveError = await XBookmarkStorageService.save(vault, slug, meta);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(saveError ?? 'Saved to Bookmarks')));
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
                ),
                textInputAction: TextInputAction.done,
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
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, size: 16, color: AppColors.textTertiary),
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
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: _addEntity,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppColors.textSecondary,
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
          prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
        ),
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  static const _sortLabels = {
    'latest': 'Latest',
    'oldest': 'Oldest',
    'high_score': 'Highest Score',
    'low_score': 'Lowest Score',
    'alpha': 'A–Z',
    'alpha_rev': 'Z–A',
  };

  Widget _buildSortBar() {
    final count = _filtered.length;
    final sortLabel = _sortLabels[_sortOrder] ?? 'Latest';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 8),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? "entity" : "entities"}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSortSheet,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sortLabel,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(width: 2),
                const Icon(Icons.unfold_more, size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showBottomSheetMenu(context, items: [
      for (final entry in _sortLabels.entries)
        BottomSheetMenuItem(
          icon: _sortOrder == entry.key ? Icons.check : Icons.sort,
          label: entry.value,
          onTap: () => setState(() => _sortOrder = entry.key),
        ),
    ]);
  }

  Widget _buildEntityList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'Nothing here yet.' : 'No results.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: kFabListBottomPad),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final entity = items[i];
        final catName = _categories
            .firstWhere((c) => c.id == entity.categoryId,
                orElse: () => Category(id: '', name: ''))
            .name;
        return GestureDetector(
          onLongPress: () => _showEntityOptions(entity),
          child: InkWell(
            onTap: () => _openEntity(entity),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: kScreenHPad, vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entity.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (entity.score != null)
                              Text(
                                '★${entity.score!.toStringAsFixed(entity.score! % 1 == 0 ? 0 : 1)}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.score),
                              ),
                            if (catName.isNotEmpty)
                              Text(catName,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary)),
                            for (final tag in entity.tags.take(2))
                              Text('#$tag',
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.accent)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTimestamp(entity.updatedAt),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEntityOptions(Entity entity) {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        isDestructive: true,
        onTap: () => _deleteEntity(entity),
      ),
    ]);
  }

  static String _formatTimestamp(int msEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msEpoch);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
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

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final notesState = _resurfaceKey.currentState;
    final notesCanGoBack = _currentTab == 1 && (notesState?.canGoBack ?? false);
    final notesEditPath = _currentTab == 1 ? notesState?.currentEditFilePath : null;
    final notesIsSearchable = _currentTab == 1 && (notesState?.isSearchable ?? false);
    final notesSearchActive = notesState?.isSearchActive ?? false;

    final tabTitle = switch (_currentTab) {
      0 => 'Interest',
      1 => notesState?.navTitle ?? 'Notes',
      2 => 'Entities',
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
        actions: [
          if (_currentTab == 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  _todayLabel(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          if (notesIsSearchable)
            IconButton(
              icon: Icon(notesSearchActive ? Icons.close : Icons.search),
              tooltip: notesSearchActive ? 'Close search' : 'Search notes',
              onPressed: () {
                notesState!.toggleSearch();
                setState(() {});
              },
            ),
          if (notesEditPath != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit note',
              onPressed: () async {
                await notesState!.openEditForCurrentNote(context);
                setState(() {});
              },
            ),
          IconButton(
            icon: const Icon(Icons.sensors),
            tooltip: 'Sources',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SourcesScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settings') { _openSettings(); }
              else if (v == 'templates') { _openTemplates(); }
              else if (v == 'obsidian') { _openObsidian(); }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'templates', child: Text('Templates')),
              PopupMenuItem(value: 'obsidian', child: Text('Open Obsidian')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          HomeDashboardScreen(
            key: _homeDashboardKey,
            entities: _entities,
            categories: _categories,
            onBeginReview: () => setState(() => _currentTab = 1),
            onEntityTap: _openEntity,
            onAddTap: () => showQuickAddSheet(
              context,
              entities: _entities,
              categories: _categories,
              tags: _tags,
              allEntityLinks: _entityLinks,
              storage: _storage,
              onCreated: (entity) async {
                await _reloadData();
                if (mounted) await _openEntity(entity);
              },
            ),
          ),
          ResurfaceScreen(
            key: _resurfaceKey,
            onNavigationChanged: () => setState(() {}),
          ),
          _buildEntitiesTab(),
          ProjectsScreen(key: _projectsKey),
        ],
      ),
      floatingActionButton: switch (_currentTab) {
        2 => _EntitiesFab(onTap: () => showQuickAddSheet(
              context,
              entities: _entities,
              categories: _categories,
              tags: _tags,
              allEntityLinks: _entityLinks,
              storage: _storage,
              onCreated: (entity) async {
                await _reloadData();
                if (mounted) {
                  await _openEntity(entity);
                }
              },
            )),
        3 => FloatingActionButton(
            onPressed: () => _projectsKey.currentState?.showCreateDialog(context),
            tooltip: 'New project',
            child: const Icon(Icons.add),
          ),
        _ => null,
      },
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (i) {
            if (i == 1 && _currentTab == 1) {
              _resurfaceKey.currentState?.resetStack();
            }
            setState(() => _currentTab = i);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'HOME',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories_outlined),
              activeIcon: Icon(Icons.auto_stories),
              label: 'NOTES',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.hub_outlined),
              activeIcon: Icon(Icons.hub),
              label: 'ENTITIES',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.checklist_outlined),
              activeIcon: Icon(Icons.checklist),
              label: 'PROJECTS',
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _EntitiesFab extends StatelessWidget {
  final VoidCallback onTap;
  const _EntitiesFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.accentDim,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.33)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.add, color: AppColors.accent, size: 24),
      ),
    );
  }
}

