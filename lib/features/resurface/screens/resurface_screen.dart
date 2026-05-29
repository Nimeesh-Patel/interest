import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/resurface_card.dart';
import '../models/resurface_note.dart';
import '../services/resurface_service.dart';
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
  List<ResurfaceCard> _cards = [];
  bool _loading = true;
  String? _error;
  String? _vaultPath;

  final List<_ResurfaceRoute> _stack = [const _DeckListRoute()];

  // Card viewer state hoisted here to survive note-detail pushes.
  List<ResurfaceCard> _viewerCards = [];
  int _viewerIndex = 0;
  bool _viewerBackRevealed = false;

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
    final cards = allNotes
        .where((n) => n.hasCard)
        .map((n) => ResurfaceCard(
              sourcePath: n.sourcePath,
              sourceFile: n.sourceFile,
              front: n.front!,
              back: n.back!,
              decks: n.decks,
            ))
        .toList();
    setState(() {
      _allNotes = allNotes;
      _cards = cards;
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
        _CardViewerRoute() =>
          _viewerCards.isEmpty ? null : _viewerCards[_viewerIndex].sourcePath,
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

  void _reloadAfterEdit(String filePath) {
    if (_stack.last is _NoteDetailRoute) {
      setState(() => _detailVersion++);
    } else if (_stack.last is _CardViewerRoute) {
      _reloadCard(filePath);
    }
  }

  Future<void> _reloadCard(String filePath) async {
    try {
      final raw = await File(filePath).readAsString();
      final split = splitFrontmatter(raw);
      final fb = splitFrontBack(split.body);
      if (fb == null) {
        final idx = _viewerCards.indexWhere((c) => c.sourcePath == filePath);
        if (idx != -1) {
          setState(() {
            _viewerCards.removeAt(idx);
            _viewerIndex = _viewerIndex.clamp(0, (_viewerCards.length - 1).clamp(0, 1 << 30));
          });
        }
        return;
      }
      final updated = ResurfaceCard(
        sourcePath: filePath,
        sourceFile: p.basename(filePath),
        front: fb.front,
        back: fb.back,
        decks: parseDeckMetadata(split.frontmatter),
      );
      final idx = _viewerCards.indexWhere((c) => c.sourcePath == filePath);
      if (idx != -1) setState(() => _viewerCards[idx] = updated);
    } catch (_) {}
  }

  void goBack() {
    if (_stack.length <= 1) return;
    setState(() {
      _stack.removeLast();
      if (_stack.last is _CardViewerRoute) _viewerBackRevealed = false;
    });
    widget.onNavigationChanged?.call();
  }

  void resetStack() {
    if (_stack.length <= 1 && !_searchActive) return;
    setState(() {
      _stack
        ..clear()
        ..add(const _DeckListRoute());
      _viewerCards = [];
      _viewerIndex = 0;
      _viewerBackRevealed = false;
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

  void _pushDeck(String deckName, List<ResurfaceCard> cards) {
    setState(() {
      _stack.add(_CardViewerRoute(deckName));
      _viewerCards = List.of(cards)..shuffle();
      _viewerIndex = 0;
      _viewerBackRevealed = false;
    });
    widget.onNavigationChanged?.call();
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

  // ── Card viewer callbacks ─────────────────────────────────────────────────

  void _viewerGoNext() {
    if (_viewerIndex < _viewerCards.length - 1) {
      setState(() {
        _viewerIndex++;
        _viewerBackRevealed = false;
      });
    }
  }

  void _viewerGoPrev() {
    if (_viewerIndex > 0) {
      setState(() {
        _viewerIndex--;
        _viewerBackRevealed = false;
      });
    }
  }

  void _viewerToggleBack() => setState(() => _viewerBackRevealed = !_viewerBackRevealed);

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
    if (note.hasCard) {
      _pushDeck(
        p.basenameWithoutExtension(note.sourceFile),
        [
          ResurfaceCard(
            sourcePath: note.sourcePath,
            sourceFile: note.sourceFile,
            front: note.front!,
            back: note.back!,
            decks: note.decks,
          )
        ],
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
    for (final c in _cards) {
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
      _DeckInfo('All Notes', _cards.length),
      if (defaultCount > 0) _DeckInfo('Default', defaultCount),
      ...namedList,
    ];
  }

  List<ResurfaceCard> _cardsForDeck(String deckName) {
    if (deckName == 'All Notes') return List.of(_cards);
    if (deckName == 'Default') return _cards.where((c) => c.decks.isEmpty).toList();
    return _cards.where((c) => c.decks.contains(deckName)).toList();
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
        child: Text('No notes match', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final note = results[i];
        final title = p.basenameWithoutExtension(note.sourceFile);
        final snippet = _snippetFor(note);
        return ListTile(
          title: Text(title),
          subtitle: snippet.isNotEmpty
              ? Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 13),
                )
              : null,
          trailing: note.hasCard
              ? Icon(Icons.auto_awesome,
                  size: 13,
                  color: Theme.of(ctx)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.6))
              : null,
          onTap: () => _openSearchResult(note),
        );
      },
    );
  }

  Widget _buildDeckList() {
    if (_cards.isEmpty) {
      return const EmptyState(
        icon: Icons.auto_awesome_outlined,
        message: 'No notes found.\nAdd a *** separator to a note.',
      );
    }
    final items = _deckItems;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final deck = items[i];
        return ListTile(
          title: Text(
            deck.name,
            style: i == 0 ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
          trailing: Text(
            '${deck.count}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          onTap: () => _pushDeck(deck.name, _cardsForDeck(deck.name)),
        );
      },
    );
  }

  Widget _buildCardViewer() {
    if (_viewerCards.isEmpty) {
      return const EmptyState(icon: Icons.auto_awesome_outlined, message: 'No cards.');
    }
    return _NoteCardViewerBody(
      cards: _viewerCards,
      currentIndex: _viewerIndex,
      backRevealed: _viewerBackRevealed,
      onNext: _viewerGoNext,
      onPrev: _viewerGoPrev,
      onToggleBack: _viewerToggleBack,
      onNavigateToNote: _handleWikilinkTap,
    );
  }
}

class _DeckInfo {
  final String name;
  final int count;
  const _DeckInfo(this.name, this.count);
}

// ── Card viewer body ──────────────────────────────────────────────────────────
// Stateless: all mutable state lives in ResurfaceScreenState.

class _NoteCardViewerBody extends StatelessWidget {
  final List<ResurfaceCard> cards;
  final int currentIndex;
  final bool backRevealed;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onToggleBack;
  final Future<void> Function(String targetName) onNavigateToNote;

  const _NoteCardViewerBody({
    required this.cards,
    required this.currentIndex,
    required this.backRevealed,
    required this.onNext,
    required this.onPrev,
    required this.onToggleBack,
    required this.onNavigateToNote,
  });

  String _stripExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  MarkdownStyleSheet _mdStyle(BuildContext context, {Color? textColor}) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      h1: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.3, color: color),
      h2: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.35, color: color),
      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: color),
      p: TextStyle(fontSize: 15, height: 1.55, color: color),
      listBullet: TextStyle(fontSize: 15, height: 1.55, color: color),
    );
  }

  void _onTapLink(String text, String? href, String title) {
    if (href == null) return;
    if (href.startsWith('wikilink:')) {
      final target = Uri.decodeComponent(href.substring('wikilink:'.length));
      onNavigateToNote(target);
    } else if (href.startsWith('http:') || href.startsWith('https:')) {
      launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    }
  }

  Widget _mdBody(BuildContext context, String data, {Color? textColor}) => MarkdownBody(
        data: substituteWikilinks(data),
        styleSheet: _mdStyle(context, textColor: textColor),
        onTapLink: _onTapLink,
      );

  @override
  Widget build(BuildContext context) {
    final card = cards[currentIndex];
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onToggleBack,
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: '# ${_stripExtension(card.sourceFile)}',
                    styleSheet: _mdStyle(context),
                  ),
                  const SizedBox(height: 16),
                  _mdBody(context, card.front),
                  const SizedBox(height: 24),
                  if (!backRevealed)
                    _TapToRevealHint()
                  else ...[
                    Divider(thickness: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    _mdBody(context, card.back, textColor: Colors.grey.shade800),
                  ],
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: currentIndex > 0 ? onPrev : null,
                ),
                const Spacer(),
                Text(
                  '${currentIndex + 1} / ${cards.length}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 18),
                  onPressed: currentIndex < cards.length - 1 ? onNext : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TapToRevealHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'tap to reveal',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
