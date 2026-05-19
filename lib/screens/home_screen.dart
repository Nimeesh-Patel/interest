import 'package:flutter/material.dart';
import '../features/boards/models/board.dart';
import '../features/boards/models/board_entity.dart';
import '../features/entities/models/category.dart';
import '../features/entities/models/entity.dart';
import '../features/entities/models/entity_link.dart';
import '../features/tasks/models/task.dart';
import '../features/entities/services/markdown_storage_service.dart';
import '../features/tasks/services/task_storage_service.dart';
import '../shared/widgets/bottom_sheet_menu.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/input_dialog.dart';
import '../features/boards/screens/board_detail_screen.dart';
import '../features/entities/screens/entity_screen.dart';
import '../features/anki/screens/anki_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/tasks/screens/task_file_screen.dart';
import '../features/templates/screens/templates_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MarkdownStorageService _storage = MarkdownStorageService();
  List<Entity> _entities = [];
  List<Category> _categories = [];
  List<String> _tags = [];
  List<EntityLink> _entityLinks = [];
  List<Board> _boards = [];
  List<BoardEntity> _boardEntities = [];
  List<TaskFile> _taskFiles = [];
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
        _boards = data.boards;
        _boardEntities = data.boardEntities;
        _isLoading = false;
      });
    }
    final taskFiles = await TaskStorageService.loadTaskFiles();
    if (mounted) setState(() => _taskFiles = taskFiles);
  }

  Future<void> _reloadData() async {
    final data = await _storage.loadData();
    if (mounted) {
      setState(() {
        _entities = data.entities;
        _categories = data.categories;
        _tags = data.tags;
        _entityLinks = data.entityLinks;
        _boards = data.boards;
        _boardEntities = data.boardEntities;
      });
    }
  }

  Future<void> _reloadTaskFiles() async {
    final taskFiles = await TaskStorageService.loadTaskFiles();
    if (mounted) setState(() => _taskFiles = taskFiles);
  }

  void _save() {
    _storage.saveData(
      entities: _entities,
      categories: _categories,
      tags: _tags,
      entityLinks: _entityLinks,
      boards: _boards,
      boardEntities: _boardEntities,
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
      _boardEntities.removeWhere((be) => be.entityId == entity.id);
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
          allBoards: _boards,
          allBoardEntities: _boardEntities,
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

  // ── Board operations ──────────────────────────────────────────────────────

  int _entityCountForBoard(String boardId) =>
      _boardEntities.where((be) => be.boardId == boardId).length;

  void _showCreateBoard() async {
    final name = await showInputDialog(context,
      title: 'New board',
      hintText: 'Board name',
      confirmLabel: 'Create',
      capitalization: TextCapitalization.words,
    );
    if (name != null) _createBoard(name);
  }

  void _createBoard(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = MarkdownStorageService.generateBoardId(trimmed, _boards);
    setState(() => _boards.add(Board(id: id, name: trimmed)));
    _save();
  }

  void _showBoardOptions(Board board) {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.edit,
        label: 'Rename',
        onTap: () => _showRenameBoard(board),
      ),
      BottomSheetMenuItem(
        icon: Icons.delete,
        label: 'Delete',
        isDestructive: true,
        onTap: () => _deleteBoard(board),
      ),
    ]);
  }

  void _showRenameBoard(Board board) async {
    final name = await showInputDialog(context,
      title: 'Rename board',
      initialValue: board.name,
      confirmLabel: 'Rename',
    );
    if (name != null) {
      setState(() => board.name = name);
      _save();
    }
  }

  void _deleteBoard(Board board) {
    setState(() {
      _boards.removeWhere((b) => b.id == board.id);
      _boardEntities.removeWhere((be) => be.boardId == board.id);
    });
    _save();
  }

  Future<void> _openBoardDetail(Board board) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoardDetailScreen(
          storage: _storage,
          boardId: board.id,
          boardName: board.name,
        ),
      ),
    );
    await _reloadData();
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

  // ── ToDos tab operations ──────────────────────────────────────────────────

  void _showCreateTaskFile() async {
    final name = await showInputDialog(context,
      title: 'New task file',
      hintText: 'Name',
      confirmLabel: 'Create',
      capitalization: TextCapitalization.words,
    );
    if (name != null) _createTaskFile(name);
  }

  Future<void> _createTaskFile(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await TaskStorageService.createTaskFile(trimmed);
    await _reloadTaskFiles();
  }

  void _showDeleteTaskFileConfirm(TaskFile tf) async {
    final confirmed = await showConfirmDialog(context,
      title: 'Delete task file?',
      message: 'Delete "${tf.name}"? This cannot be undone.',
    );
    if (confirmed) {
      await TaskStorageService.deleteTaskFile(tf.filePath);
      await _reloadTaskFiles();
    }
  }

  void _showTaskFileOptions(TaskFile tf) {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
        onTap: () => _showRenameTaskFile(tf),
      ),
      BottomSheetMenuItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        isDestructive: true,
        onTap: () => _showDeleteTaskFileConfirm(tf),
      ),
    ]);
  }

  void _showRenameTaskFile(TaskFile tf) async {
    final name = await showInputDialog(context,
      title: 'Rename task file',
      initialValue: tf.name,
      hintText: 'Name',
      confirmLabel: 'Rename',
      capitalization: TextCapitalization.words,
    );
    if (name != null) _renameTaskFile(tf, name);
  }

  Future<void> _renameTaskFile(TaskFile tf, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == tf.name) return;
    final result = await TaskStorageService.renameTaskFile(tf.filePath, trimmed);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rename failed — name already in use.')),
      );
      return;
    }
    await _reloadTaskFiles();
  }

  // ── ToDos tab UI ──────────────────────────────────────────────────────────

  Widget _buildTodosTab() {
    if (_taskFiles.isEmpty) {
      return const EmptyState(
        icon: Icons.check_box_outline_blank,
        message: 'No task files yet.\nTap + to create one.',
      );
    }
    return ListView.builder(
      itemCount: _taskFiles.length,
      itemBuilder: (ctx, i) {
        final tf = _taskFiles[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: Icon(Icons.check_box_outline_blank,
                color: Colors.grey.shade400),
            title: Text(tf.name),
            subtitle: tf.totalTasks == 0
                ? const Text('No tasks', style: TextStyle(fontSize: 12))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: tf.progress,
                        minHeight: 5,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${tf.completedTasks} / ${tf.totalTasks} done',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskFileScreen(
                    filePath: tf.filePath,
                    title: tf.name,
                    onRenamed: (newPath, newTitle) => _reloadTaskFiles(),
                  ),
                ),
              );
              await _reloadTaskFiles();
            },
            onLongPress: () => _showTaskFileOptions(tf),
          ),
        );
      },
    );
  }

  // ── Boards tab UI ─────────────────────────────────────────────────────────

  Widget _buildBoardsTab() {
    if (_boards.isEmpty) {
      return const Center(
        child: Text(
          'No boards yet.\nTap + to create one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      itemCount: _boards.length,
      itemBuilder: (ctx, i) {
        final board = _boards[i];
        final count = _entityCountForBoard(board.id);
        return ListTile(
          title: Text(board.name),
          subtitle: Text(
            '$count ${count == 1 ? 'entity' : 'entities'}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showBoardOptions(board),
          ),
          onTap: () => _openBoardDetail(board),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTab == 0 ? 'Entities' : _currentTab == 1 ? 'Boards' : 'ToDos'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_currentTab == 1)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showCreateBoard,
              tooltip: 'New board',
            ),
          if (_currentTab == 2)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showCreateTaskFile,
              tooltip: 'New task file',
            ),
          IconButton(
            icon: const Icon(Icons.style_outlined),
            onPressed: _openAnki,
            tooltip: 'Anki cards',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            onPressed: _openTemplates,
            tooltip: 'Templates',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildEntitiesTab(),
          _buildBoardsTab(),
          _buildTodosTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Entities',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            label: 'Boards',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_box_outline_blank),
            label: 'ToDos',
          ),
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
