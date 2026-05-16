import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/board.dart';
import '../models/board_entity.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/grokipedia_service.dart';
import '../services/markdown_storage_service.dart';

class EntityScreen extends StatefulWidget {
  final Entity entity;
  final MarkdownStorageService storage;
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

  bool _isEditMode = false;
  late Entity _editSnapshot;

  // Grokipedia external knowledge state
  GrokipediaArticle? _grokArticle;
  bool _grokSearched = false;
  bool _grokSummaryExpanded = false;
  bool _grokSummaryFetching = false;
  String? _grokFetchedSummary;

  // edit-mode inline state
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
    _entity = widget.entity.copyWith();
    _allTags = List<String>.from(widget.allTags);
    _fetchGrokipedia();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _linkController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  // ── Edit mode lifecycle ───────────────────────────────────────────────────

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _editSnapshot = _entity.copyWith();
      _nameController.text = _entity.name;
      _isAddingNote = false;
      _isAddingLink = false;
      _isAddingTag = false;
      _editingNoteIndex = null;
      _editingLinkIndex = null;
    });
  }

  void _saveEdit() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty) _entity.name = trimmed;
    _save();
    setState(() => _isEditMode = false);
  }

  void _cancelEdit() {
    final restored = _editSnapshot.copyWith();
    final idx = widget.allEntities.indexWhere((e) => e.id == restored.id);
    if (idx != -1) widget.allEntities[idx] = restored;
    setState(() {
      _entity = restored;
      _isEditMode = false;
    });
  }

  // ── Persistence ───────────────────────────────────────────────────────────

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

  // ── Core field mutations (no auto-save; committed on Save) ────────────────

  void _changeCategory(String? id) {
    if (id == null) return;
    setState(() => _entity.categoryId = id);
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
  }

  void _removeTag(String tag) {
    setState(() => _entity.tags.remove(tag));
  }

  void _addNote(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _entity.notes.add(trimmed);
      _isAddingNote = false;
    });
    _noteController.clear();
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
  }

  void _deleteNote(int index) {
    setState(() {
      _entity.notes.removeAt(index);
      if (_editingNoteIndex == index) _editingNoteIndex = null;
    });
  }

  void _addLink(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _entity.links.add(trimmed);
      _isAddingLink = false;
    });
    _linkController.clear();
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
  }

  void _deleteLink(int index) {
    setState(() {
      _entity.links.removeAt(index);
      if (_editingLinkIndex == index) _editingLinkIndex = null;
    });
  }

  void _setScore(double value) {
    setState(() => _entity.score = (value * 10).round() / 10);
  }

  // ── Board mutations (immediate save — mutate join tables) ─────────────────

  List<Board> get _entityBoards => widget.allBoards
      .where((b) => widget.allBoardEntities
          .any((be) => be.boardId == b.id && be.entityId == _entity.id))
      .toList();

  void _addToBoard(String boardId) {
    if (MarkdownStorageService.boardEntryExists(boardId, _entity.id, widget.allBoardEntities)) return;
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
    final candidates = widget.allBoards
        .where((b) => !alreadyIn.contains(b.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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

  // ── Entity link mutations (immediate save) ────────────────────────────────

  void _createEntityLink(String targetId) {
    if (targetId == _entity.id) return;
    if (MarkdownStorageService.linkExists(_entity.id, targetId, widget.allEntityLinks)) return;
    final link = EntityLink(
      id: MarkdownStorageService.generateLinkId(_entity.id, targetId),
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
              if (MarkdownStorageService.linkExists(_entity.id, e.id, widget.allEntityLinks)) return false;
              if (query.isEmpty) return true;
              return e.name.toLowerCase().contains(query.toLowerCase());
            }).toList()
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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

  // ── Grokipedia external knowledge ─────────────────────────────────────────

  Future<void> _fetchGrokipedia() async {
    final article = await GrokipediaService.findArticle(_entity.name);
    if (mounted) {
      setState(() {
        _grokArticle = article;
        _grokSearched = true;
      });
    }
  }

  Future<void> _toggleGrokSummary() async {
    if (!_grokSummaryExpanded) {
      setState(() => _grokSummaryExpanded = true);
      if (_grokArticle?.snippet == null &&
          _grokFetchedSummary == null &&
          !_grokSummaryFetching) {
        setState(() => _grokSummaryFetching = true);
        final summary = await GrokipediaService.fetchPageSummary(_grokArticle!.slug);
        if (mounted) {
          setState(() {
            _grokFetchedSummary = summary;
            _grokSummaryFetching = false;
          });
        }
      }
    } else {
      setState(() => _grokSummaryExpanded = false);
    }
  }

  Future<void> _openGrokArticle(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open article')),
        );
      }
    }
  }

  Widget _buildExternalKnowledgeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('External Knowledge',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        if (!_grokSearched)
          Text('Searching Grokipedia…',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else if (_grokArticle == null)
          Text('No Grokipedia article found.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else ...[
          Text(
            _grokArticle!.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _openGrokArticle(_grokArticle!.webUrl),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Open Article', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _toggleGrokSummary,
                icon: Icon(
                  _grokSummaryExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                ),
                label: const Text('Summary', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (_grokSummaryExpanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _grokSummaryFetching
                  ? const Row(children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Loading summary…', style: TextStyle(fontSize: 13)),
                    ])
                  : Text(
                      _grokArticle!.snippet ??
                          _grokFetchedSummary ??
                          'No summary available.',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
            ),
          ],
        ],
      ],
    );
  }

  // ── Display body ──────────────────────────────────────────────────────────

  Widget _buildDisplayBody() {
    final currentCategory = widget.allCategories.firstWhere(
      (c) => c.id == _entity.categoryId,
      orElse: () => widget.allCategories.isNotEmpty
          ? widget.allCategories.first
          : Category(id: '', name: ''),
    );
    final boards = _entityBoards;
    final related = MarkdownStorageService.getRelatedEntities(
        _entity.id, widget.allEntityLinks, widget.allEntities);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // Name
        Text(
          _entity.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        // Category
        if (currentCategory.name.isNotEmpty)
          Text(
            currentCategory.name,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        const SizedBox(height: 12),
        // Tags
        if (_entity.tags.isEmpty)
          Text('No tags.', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _entity.tags
                .map((tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        const SizedBox(height: 12),
        // Score
        if (_entity.score != null)
          Row(
            children: [
              Text(
                '★ ${_entity.score!.toStringAsFixed(1)}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade700),
              ),
            ],
          )
        else
          Text('No score set.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        // Boards
        if (boards.isEmpty)
          Text('Not in any board.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: boards
                .map((b) => Chip(
                      label: Text(b.name, style: const TextStyle(fontSize: 12)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),

        const Divider(height: 32),

        // Why it matters
        const Text('Why it matters',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        if (_entity.notes.isEmpty)
          Text('No notes yet.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else
          for (final note in _entity.notes) ...[
            Text(note, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],

        const Divider(height: 32),

        // Sources
        const Text('Sources',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        if (_entity.links.isEmpty)
          Text('No sources yet.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else
          for (final link in _entity.links) ...[
            Text(
              link,
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.blue,
                  decoration: TextDecoration.underline),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
          ],

        const Divider(height: 32),

        // Related
        const Text('Related',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        if (related.isEmpty)
          Text('No related entities.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
        else
          for (final other in related)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(other.name, style: const TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
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

        const Divider(height: 32),
        _buildExternalKnowledgeSection(),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Edit body ─────────────────────────────────────────────────────────────

  Widget _buildEditBody() {
    final currentCategory = widget.allCategories.firstWhere(
      (c) => c.id == _entity.categoryId,
      orElse: () => widget.allCategories.isNotEmpty
          ? widget.allCategories.first
          : Category(id: '', name: ''),
    );

    return ListView(
      children: [
        // Name field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        // Category
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
    );
  }

  // ── Edit section builders ─────────────────────────────────────────────────

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
            ),
          ),
      ],
    );
  }

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
                  ? 'No boards yet.'
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

  Widget _buildRelatedSection() {
    final related = MarkdownStorageService.getRelatedEntities(
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(_entity.name),
        actions: _isEditMode
            ? [
                TextButton(
                  onPressed: _cancelEdit,
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: _saveEdit,
                  child: const Text('Save',
                      style: TextStyle(color: Colors.white)),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _enterEditMode,
                  tooltip: 'Edit',
                ),
              ],
      ),
      body: _isEditMode ? _buildEditBody() : _buildDisplayBody(),
    );
  }
}
