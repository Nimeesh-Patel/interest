import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/storage_service.dart';
import 'entity_screen.dart';

class BoardDetailScreen extends StatefulWidget {
  final StorageService storage;
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

  void _removeFromBoard(String entityId) {
    setState(() {
      _boardEntities.removeWhere(
          (be) => be.boardId == widget.boardId && be.entityId == entityId);
    });
    _save();
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

    final members = _boardMembers;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.boardName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: members.isEmpty
          ? const Center(
              child: Text(
                'No entities in this board yet.\nAdd entities from their detail screen.',
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
    );
  }
}
