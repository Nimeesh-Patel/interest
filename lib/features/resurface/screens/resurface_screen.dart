import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/problem_note.dart';
import '../models/resurface_note.dart';
import '../services/graph_scoring_service.dart';
import '../services/resurface_service.dart';
import '../services/review_log_service.dart';
import '../controllers/card_viewer_controller.dart';
import '_backlinks_section.dart';
import '_note_md_helpers.dart';
import 'note_detail_screen.dart';
import 'note_edit_screen.dart';

// ── Route types ───────────────────────────────────────────────────────────────

sealed class _ResurfaceRoute {
  const _ResurfaceRoute();
}

final class _DeckListRoute extends _ResurfaceRoute {
  const _DeckListRoute();
}

final class _CardViewerRoute extends _ResurfaceRoute {
  final String deckName;
  const _CardViewerRoute(this.deckName);
}

final class _NoteDetailRoute extends _ResurfaceRoute {
  final String filePath;
  const _NoteDetailRoute(this.filePath);
}

// ── Deck list (no Scaffold — HomeScreen provides AppBar) ──────────────────────

class ResurfaceScreen extends StatefulWidget {
  /// Called whenever the nav stack changes so HomeScreen can rebuild its AppBar.
  final VoidCallback? onNavigationChanged;

  const ResurfaceScreen({super.key, this.onNavigationChanged});

  @override
  State<ResurfaceScreen> createState() => ResurfaceScreenState();
}

class ResurfaceScreenState extends State<ResurfaceScreen> {
  // problem note counts for deck list (only isProblemNote notes)
  List<ProblemNote> _problemNotes = [];
  bool _loading = true;
  String? _error;
  String? _vaultPath;

  final List<_ResurfaceRoute> _stack = [const _DeckListRoute()];

  // Card viewer: queue, position, no-repeat logic, review session.
  final _controller = CardViewerController();

  // Incremented after each edit to force NoteDetailScreen to re-read its file.
  int _detailVersion = 0;

  // Search state — session-only, never persisted.
  List<ResurfaceNote> _allNotes = [];
  bool _searchActive = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
        () => setState(() => _searchQuery = _searchController.text));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted) return;
    if (vaultPath == null) {
      setState(() {
        _loading = false;
        _error = 'No vault configured.';
      });
      return;
    }
    _vaultPath = vaultPath;
    final config = await IntegrationsConfigService.load(vaultPath);
    final allNotes = await ResurfaceService.getAllNotes(
      vaultPath,
      excludedFolders: config.resurfaceExcludedFolders,
    );
    if (!mounted) return;
    final problemNotes = allNotes
        .where((n) => n.isProblemNote)
        .map((n) => ProblemNote(
              sourcePath: n.sourcePath,
              sourceFile: n.sourceFile,
              front: n.front!,
              back: n.back!,
              decks: n.decks,
            ))
        .toList();
    setState(() {
      _allNotes = allNotes;
      _problemNotes = problemNotes;
      _loading = false;
    });
  }

  // ── Public API consumed by HomeScreen via GlobalKey ───────────────────────

  /// Title for HomeScreen's AppBar at the current nav depth.
  String get navTitle => switch (_stack.last) {
        _DeckListRoute() => 'Notes',
        _CardViewerRoute(deckName: final n) => n,
        _NoteDetailRoute(filePath: final fp) => _basenameWithoutExt(fp),
      };

  bool get canGoBack => _stack.length > 1;

  /// Absolute path of the note currently visible; null when deck list is showing.
  String? get currentEditFilePath => switch (_stack.last) {
        _NoteDetailRoute(:final filePath) => filePath,
        _CardViewerRoute() => _controller.current?.sourcePath,
        _DeckListRoute() => null,
      };

  /// Called by HomeScreen. Pushes NoteEditScreen and reloads content on save.
  Future<void> openEditForCurrentNote(BuildContext context) async {
    final fp = currentEditFilePath;
    if (fp == null) return;
    final didSave = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditScreen(filePath: fp)),
    );
    if (didSave == true) _reloadAfterEdit(fp);
  }

  /// Called by HomeScreen. Launches Obsidian for the currently visible note.
  Future<void> launchObsidianForCurrentNote(BuildContext context) async {
    final fp = currentEditFilePath;
    if (fp == null || _vaultPath == null) return;
    final uri = obsidianUri(_vaultPath!, fp);
    try {
      final launched = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obsidian not installed')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obsidian not installed')),
        );
      }
    }
  }

  /// Called by HomeScreen when an interest://note deep link arrives.
  /// Routes problem notes to the card viewer, plain notes to the detail screen.
  Future<void> openNoteByName(String name) async {
    final lower = name.toLowerCase();
    final note = _allNotes
        .where((n) => p.basenameWithoutExtension(n.sourceFile).toLowerCase() == lower)
        .firstOrNull;
    if (note != null) {
      _openSearchResult(note);
      return;
    }
    // Fast vault-wide filename scan — no file content parsing.
    final vaultPath = _vaultPath ?? await VaultService.getVaultPath();
    if (vaultPath == null || !mounted) return;
    final path = await ResurfaceService.resolveWikilink(vaultPath, name);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note not found: $name')),
      );
      return;
    }
    final loaded = await ResurfaceService.loadSingleNote(path);
    if (!mounted) return;
    if (loaded != null) {
      _openSearchResult(loaded);
    } else {
      setState(() => _stack.add(_NoteDetailRoute(path)));
      widget.onNavigationChanged?.call();
    }
  }

  void _reloadAfterEdit(String filePath) {
    if (_stack.last is _NoteDetailRoute) {
      setState(() => _detailVersion++);
    } else if (_stack.last is _CardViewerRoute) {
      _reloadViewerNote(filePath);
    }
  }

  Future<void> _reloadViewerNote(String filePath) async {
    final updated = await ResurfaceService.loadSingleNote(filePath);
    if (updated == null) return;
    final notes = _controller.notes;
    final idx = notes.indexWhere((n) => n.sourcePath == filePath);
    if (idx == -1) return;
    final wasProblemNote = notes[idx].isProblemNote;
    // *** note lost its separator → remove from viewer.
    if (wasProblemNote && !updated.isProblemNote) {
      setState(() => _controller.removeAt(idx));
      return;
    }
    // Non-*** note gained a separator → update is_star in log.
    if (!wasProblemNote && updated.isProblemNote) {
      ReviewLogService.recordTraversal(
        p.basenameWithoutExtension(filePath),
        isProblemNote: true,
      );
    }
    setState(() => _controller.reloadNote(idx, updated));
  }

  void goBack() {
    if (_stack.length <= 1) return;
    setState(() {
      _stack.removeLast();
      if (_stack.last is _CardViewerRoute) _controller.resetBackRevealed();
    });
    widget.onNavigationChanged?.call();
  }

  void resetStack() {
    if (_stack.length <= 1 && !_searchActive) return;
    setState(() {
      _stack
        ..clear()
        ..add(const _DeckListRoute());
      _controller.reset();
      _searchActive = false;
      _searchController.clear();
      _searchQuery = '';
    });
    widget.onNavigationChanged?.call();
  }

  /// True when the search icon should be visible in the AppBar.
  bool get isSearchable =>
      !_loading && _error == null && _stack.last is _DeckListRoute;

  bool get isSearchActive => _searchActive;

  void toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
    widget.onNavigationChanged?.call();
  }

  // ── Internal navigation ───────────────────────────────────────────────────

  Future<void> _pushDeck(String deckName, List<ResurfaceNote> starNotes) async {
    // Include activated non-*** notes that belong to this deck.
    final log = await ReviewLogService.loadFullLog();
    final activatedPlain = _allNotes
        .where((n) => !n.isProblemNote)
        .where((n) {
          final e = log[p.basenameWithoutExtension(n.sourceFile)];
          return e != null && e.activatedBy.isNotEmpty;
        })
        .where((n) => _noteBelongsToDeck(n, deckName))
        .toList();

    final allEligible = [...starNotes, ...activatedPlain];
    final result = await GraphScoringService.sortByPriority(allEligible);
    if (!mounted) return;
    setState(() {
      _stack.add(_CardViewerRoute(deckName));
      _controller.load(result.sorted, result.priorities);
    });
    widget.onNavigationChanged?.call();
  }

  List<ResurfaceNote> _notesForDeck(String deckName) {
    final problemNotes = _allNotes.where((n) => n.isProblemNote);
    if (deckName == 'All Notes') return problemNotes.toList();
    if (deckName == 'Default') return problemNotes.where((n) => n.decks.isEmpty).toList();
    return problemNotes.where((n) => n.decks.contains(deckName)).toList();
  }

  bool _noteBelongsToDeck(ResurfaceNote n, String deckName) {
    if (deckName == 'All Notes') return true;
    if (deckName == 'Default') return n.decks.isEmpty;
    return n.decks.contains(deckName);
  }

  Future<void> _handleWikilinkTap(String targetName) async {
    if (_vaultPath == null) return;
    final path = await ResurfaceService.resolveWikilink(_vaultPath!, targetName);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note not found: $targetName')),
      );
      return;
    }
    setState(() => _stack.add(_NoteDetailRoute(path)));
    widget.onNavigationChanged?.call();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  List<ResurfaceNote> get _searchResults {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    return _allNotes.where((n) {
      if (p.basenameWithoutExtension(n.sourceFile).toLowerCase().contains(q)) return true;
      return n.body.toLowerCase().contains(q);
    }).toList();
  }

  String _snippetFor(ResurfaceNote note) {
    final q = _searchQuery.toLowerCase();
    for (final line in note.body.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty && t.toLowerCase().contains(q)) {
        return t.length > 100 ? '${t.substring(0, 100)}…' : t;
      }
    }
    for (final line in note.body.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t.length > 100 ? '${t.substring(0, 100)}…' : t;
    }
    return '';
  }

  void _openSearchResult(ResurfaceNote note) {
    if (note.isProblemNote) {
      _pushDeck(
        p.basenameWithoutExtension(note.sourceFile),
        [note],
      );
    } else {
      setState(() => _stack.add(_NoteDetailRoute(note.sourcePath)));
      widget.onNavigationChanged?.call();
    }
  }

  // ── Deck list helpers ─────────────────────────────────────────────────────

  String _basenameWithoutExt(String filePath) {
    final base = p.basename(filePath);
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  List<_DeckInfo> get _deckItems {
    final named = <String, int>{};
    int defaultCount = 0;
    for (final c in _problemNotes) {
      if (c.decks.isEmpty) {
        defaultCount++;
      } else {
        for (final d in c.decks) {
          named[d] = (named[d] ?? 0) + 1;
        }
      }
    }
    final namedList = named.entries.map((e) => _DeckInfo(e.key, e.value)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return [
      _DeckInfo('All Notes', _problemNotes.length),
      if (defaultCount > 0) _DeckInfo('Default', defaultCount),
      ...namedList,
    ];
  }

  Future<void> _deleteCurrentNote(BuildContext context) async {
    final note = _controller.current;
    if (note == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete note',
      message: 'Delete this note? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try { await File(note.sourcePath).delete(); } catch (_) {}
    await ReviewLogService.removeNote(p.basenameWithoutExtension(note.sourceFile));

    if (!mounted) return;
    setState(() {
      _allNotes.removeWhere((n) => n.sourcePath == note.sourcePath);
      _problemNotes.removeWhere((c) => c.sourcePath == note.sourcePath);
      _controller.removeAt(_controller.index);
    });
    if (_controller.isEmpty) goBack();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return EmptyState(icon: Icons.error_outline, message: _error!);

    return SafeArea(
      top: false,
      child: switch (_stack.last) {
        _DeckListRoute() => _buildDeckListWithSearch(),
        _CardViewerRoute() => _buildCardViewer(),
        _NoteDetailRoute(filePath: final fp) => NoteDetailScreen(
            key: ValueKey('${fp}_$_detailVersion'),
            filePath: fp,
            onNavigateToNote: _handleWikilinkTap,
          ),
      },
    );
  }

  Widget _buildDeckListWithSearch() {
    return Column(
      children: [
        if (_searchActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(kScreenHPad, 8, kScreenHPad, 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search notes…',
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchController.clear,
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
        Expanded(
          child: _searchActive ? _buildSearchResults() : _buildDeckList(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();
    final results = _searchResults;
    if (results.isEmpty) {
      return const Center(
        child: Text('No notes match', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final note = results[i];
        final title = p.basenameWithoutExtension(note.sourceFile);
        final rawSnippet = _snippetFor(note);
        final snippet = plainTextWikilinks(rawSnippet);
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: ListTile(
            title: Text(title),
            subtitle: snippet.isNotEmpty
                ? Text(
                    snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  )
                : null,
            trailing: note.isProblemNote
                ? const Text('✦', style: TextStyle(color: AppColors.accent, fontSize: 12))
                : null,
            onTap: () => _openSearchResult(note),
          ),
        );
      },
    );
  }

  Widget _buildDeckList() {
    if (_allNotes.isEmpty && _problemNotes.isEmpty) {
      return const EmptyState(
        icon: Icons.auto_awesome_outlined,
        message: 'No notes found.\nAdd a *** separator to a note.',
      );
    }
    final deckItems = _deckItems;
    // Named decks are everything after "All Notes" in the list
    final namedDecks =
        deckItems.length > 1 ? deckItems.sublist(1) : <_DeckInfo>[];

    return ListView(
      children: [
        // ── All Notes hero ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(kScreenHPad, 16, kScreenHPad, 4),
          child: GestureDetector(
            onTap: () => _pushDeck('All Notes', _notesForDeck('All Notes')),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.borderMid),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text('✦',
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.accent, fontSize: 16)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('All Notes',
                            style: AppTextStyles.entityName.copyWith(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text('${_problemNotes.length} problem notes to review',
                            style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 15, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
        ),

        // ── Named decks ───────────────────────────────────────────────────
        if (namedDecks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: SectionHeader(title: 'Decks'),
          ),
          const Divider(height: 1),
          for (final deck in namedDecks)
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: InkWell(
                onTap: () => _pushDeck(deck.name, _notesForDeck(deck.name)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: kScreenHPad, vertical: 14),
                  child: Row(
                    children: [
                      Text('✦',
                          style: AppTextStyles.metaMuted
                              .copyWith(fontSize: 11)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(deck.name,
                            style: AppTextStyles.entityName),
                      ),
                      Text('${deck.count}',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textTertiary)),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
        ],

        // ── Browse Notes ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
          child: SectionHeader(title: 'Browse Notes'),
        ),
        const Divider(height: 1),
        for (final note in _allNotes)
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: InkWell(
              onTap: () => _openSearchResult(note),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: kScreenHPad, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.basenameWithoutExtension(note.sourceFile),
                        style: AppTextStyles.entityName,
                      ),
                    ),
                    if (note.isProblemNote)
                      Text('✦',
                          style: AppTextStyles.meta.copyWith(
                              color: AppColors.accent, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardViewer() {
    if (_controller.isEmpty) {
      return const EmptyState(icon: Icons.auto_awesome_outlined, message: 'No notes.');
    }
    return _NoteViewerBody(
      notes: _controller.notes,
      currentIndex: _controller.index,
      backRevealed: _controller.backRevealed,
      onNext: () => setState(() => _controller.goNext()),
      onPrev: () => setState(() => _controller.goPrev()),
      onToggleBack: () => setState(() => _controller.toggleBack()),
      onNavigateToNote: _handleWikilinkTap,
      onDeleteNote: () => _deleteCurrentNote(context),
    );
  }
}

class _DeckInfo {
  final String name;
  final int count;
  const _DeckInfo(this.name, this.count);
}

// ── Mixed note/card viewer body ───────────────────────────────────────────────
// Stateless: all mutable state lives in ResurfaceScreenState.

class _NoteViewerBody extends StatelessWidget {
  final List<ResurfaceNote> notes;
  final int currentIndex;
  final bool backRevealed;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onToggleBack;
  final Future<void> Function(String targetName) onNavigateToNote;
  final VoidCallback? onDeleteNote;

  const _NoteViewerBody({
    required this.notes,
    required this.currentIndex,
    required this.backRevealed,
    required this.onNext,
    required this.onPrev,
    required this.onToggleBack,
    required this.onNavigateToNote,
    this.onDeleteNote,
  });

  String _stripExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  Widget _mdBody(BuildContext context, String data, {Color? textColor}) =>
      noteMarkdownBody(
        context,
        data,
        textColor: textColor,
        onTapLink: (_, href, _) => onNoteLinkTap(href, onNavigateToNote),
      );

  @override
  Widget build(BuildContext context) {
    final note = notes[currentIndex];
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex < notes.length - 1;

    return Column(
      children: [
        // ── Card body ───────────────────────────────────────────────────────
        Expanded(
          child: GestureDetector(
            onTap: note.isProblemNote ? onToggleBack : null,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -200) {
                onNext();
              } else if (v > 200) {
                onPrev();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 40, 26, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.isProblemNote) ...[
                    // Front — IBM Plex Serif 21px
                    _mdBodySerif(context, note.front!, fontSize: 21, height: 1.65),
                    const SizedBox(height: 38),
                    if (!backRevealed)
                      _TapToRevealHint()
                    else ...[
                      const Divider(thickness: 1, color: AppColors.borderMid),
                      const SizedBox(height: 30),
                      // Back — IBM Plex Serif 17px
                      _mdBodySerif(context, note.back!, fontSize: 17, height: 1.78),
                      BacklinksSection(
                        key: ValueKey(note.sourcePath),
                        noteFilePath: note.sourcePath,
                        onNavigateToNote: onNavigateToNote,
                      ),
                    ],
                  ] else ...[
                    MarkdownBody(
                      data: '# ${_stripExtension(note.sourceFile)}',
                      styleSheet: noteMarkdownStyle(context),
                    ),
                    const SizedBox(height: 16),
                    _mdBody(context, note.body),
                    BacklinksSection(
                      key: ValueKey(note.sourcePath),
                      noteFilePath: note.sourcePath,
                      onNavigateToNote: onNavigateToNote,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ── Nav row ─────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kScreenHPad, vertical: 12),
              child: Row(
                children: [
                  // Prev button
                  GestureDetector(
                    onTap: hasPrev ? onPrev : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: hasPrev
                              ? AppColors.border
                              : AppColors.textTertiary,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new,
                              size: 14,
                              color: hasPrev
                                  ? AppColors.textSecondary
                                  : AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text('Prev',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: hasPrev
                                      ? AppColors.textSecondary
                                      : AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${currentIndex + 1} / ${notes.length}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  const Spacer(),
                  // Next button
                  GestureDetector(
                    onTap: hasNext ? onNext : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 9),
                      decoration: BoxDecoration(
                        color: hasNext
                            ? AppColors.accent
                            : AppColors.accentDim,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Next',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios,
                              size: 14, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: AppColors.textPrimary, size: 20),
                    onSelected: (v) {
                      if (v == 'delete') onDeleteNote?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete note',
                          style: TextStyle(color: AppColors.destructive),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mdBodySerif(BuildContext context, String data,
      {required double fontSize, required double height}) {
    return MarkdownBody(
      data: substituteWikilinks(data),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: AppTextStyles.cardAnswer.copyWith(fontSize: fontSize, height: height),
        strong: AppTextStyles.cardAnswer.copyWith(
          fontSize: fontSize,
          height: height,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
        a: const TextStyle(color: AppColors.accent, decoration: TextDecoration.none),
      ),
      onTapLink: (_, href, _) => onNoteLinkTap(href, onNavigateToNote),
    );
  }
}

class _TapToRevealHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: const Text(
          'tap to reveal',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
