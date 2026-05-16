import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/markdown_storage_service.dart';
import 'entity_screen.dart';

class BoardDetailScreen extends StatefulWidget {
  final MarkdownStorageService storage;
  final String boardId;
  final String boardName;

  const BoardDetailScreen({
    super.key,
    required this.storage,
    required this.boardId,
    required this.boardName,
  });

  @override
  State<BoardDetailScreen> createState() => _BoardDetailScreenState();
}

class _BoardDetailScreenState extends State<BoardDetailScreen> {
  List<Entity> _entities = [];
  List<Category> _categories = [];
  List<String> _tags = [];
  List<EntityLink> _entityLinks = [];
  List<Board> _boards = [];
  List<BoardEntity> _boardEntities = [];
  bool _isLoading = true;
  String _sortOrder = 'latest';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await widget.storage.loadData();
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
  }

  Future<void> _reloadData() async {
    final data = await widget.storage.loadData();
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

  void _save() {
    widget.storage.saveData(
      entities: _entities,
      categories: _categories,
      tags: _tags,
      entityLinks: _entityLinks,
      boards: _boards,
      boardEntities: _boardEntities,
    );
  }

  List<Entity> get _boardMembers {
    final ids = _boardEntities
        .where((be) => be.boardId == widget.boardId)
        .map((be) => be.entityId)
        .toSet();
    return _entities.where((e) => ids.contains(e.id)).toList();
  }

  List<Entity> get _sortedMembers {
    if (_sortOrder == 'category') {
      final members = List<Entity>.from(_boardMembers)
        ..sort((a, b) => a.categoryId.compareTo(b.categoryId));
      return members;
    }
    return MarkdownStorageService.sortEntities(_boardMembers, _sortOrder);
  }

  void _removeFromBoard(String entityId) {
    setState(() {
      _boardEntities.removeWhere(
          (be) => be.boardId == widget.boardId && be.entityId == entityId);
    });
    _save();
  }

  void _addToBoard(String entityId) {
    if (MarkdownStorageService.boardEntryExists(widget.boardId, entityId, _boardEntities)) return;
    setState(() {
      _boardEntities.add(BoardEntity(boardId: widget.boardId, entityId: entityId));
    });
    _save();
  }

  void _showAddEntityToBoard() {
    final alreadyIn = _boardEntities
        .where((be) => be.boardId == widget.boardId)
        .map((be) => be.entityId)
        .toSet();
    final candidates = _entities
        .where((e) => !alreadyIn.contains(e.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = candidates.where((e) =>
                query.isEmpty ||
                e.name.toLowerCase().contains(query.toLowerCase())).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: 420,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 4, 8),
                      child: Row(
                        children: [
                          const Text('Add entity',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search entities…',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                candidates.isEmpty
                                    ? 'All entities are already in this board.'
                                    : 'No entities found.',
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final e = filtered[i];
                                final catName = _categories
                                    .firstWhere((c) => c.id == e.categoryId,
                                        orElse: () => Category(id: '', name: ''))
                                    .name;
                                return ListTile(
                                  title: Text(e.name),
                                  subtitle: catName.isNotEmpty
                                      ? Text(catName,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600))
                                      : null,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _addToBoard(e.id);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openEntity(Entity entity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntityScreen(
          entity: entity,
          storage: widget.storage,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = _sortedMembers;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.boardName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEntityToBoard,
        icon: const Icon(Icons.add),
        label: const Text('Add entity'),
      ),
      body: Column(
        children: [
          // Sort row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('Sort:',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sortOrder,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  items: const [
                    DropdownMenuItem(value: 'latest', child: Text('Latest')),
                    DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                    DropdownMenuItem(
                        value: 'high_score', child: Text('Highest score')),
                    DropdownMenuItem(
                        value: 'low_score', child: Text('Lowest score')),
                    DropdownMenuItem(value: 'alpha', child: Text('A–Z')),
                    DropdownMenuItem(value: 'alpha_rev', child: Text('Z–A')),
                    DropdownMenuItem(
                        value: 'category', child: Text('Category')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortOrder = v);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: members.isEmpty
                ? const Center(
                    child: Text(
                      'No entities in this board yet.\nTap "Add entity" to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (ctx, i) {
                      final entity = members[i];
                      final catName = _categories
                          .firstWhere((c) => c.id == entity.categoryId,
                              orElse: () => Category(id: '', name: ''))
                          .name;
                      return ListTile(
                        title: Text(entity.name),
                        subtitle: catName.isNotEmpty
                            ? Text(catName,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600))
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.grey),
                          tooltip: 'Remove from board',
                          onPressed: () => _removeFromBoard(entity.id),
                        ),
                        onTap: () => _openEntity(entity),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
