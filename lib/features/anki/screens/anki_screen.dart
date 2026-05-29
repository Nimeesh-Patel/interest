import 'package:flutter/material.dart';

import '../../../shared/constants/app_spacing.dart';
import '../models/anki_card.dart';
import '../services/anki_storage_service.dart';
import '../services/anki_sync_service.dart';
import '../../../shared/constants/app_theme.dart';
import 'anki_card_editor_screen.dart';

class AnkiScreen extends StatefulWidget {
  const AnkiScreen({super.key});

  @override
  State<AnkiScreen> createState() => _AnkiScreenState();
}

class _AnkiScreenState extends State<AnkiScreen> {
  List<AnkiCard> _cards = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await AnkiStorageService.loadCards();
    if (mounted) {
      setState(() {
        _cards = cards;
        _loading = false;
      });
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final result = await AnkiSyncService.sync();
    if (!mounted) return;
    setState(() => _syncing = false);
    if (result.error != null) {
      _showSnack(result.error!, isError: true);
    } else {
      _showSnack(result.summary);
    }
    await _load();
  }

  Future<void> _openEditor({AnkiCard? card}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnkiCardEditorScreen(card: card),
      ),
    );
    await _load();
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.destructive : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anki Cards'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _sync,
              tooltip: 'Sync with Anki',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? _buildEmpty()
              : _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'New card',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined, size: 56, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text(
              'No Anki cards yet.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              'Tap + to create a card, or tap Sync to import from Anki.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: kFabListBottomPad),
      itemCount: _cards.length,
      itemBuilder: (context, i) => _buildCard(_cards[i]),
    );
  }

  Widget _buildCard(AnkiCard card) {
    final typeLabel = card.noteType == AnkiNoteType.cloze ? 'Cloze' : 'Basic';
    final typeColor =
        card.noteType == AnkiNoteType.cloze ? Colors.purple : Colors.blue;
    final synced = card.ankiId != null;

    return ListTile(
      onTap: () => _openEditor(card: card),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: typeColor.withValues(alpha: 0.4)),
        ),
        child: Text(
          typeLabel,
          style: TextStyle(
            color: typeColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        _firstLine(card.displayTitle),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          const Icon(Icons.layers_outlined, size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              card.deck,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (card.tags.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                card.tags.join(', '),
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: synced
          ? null
          : Tooltip(
              message: 'Not yet synced to Anki',
              child: Icon(Icons.cloud_off_outlined,
                  size: 16, color: Colors.orange[400]),
            ),
    );
  }

  String _firstLine(String text) {
    final line = text.split('\n').first.trim();
    return line.isEmpty ? '(empty)' : line;
  }
}
