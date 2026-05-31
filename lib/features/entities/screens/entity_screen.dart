import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/category.dart';
import '../models/entity.dart';
import '../models/entity_link.dart';
import '../services/grokipedia_service.dart';
import '../services/markdown_storage_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/section_header.dart';

class EntityScreen extends StatefulWidget {
  final Entity entity;
  final MarkdownStorageService storage;
  final List<Entity> allEntities;
  final List<Category> allCategories;
  final List<String> allTags;
  final List<EntityLink> allEntityLinks;

  const EntityScreen({
    super.key,
    required this.entity,
    required this.storage,
    required this.allEntities,
    required this.allCategories,
    required this.allTags,
    required this.allEntityLinks,
  });

  @override
  State<EntityScreen> createState() => _EntityScreenState();
}

class _EntityScreenState extends State<EntityScreen> {
  late Entity _entity;
  late List<String> _allTags;

  bool _isEditMode = false;
  late Entity _editSnapshot;
  bool _hasUnsavedChanges = false;
  bool _editingTitle = false;

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

  void _markDirty() {
    if (!_hasUnsavedChanges) {
      _editSnapshot = _entity.copyWith();
      _nameController.text = _entity.name;
    }
    setState(() => _hasUnsavedChanges = true);
  }

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
    setState(() {
      _isEditMode = false;
      _hasUnsavedChanges = false;
      _editingTitle = false;
      _editingNoteIndex = null;
      _isAddingNote = false;
    });
  }

  void _cancelEdit() {
    final restored = _editSnapshot.copyWith();
    final idx = widget.allEntities.indexWhere((e) => e.id == restored.id);
    if (idx != -1) widget.allEntities[idx] = restored;
    setState(() {
      _entity = restored;
      _isEditMode = false;
      _hasUnsavedChanges = false;
      _editingTitle = false;
      _editingNoteIndex = null;
      _isAddingNote = false;
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
    if (trimmed.isEmpty) {
      setState(() => _isAddingNote = false);
      _noteController.clear();
      return;
    }
    _markDirty();
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
    _markDirty();
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
                height: MediaQuery.of(ctx).size.height * 0.55,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search entities…',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: candidates.isEmpty
                          ? const Center(
                              child: Text('No entities found.',
                                  style: TextStyle(color: AppColors.textSecondary)),
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

  Widget _buildGrokipediaCard() {
    if (!_grokSearched) {
      return Text('Searching…', style: AppTextStyles.bodySmall);
    }
    if (_grokArticle == null) {
      return Text('No article found.', style: AppTextStyles.bodySmall);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderMid),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_grokSummaryExpanded) ...[
            _grokSummaryFetching
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _grokArticle!.snippet ??
                        _grokFetchedSummary ??
                        'No summary available.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.65,
                    ),
                  ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              GestureDetector(
                onTap: () => _openGrokArticle(_grokArticle!.webUrl),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_new,
                        size: 13, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text('Read full article',
                        style: AppTextStyles.meta
                            .copyWith(color: AppColors.accent)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _toggleGrokSummary,
                child: Text(
                  _grokSummaryExpanded ? 'Hide summary' : 'Show summary',
                  style: AppTextStyles.meta
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
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
    final related = MarkdownStorageService.getRelatedEntities(
        _entity.id, widget.allEntityLinks, widget.allEntities);

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Title block ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(kScreenHPad, 22, kScreenHPad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_editingTitle)
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        setState(() => _editingTitle = false),
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide:
                            const BorderSide(color: AppColors.accent),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide:
                            const BorderSide(color: AppColors.accent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      _markDirty();
                      setState(() => _editingTitle = true);
                    },
                    child: Text(
                      _entity.name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    if (currentCategory.name.isNotEmpty)
                      Text(currentCategory.name,
                          style: AppTextStyles.bodySmall),
                    for (final tag in _entity.tags)
                      Text('#$tag',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.accent)),
                    if (_entity.score != null)
                      Text(
                        '★${_entity.score!.toStringAsFixed(_entity.score! % 1 == 0 ? 0 : 1)}',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.score),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 32),

          // ── Why Interesting ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: SectionHeader(title: 'Why Interesting'),
          ),
          if (_entity.notes.isEmpty && !_isAddingNote)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kScreenHPad, vertical: 4),
              child: Text('No notes yet.',
                  style: AppTextStyles.bodySmall),
            ),
          for (int i = 0; i < _entity.notes.length; i++)
            _editingNoteIndex == i
                ? _buildInlineNoteField(i)
                : GestureDetector(
                    onTap: () {
                      _markDirty();
                      setState(() => _editingNoteIndex = i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: kScreenHPad, vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('· ',
                              style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.textTertiary,
                                  height: 1.55)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_entity.notes[i],
                                style: AppTextStyles.bodyLarge
                                    .copyWith(height: 1.55)),
                          ),
                        ],
                      ),
                    ),
                  ),
          if (_isAddingNote) _buildNoteAddField(),
          // Always-visible + Add note row
          GestureDetector(
            onTap: () {
              _markDirty();
              setState(() {
                _isAddingNote = true;
                _noteController.clear();
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kScreenHPad, vertical: 8),
              child: Text('+ Add note',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textTertiary)),
            ),
          ),
          const Divider(height: 32),

          // ── Sources ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: SectionHeader(title: 'Sources'),
          ),
          if (_entity.links.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kScreenHPad, vertical: 4),
              child: Text('No sources yet.',
                  style: AppTextStyles.bodySmall),
            )
          else
            for (final link in _entity.links)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: kScreenHPad, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.link,
                        size: 14, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(link,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.accent),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
          const Divider(height: 32),

          // ── Related ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: SectionHeader(title: 'Related'),
          ),
          if (related.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GestureDetector(
                    onTap: _showLinkSearch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add,
                              size: 13, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text('Link',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ...related.map((other) => GestureDetector(
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
                            ),
                          ),
                        ).then((_) => setState(() {})),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.accentDim),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('[[${other.name}]]',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.accent)),
                        ),
                      )),
                  // Always-visible + Link chip
                  GestureDetector(
                    onTap: _showLinkSearch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add,
                              size: 13, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text('Link',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 32),

          // ── Grokipedia ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: SectionHeader(title: 'Grokipedia'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: _buildGrokipediaCard(),
          ),
          const SizedBox(height: 16),
        ],
      ),
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

    return SafeArea(top: false, child: ListView(
      children: [
        // Name field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
          ),
        ),
        // Category
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Category',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButton<String>(
              value: currentCategory.id.isNotEmpty ? currentCategory.id : null,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              isDense: true,
              dropdownColor: AppColors.surfaceElevated,
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
        _buildNotesSection(),
        const Divider(height: 24),
        _buildLinksSection(),
        const Divider(height: 24),
        _buildRelatedSection(),
        const SizedBox(height: 32),
      ],
    ));
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
                  fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textSecondary)),
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
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _addTag,
                    ),
                    optionsViewBuilder: (ctx, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: AppColors.surfaceElevated,
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
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.score),
                )
              else
                const Text('Not set',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                decoration: const InputDecoration(isDense: true),
                textInputAction: TextInputAction.done,
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
            icon: const Icon(Icons.edit, size: 16, color: AppColors.textTertiary),
            onPressed: () => setState(() => _editingNoteIndex = i),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
            onPressed: () => _deleteNote(i),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineNoteField(int i) {
    final ctrl = TextEditingController(text: _entity.notes[i]);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: kScreenHPad, vertical: 4),
      child: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: null,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => _commitNoteEdit(i, v),
        style: AppTextStyles.bodyLarge.copyWith(height: 1.55),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, size: 18, color: AppColors.accent),
            onPressed: () => _commitNoteEdit(i, ctrl.text),
          ),
        ),
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
              ),
              textInputAction: TextInputAction.done,
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(isDense: true),
                textInputAction: TextInputAction.done,
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
        style: const TextStyle(fontSize: 13, color: AppColors.accent),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: AppColors.textTertiary),
            onPressed: () => setState(() => _editingLinkIndex = i),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
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
              ),
              textInputAction: TextInputAction.done,
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          )
        else
          for (final other in related)
            ListTile(
              dense: true,
              title: Text(other.name, style: const TextStyle(fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.link_off, size: 16, color: AppColors.textTertiary),
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
        title: Text(_entity.name),
        actions: _isEditMode
            ? [
                TextButton(
                  onPressed: _cancelEdit,
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: _saveEdit,
                  child: const Text('Save',
                      style: TextStyle(color: AppColors.accent)),
                ),
              ]
            : _hasUnsavedChanges
                ? [
                    IconButton(
                      icon: const Icon(Icons.check,
                          color: AppColors.accent),
                      tooltip: 'Done',
                      onPressed: _saveEdit,
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
