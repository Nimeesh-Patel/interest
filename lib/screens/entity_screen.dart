import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/storage_service.dart';

class EntityScreen extends StatefulWidget {
  final Entity entity;
  final StorageService storage;
  final List<Entity> allEntities;
  final List<Category> allCategories;
  final List<String> allTags;
  final List<EntityLink> allEntityLinks;
  final List<Board> allBoards;
  final List<BoardEntity> allBoardEntities;

  const EntityScreen({
    super.key,
    required this.entity,
    required this.storage,
    required this.allEntities,
    required this.allCategories,
    required this.allTags,
    required this.allEntityLinks,
    required this.allBoards,
    required this.allBoardEntities,
  });

  @override
  State<EntityScreen> createState() => _EntityScreenState();
}

class _EntityScreenState extends State<EntityScreen> {
  late Entity _entity;
  late List<String> _allTags;

  bool _isEditingName = false;
  bool _isAddingNote = false;
  bool _isAddingLink = false;
  bool _isAddingTag = false;
  int? _editingNoteIndex;
  int? _editingLinkIndex;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entity = widget.entity;
    _allTags = List<String>.from(widget.allTags);
    _nameController.text = _entity.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _linkController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _save() {
    _entity.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final idx = widget.allEntities.indexWhere((e) => e.id == _entity.id);
    if (idx != -1) widget.allEntities[idx] = _entity;
    widget.storage.saveData(
      entities: widget.allEntities,
      categories: widget.allCategories,
      tags: _allTags,
      entityLinks: widget.allEntityLinks,
      boards: widget.allBoards,
      boardEntities: widget.allBoardEntities,
    );
  }

  void _commitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _entity.name = trimmed;
      _isEditingName = false;
    });
    _save();
  }

  void _changeCategory(String? id) {
    if (id == null) return;
    setState(() => _entity.categoryId = id);
    _save();
  }

  void _addTag(String raw) {
    final tag = raw.trim().toLowerCase();
    if (tag.isEmpty || _entity.tags.contains(tag)) {
      setState(() => _isAddingTag = false);
      _tagController.clear();
      return;
    }
    setState(() {
      _entity.tags.add(tag);
      if (!_allTags.contains(tag)) _allTags.add(tag);
      _isAddingTag = false;
    });
    _tagController.clear();
    _save();
  }

  void _removeTag(String tag) {
    setState(() => _entity.tags.remove(tag));
    _save();
  }

  void _addNote(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _entity.notes.add(trimmed);
      _isAddingNote = false;
    });
    _noteController.clear();
    _save();
  }

  void _commitNoteEdit(int index, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() => _editingNoteIndex = null);
      return;
    }
    setState(() {
      _entity.notes[index] = trimmed;
      _editingNoteIndex = null;
    });
    _save();
  }

  void _deleteNote(int index) {
    setState(() {
      _entity.notes.removeAt(index);
      if (_editingNoteIndex == index) _editingNoteIndex = null;
    });
    _save();
  }

  void _addLink(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _entity.links.add(trimmed);
      _isAddingLink = false;
    });
    _linkController.clear();
    _save();
  }

  void _commitLinkEdit(int index, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() => _editingLinkIndex = null);
      return;
    }
    setState(() {
      _entity.links[index] = trimmed;
      _editingLinkIndex = null;
    });
    _save();
  }

  void _deleteLink(int index) {
    setState(() {
      _entity.links.removeAt(index);
      if (_editingLinkIndex == index) _editingLinkIndex = null;
    });
    _save();
  }

  // ── Score ─────────────────────────────────────────────────────────────────

  void _setScore(double value) {
    final rounded = (value * 10).round() / 10;
    setState(() => _entity.score = rounded);
  }

  // ── Boards ────────────────────────────────────────────────────────────────

  List<Board> get _entityBoards => widget.allBoards
      .where((b) => widget.allBoardEntities
          .any((be) => be.boardId == b.id && be.entityId == _entity.id))
      .toList();

  void _addToBoard(String boardId) {
    if (StorageService.boardEntryExists(boardId, _entity.id, widget.allBoardEntities)) return;
    setState(() {
      widget.allBoardEntities.add(BoardEntity(boardId: boardId, entityId: _entity.id));
    });
    _save();
  }

  void _removeFromBoard(String boardId) {
    setState(() {
      widget.allBoardEntities.removeWhere(
          (be) => be.boardId == boardId && be.entityId == _entity.id);
    });
    _save();
  }

  void _showAddToBoard() {
    final alreadyIn = widget.allBoardEntities
        .where((be) => be.entityId == _entity.id)
        .map((be) => be.boardId)
        .toSet();
    final candidates = widget.allBoards.where((b) => !alreadyIn.contains(b.id)).toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add to board',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No boards available.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              for (final board in candidates)
                ListTile(
                  title: Text(board.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addToBoard(board.id);
                  },
                ),
          ],
        ),
      ),
    );
  }

  // ── Entity linking ────────────────────────────────────────────────────────

  void _createEntityLink(String targetId) {
    if (targetId == _entity.id) return;
    if (StorageService.linkExists(_entity.id, targetId, widget.allEntityLinks)) return;
    final link = EntityLink(
      id: StorageService.generateLinkId(_entity.id, targetId),
      from: _entity.id,
      to: targetId,
    );
    setState(() => widget.allEntityLinks.add(link));
    _save();
  }

  void _deleteEntityLink(String linkId) {
    setState(() => widget.allEntityLinks.removeWhere((l) => l.id == linkId));
    _save();
  }

  EntityLink? _findLink(String otherId) {
    try {
      return widget.allEntityLinks.firstWhere(
        (l) => (l.from == _entity.id && l.to == otherId) ||
               (l.from == otherId && l.to == _entity.id),
      );
    } catch (_) {
      return null;
    }
  }

  void _showLinkSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final candidates = widget.allEntities.where((e) {
              if (e.id == _entity.id) return false;
              if (StorageService.linkExists(_entity.id, e.id, widget.allEntityLinks)) return false;
              if (query.isEmpty) return true;
              return e.name.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: 400,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                      child: candidates.isEmpty
                          ? const Center(
                              child: Text('No entities found.',
                                  style: TextStyle(color: Colors.grey)),
                            )
                          : ListView.builder(
                              itemCount: candidates.length,
                              itemBuilder: (_, i) {
                                final e = candidates[i];
                                return ListTile(
                                  title: Text(e.name),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _createEntityLink(e.id);
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

  // ── AppBar title ──────────────────────────────────────────────────────────

  Widget _buildTitle() {
    if (_isEditingName) {
      return TextField(
        controller: _nameController,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
        onSubmitted: (_) => _commitName(),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _isEditingName = true),
      child: Text(_entity.name),
    );
  }

  // ── Tags ──────────────────────────────────────────────────────────────────

  Widget _buildTagsSection() {
    final suggestions = _allTags.where((t) => !_entity.tags.contains(t)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Tags',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in _entity.tags)
                Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeTag(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              if (_isAddingTag)
                SizedBox(
                  width: 150,
                  child: RawAutocomplete<String>(
                    textEditingController: _tagController,
                    focusNode: FocusNode()..requestFocus(),
                    optionsBuilder: (value) {
                      if (value.text.trim().isEmpty) return suggestions;
                      final q = value.text.toLowerCase();
                      return suggestions.where((t) => t.contains(q));
                    },
                    onSelected: _addTag,
                    fieldViewBuilder: (ctx, ctrl, fn, onSubmit) => TextField(
                      controller: ctrl,
                      focusNode: fn,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'tag…',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      onSubmitted: _addTag,
                    ),
                    optionsViewBuilder: (ctx, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxHeight: 160, maxWidth: 180),
                          child: ListView(
                            shrinkWrap: true,
                            children: options
                                .map((t) => ListTile(
                                      dense: true,
                                      title: Text(t,
                                          style: const TextStyle(fontSize: 13)),
                                      onTap: () => onSelected(t),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                ActionChip(
                  label: const Text('＋ tag', style: TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _isAddingTag = true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Score ─────────────────────────────────────────────────────────────────

  Widget _buildScoreSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Text('Score',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(width: 12),
              if (_entity.score != null)
                Text(
                  _entity.score!.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade700),
                )
              else
                Text('Not set',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const Spacer(),
              if (_entity.score == null)
                TextButton.icon(
                  onPressed: () {
                    setState(() => _entity.score = 5.0);
                    _save();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Set', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () {
                    setState(() => _entity.score = null);
                    _save();
                  },
                  tooltip: 'Remove score',
                ),
            ],
          ),
        ),
        if (_entity.score != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Slider(
              value: _entity.score!,
              min: 0,
              max: 10,
              divisions: 100,
              label: _entity.score!.toStringAsFixed(1),
              onChanged: _setScore,
              onChangeEnd: (_) => _save(),
            ),
          ),
      ],
    );
  }

  // ── Boards ────────────────────────────────────────────────────────────────

  Widget _buildBoardsSection() {
    final boards = _entityBoards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Text('Boards',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              if (widget.allBoards.isNotEmpty)
                TextButton.icon(
                  onPressed: _showAddToBoard,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add to board', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ),
        if (boards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              widget.allBoards.isEmpty
                  ? 'No boards yet. Create one from the Boards screen.'
                  : 'Not in any board.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final board in boards)
                  Chip(
                    label: Text(board.name, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _removeFromBoard(board.id),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Text('Why it matters',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  _isAddingNote = true;
                  _noteController.clear();
                }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < _entity.notes.length; i++) _buildNoteItem(i),
        if (_isAddingNote) _buildNoteAddField(),
        if (_entity.notes.isEmpty && !_isAddingNote)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('No notes yet.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _buildNoteItem(int i) {
    if (_editingNoteIndex == i) {
      final ctrl = TextEditingController(text: _entity.notes[i]);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: null,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => _commitNoteEdit(i, v),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, size: 18),
              onPressed: () => _commitNoteEdit(i, ctrl.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _editingNoteIndex = null),
            ),
          ],
        ),
      );
    }
    return ListTile(
      dense: true,
      title: Text(_entity.notes[i], style: const TextStyle(fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
            onPressed: () => setState(() => _editingNoteIndex = i),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
            onPressed: () => _deleteNote(i),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteAddField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _noteController,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Add a note…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: _addNote,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 18),
            onPressed: () => _addNote(_noteController.text),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _isAddingNote = false;
              _noteController.clear();
            }),
          ),
        ],
      ),
    );
  }

  // ── Sources ───────────────────────────────────────────────────────────────

  Widget _buildLinksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Text('Sources',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  _isAddingLink = true;
                  _linkController.clear();
                }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < _entity.links.length; i++) _buildLinkItem(i),
        if (_isAddingLink) _buildLinkAddField(),
        if (_entity.links.isEmpty && !_isAddingLink)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('No links yet.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _buildLinkItem(int i) {
    if (_editingLinkIndex == i) {
      final ctrl = TextEditingController(text: _entity.links[i]);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => _commitLinkEdit(i, v),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, size: 18),
              onPressed: () => _commitLinkEdit(i, ctrl.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _editingLinkIndex = null),
            ),
          ],
        ),
      );
    }
    return ListTile(
      dense: true,
      title: Text(
        _entity.links[i],
        style: const TextStyle(
            fontSize: 13,
            color: Colors.blue,
            decoration: TextDecoration.underline),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
            onPressed: () => setState(() => _editingLinkIndex = i),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
            onPressed: () => _deleteLink(i),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkAddField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _linkController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'Add a link…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: _addLink,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 18),
            onPressed: () => _addLink(_linkController.text),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _isAddingLink = false;
              _linkController.clear();
            }),
          ),
        ],
      ),
    );
  }

  // ── Related ───────────────────────────────────────────────────────────────

  Widget _buildRelatedSection() {
    final related = StorageService.getRelatedEntities(
        _entity.id, widget.allEntityLinks, widget.allEntities);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Text('Related',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: _showLinkSearch,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Link entity', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        if (related.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('No related entities.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          for (final other in related)
            ListTile(
              dense: true,
              title: Text(other.name, style: const TextStyle(fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.link_off, size: 16, color: Colors.grey),
                onPressed: () {
                  final link = _findLink(other.id);
                  if (link != null) _deleteEntityLink(link.id);
                },
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EntityScreen(
                    entity: other,
                    storage: widget.storage,
                    allEntities: widget.allEntities,
                    allCategories: widget.allCategories,
                    allTags: _allTags,
                    allEntityLinks: widget.allEntityLinks,
                    allBoards: widget.allBoards,
                    allBoardEntities: widget.allBoardEntities,
                  ),
                ),
              ).then((_) => setState(() {})),
            ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentCategory = widget.allCategories.firstWhere(
      (c) => c.id == _entity.categoryId,
      orElse: () => widget.allCategories.isNotEmpty
          ? widget.allCategories.first
          : Category(id: '', name: ''),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: _buildTitle(),
        actions: [
          if (!_isEditingName)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditingName = true),
              tooltip: 'Rename',
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _commitName,
              tooltip: 'Save name',
            ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButton<String>(
                value: currentCategory.id.isNotEmpty ? currentCategory.id : null,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: widget.allCategories
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: _changeCategory,
              ),
            ),
          ),
          _buildTagsSection(),
          const Divider(height: 24),
          _buildScoreSection(),
          const Divider(height: 24),
          _buildBoardsSection(),
          const Divider(height: 24),
          _buildNotesSection(),
          const Divider(height: 24),
          _buildLinksSection(),
          const Divider(height: 24),
          _buildRelatedSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
