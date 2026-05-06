import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/storage_service.dart';
import 'board_detail_screen.dart';

class BoardsScreen extends StatefulWidget {
  final StorageService storage;

  const BoardsScreen({super.key, required this.storage});

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen> {
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

  void _showCreateBoard() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New board'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Board name',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            Navigator.pop(ctx);
            _createBoard(v);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _createBoard(ctrl.text);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createBoard(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = StorageService.generateBoardId(trimmed, _boards);
    setState(() => _boards.add(Board(id: id, name: trimmed)));
    _save();
  }

  void _showBoardOptions(Board board) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameBoard(board);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteBoard(board);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameBoard(Board board) {
    final ctrl = TextEditingController(text: board.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename board'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            Navigator.pop(ctx);
            final trimmed = v.trim();
            if (trimmed.isEmpty) return;
            setState(() => board.name = trimmed);
            _save();
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final trimmed = ctrl.text.trim();
              if (trimmed.isEmpty) return;
              setState(() => board.name = trimmed);
              _save();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteBoard(Board board) {
    setState(() {
      _boards.removeWhere((b) => b.id == board.id);
      _boardEntities.removeWhere((be) => be.boardId == board.id);
    });
    _save();
  }

  int _entityCountForBoard(String boardId) =>
      _boardEntities.where((be) => be.boardId == boardId).length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boards'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateBoard,
            tooltip: 'New board',
          ),
        ],
      ),
      body: _boards.isEmpty
          ? const Center(
              child: Text('No boards yet. Tap ＋ to create one.',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
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
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onPressed: () => _showBoardOptions(board),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BoardDetailScreen(
                          storage: widget.storage,
                          boardId: board.id,
                          boardName: board.name,
                        ),
                      ),
                    );
                    await _reloadData();
                  },
                );
              },
            ),
    );
  }
}
