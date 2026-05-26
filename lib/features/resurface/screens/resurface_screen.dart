import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/resurface_card.dart';
import '../services/resurface_service.dart';

// ── Deck list (no Scaffold — HomeScreen provides AppBar) ─────────────────────

class ResurfaceScreen extends StatefulWidget {
  const ResurfaceScreen({super.key});

  @override
  State<ResurfaceScreen> createState() => ResurfaceScreenState();
}

class ResurfaceScreenState extends State<ResurfaceScreen> {
  List<ResurfaceCard> _cards = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
    final config = await IntegrationsConfigService.load(vaultPath);
    final cards = await ResurfaceService.scan(
      vaultPath,
      excludedFolders: config.resurfaceExcludedFolders,
    );
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(icon: Icons.error_outline, message: _error!);
    }
    if (_cards.isEmpty) {
      return const EmptyState(
        icon: Icons.auto_awesome_outlined,
        message: 'No notes found.\nAdd a *** separator to a note.',
      );
    }

    final items = _deckItems;
    return SafeArea(
      top: false,
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final deck = items[i];
          return ListTile(
            title: Text(
              deck.name,
              style: i == 0
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
            trailing: Text(
              '${deck.count}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            onTap: () {
              Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => NoteCardViewerScreen(
                    cards: _cardsForDeck(deck.name),
                    deckName: deck.name,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DeckInfo {
  final String name;
  final int count;
  const _DeckInfo(this.name, this.count);
}

// ── Card viewer (pushed route with own Scaffold) ──────────────────────────────

class NoteCardViewerScreen extends StatefulWidget {
  final List<ResurfaceCard> cards;
  final String deckName;

  const NoteCardViewerScreen({
    super.key,
    required this.cards,
    required this.deckName,
  });

  @override
  State<NoteCardViewerScreen> createState() => _NoteCardViewerScreenState();
}

class _NoteCardViewerScreenState extends State<NoteCardViewerScreen> {
  late List<ResurfaceCard> _cards;
  int _currentIndex = 0;
  bool _backRevealed = false;

  @override
  void initState() {
    super.initState();
    _cards = List.of(widget.cards)..shuffle();
  }

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

  void _goNext() {
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _backRevealed = false;
      });
    }
  }

  void _goPrev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _backRevealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deckName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${_cards.length}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildCard(_cards[_currentIndex])),
            _buildNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(ResurfaceCard card) {
    return GestureDetector(
      onTap: () => setState(() => _backRevealed = !_backRevealed),
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          _goNext();
        } else if (v > 200) {
          _goPrev();
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
            MarkdownBody(
              data: card.front,
              styleSheet: _mdStyle(context),
            ),
            const SizedBox(height: 24),
            if (!_backRevealed)
              _TapToRevealHint()
            else ...[
              Divider(thickness: 1, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              MarkdownBody(
                data: card.back,
                styleSheet: _mdStyle(context, textColor: Colors.grey.shade800),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: _currentIndex > 0 ? _goPrev : null,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 18),
              onPressed: _currentIndex < _cards.length - 1 ? _goNext : null,
            ),
          ],
        ),
      ),
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
