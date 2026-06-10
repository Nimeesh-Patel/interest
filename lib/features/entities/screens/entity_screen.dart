import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/collection.dart';
import '../models/entity.dart';
import '../services/grokipedia_service.dart';
import '../services/markdown_storage_service.dart';
import '../../resurface/screens/note_edit_screen.dart';
import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/widgets/backlinks_section.dart';
import '../../../shared/widgets/note_markdown.dart';
import '../../../shared/widgets/progress.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/snack.dart';
import '../../resurface/services/resurface_service.dart';

/// An entity is a plain note that belongs to a collection. This screen is a
/// note VIEWER built on the shared note-view primitives ([noteMarkdownBody],
/// [BacklinksSection], Open-in-Obsidian) plus entity-specific bits (collection/
/// tags/score frontmatter editing, Grokipedia). The body is edited as plain
/// Markdown via [NoteEditScreen]; the app never rewrites an entity's body.
class EntityScreen extends StatefulWidget {
  final Entity entity;
  final MarkdownStorageService storage;
  final List<Entity> allEntities;
  final List<Collection> allCollections;
  final List<String> allTags;

  /// Routes a file path through the canonical note router
  /// (`ResurfaceScreenState.openNoteByPath`). Called when a wikilink or
  /// backlink target should NOT open in EntityScreen: a non-entity note, or
  /// a both-note — `***` takes priority over `collection:`.
  final Future<void> Function(String filePath)? onOpenNoteByPath;

  const EntityScreen({
    super.key,
    required this.entity,
    required this.storage,
    required this.allEntities,
    required this.allCollections,
    required this.allTags,
    this.onOpenNoteByPath,
  });

  @override
  State<EntityScreen> createState() => _EntityScreenState();
}

class _EntityScreenState extends State<EntityScreen> {
  late Entity _entity;
  late List<String> _allTags;

  bool _isEditMode = false;
  late Entity _editSnapshot;
  bool _isAddingTag = false;

  String? _bodyText;
  bool _loadingBody = true;

  // Grokipedia external knowledge state
  GrokipediaArticle? _grokArticle;
  bool _grokSearched = false;
  bool _grokSummaryExpanded = false;
  bool _grokSummaryFetching = false;
  String? _grokFetchedSummary;

  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entity = widget.entity.copyWith();
    _allTags = List<String>.from(widget.allTags);
    _loadBody();
    _fetchGrokipedia();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  // ── Body load (read-only) ──────────────────────────────────────────────────

  Future<void> _loadBody() async {
    final path = _entity.sourcePath;
    if (path == null) {
      setState(() {
        _bodyText = '';
        _loadingBody = false;
      });
      return;
    }
    try {
      final raw = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        _bodyText = splitFrontmatter(raw).body;
        _loadingBody = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bodyText = '';
        _loadingBody = false;
      });
    }
  }

  Future<void> _editNote() async {
    final path = _entity.sourcePath;
    if (path == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditScreen(filePath: path)),
    );
    await _loadBody();
  }

  // ── Frontmatter edit lifecycle ──────────────────────────────────────────────

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _editSnapshot = _entity.copyWith();
      _isAddingTag = false;
    });
  }

  Future<void> _saveEdit() async {
    await widget.storage.saveEntity(_entity);
    final idx = widget.allEntities.indexWhere((e) => e.id == _entity.id);
    if (idx != -1) widget.allEntities[idx] = _entity;
    if (!mounted) return;
    setState(() {
      _isEditMode = false;
      _isAddingTag = false;
    });
  }

  void _cancelEdit() {
    setState(() {
      _entity = _editSnapshot.copyWith();
      _isEditMode = false;
      _isAddingTag = false;
    });
  }

  // ── Frontmatter field mutations (committed on Save) ─────────────────────────

  void _changeCollection(String? id) {
    if (id == null) return;
    final match = widget.allCollections.where((c) => c.id == id);
    if (match.isEmpty) return;
    setState(() => _entity.collection = match.first.name);
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

  void _removeTag(String tag) => setState(() => _entity.tags.remove(tag));

  void _setScore(double value) =>
      setState(() => _entity.score = (value * 10).round() / 10);

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _openEntity(Entity other) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntityScreen(
          entity: other,
          storage: widget.storage,
          allEntities: widget.allEntities,
          allCollections: widget.allCollections,
          allTags: _allTags,
          onOpenNoteByPath: widget.onOpenNoteByPath,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  /// Navigate to a note by name (wikilink + backlink taps).
  /// `***` takes priority over `collection:`: a both-note target is handed
  /// to the canonical router (card viewer), never opened as EntityScreen.
  /// Entity-only targets open EntityScreen; all other targets route via
  /// [EntityScreen.onOpenNoteByPath] if provided, otherwise show a snackbar.
  Future<void> _navigateToNoteName(String name) async {
    // Fast path: check in-memory entity list first.
    final match = widget.allEntities
        .where((e) => e.name.toLowerCase() == name.toLowerCase());
    if (match.isNotEmpty) {
      final entity = match.first;
      final path = entity.sourcePath;
      if (path != null && widget.onOpenNoteByPath != null) {
        try {
          final body = splitFrontmatter(await File(path).readAsString()).body;
          if (splitFrontBack(body) != null) {
            await widget.onOpenNoteByPath!(path);
            return;
          }
        } catch (_) {}
        if (!mounted) return;
      }
      _openEntity(entity);
      return;
    }
    // Resolve via vault-wide filename scan.
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted) return;
    if (vaultPath == null) {
      showSnack(context, 'Note not found: $name');
      return;
    }
    final path = await ResurfaceService.resolveWikilink(vaultPath, name);
    if (!mounted) return;
    if (path == null) {
      showSnack(context, 'Note not found: $name');
      return;
    }
    widget.onOpenNoteByPath?.call(path);
  }

  Future<void> _openInObsidian() async {
    final path = _entity.sourcePath;
    if (path == null) return;
    final vaultPath = await VaultService.getVaultPath();
    if (vaultPath == null) return;
    final ok = await launchUrl(Uri.parse(obsidianUri(vaultPath, path)),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showSnack(context, 'Obsidian is not installed');
    }
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
      if (mounted) showSnack(context, 'Could not open article');
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
                ? const InlineSpinner(size: 14)
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
                Text(
                  _entity.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    if (_entity.collection.isNotEmpty)
                      Text(_entity.collection, style: AppTextStyles.bodySmall),
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

          // ── Note body ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: _loadingBody
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: InlineSpinner(),
                  )
                : (_bodyText == null || _bodyText!.trim().isEmpty)
                    ? Text('Empty note. Tap edit to write.',
                        style: AppTextStyles.bodySmall)
                    : noteMarkdownBody(
                        context,
                        _bodyText!,
                        onTapLink: (text, href, title) =>
                            onNoteLinkTap(href, _navigateToNoteName),
                      ),
          ),

          // ── Backlinks (shared note-view primitive) ─────────────────────────
          if (_entity.sourcePath != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
              child: BacklinksSection(
                key: ValueKey(_entity.sourcePath),
                noteFilePath: _entity.sourcePath!,
                onNavigateToNote: _navigateToNoteName,
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

  // ── Edit body (frontmatter only) ────────────────────────────────────────────

  Widget _buildEditBody() {
    final currentCollection = widget.allCollections.firstWhere(
      (c) => c.id == _entity.collectionId,
      orElse: () => widget.allCollections.isNotEmpty
          ? widget.allCollections.first
          : Collection(id: '', name: ''),
    );

    return SafeArea(
      top: false,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(_entity.name,
                style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          // Collection
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Collection',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButton<String>(
                value: currentCollection.id.isNotEmpty ? currentCollection.id : null,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                isDense: true,
                dropdownColor: AppColors.surfaceElevated,
                items: widget.allCollections
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: _changeCollection,
              ),
            ),
          ),
          _buildTagsSection(),
          const Divider(height: 24),
          _buildScoreSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

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
                  onPressed: () => setState(() => _entity.score = 5.0),
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
                  onPressed: () => setState(() => _entity.score = null),
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
            : [
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: _openInObsidian,
                  tooltip: 'Open in Obsidian',
                ),
                IconButton(
                  icon: const Icon(Icons.notes_outlined),
                  onPressed: _editNote,
                  tooltip: 'Edit note body',
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: _enterEditMode,
                  tooltip: 'Edit details',
                ),
              ],
      ),
      body: _isEditMode ? _buildEditBody() : _buildDisplayBody(),
    );
  }
}
