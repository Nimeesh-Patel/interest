import '../models/anki_card.dart';
import 'anki_connect_service.dart';
import 'anki_storage_service.dart';

class AnkiSyncResult {
  final int createdInAnki;
  final int updatedInAnki;
  final int createdMarkdown;
  final int updatedMarkdown;
  final int trashed;
  final int skipped;
  final String? error;

  const AnkiSyncResult({
    this.createdInAnki = 0,
    this.updatedInAnki = 0,
    this.createdMarkdown = 0,
    this.updatedMarkdown = 0,
    this.trashed = 0,
    this.skipped = 0,
    this.error,
  });

  String get summary {
    final parts = <String>[];
    if (createdInAnki > 0) parts.add('$createdInAnki created in Anki');
    if (updatedInAnki > 0) parts.add('$updatedInAnki updated in Anki');
    if (createdMarkdown > 0) parts.add('$createdMarkdown imported from Anki');
    if (updatedMarkdown > 0) parts.add('$updatedMarkdown updated from Anki');
    if (trashed > 0) parts.add('$trashed trashed');
    if (skipped > 0) parts.add('$skipped unchanged');
    if (parts.isEmpty) return 'Nothing to sync.';
    return parts.join(' · ');
  }
}

class AnkiSyncService {
  // Treat notes as equal if timestamps differ by less than this.
  static const _toleranceMs = 5000;

  static Future<AnkiSyncResult> sync() async {
    try {
      // 1. Load Markdown cards
      final mdCards = await AnkiStorageService.loadCards();
      final withId = mdCards.where((c) => c.ankiId != null).toList();
      final withoutId = mdCards.where((c) => c.ankiId == null).toList();

      // 2. Fetch all Anki note IDs
      final allAnkiIds = await AnkiConnectService.findNotes('deck:*');
      if (allAnkiIds == null) {
        return const AnkiSyncResult(
          error: 'Could not reach AnkiConnect. Check the URL in Settings.',
        );
      }

      // 3. Fetch note info in batches of 50 to avoid huge payloads
      final ankiNotes = <Map<String, dynamic>>[];
      for (var i = 0; i < allAnkiIds.length; i += 50) {
        final batch = allAnkiIds.skip(i).take(50).toList();
        final info = await AnkiConnectService.notesInfo(batch);
        if (info != null) ankiNotes.addAll(info);
      }

      // Build lookup: ankiId → ankiNote
      final ankiById = <String, Map<String, dynamic>>{};
      for (final note in ankiNotes) {
        final id = (note['noteId'] as num?)?.toInt();
        if (id != null) ankiById[id.toString()] = note;
      }

      // Build set of ankiIds known to Markdown
      final mdAnkiIds = withId.map((c) => c.ankiId!).toSet();

      int createdInAnki = 0;
      int updatedInAnki = 0;
      int createdMarkdown = 0;
      int updatedMarkdown = 0;
      int trashed = 0;
      int skipped = 0;

      // ── MD → Anki: new cards (no anki_id yet) ────────────────────────────
      for (final card in withoutId) {
        try {
          final noteId = await AnkiConnectService.addNote(card);
          if (noteId != null) {
            await AnkiStorageService.updateAnkiId(card.filePath, noteId.toString());
            createdInAnki++;
          }
        } catch (_) {}
      }

      // ── MD ↔ Anki: reconcile existing cards ──────────────────────────────
      for (final card in withId) {
        try {
          final ankiId = card.ankiId!;
          final ankiNote = ankiById[ankiId];

          if (ankiNote == null) {
            // Card deleted from Anki → trash the Markdown file
            await AnkiStorageService.trashCard(card.filePath);
            trashed++;
            continue;
          }

          final mdMs = card.updatedAt.millisecondsSinceEpoch;
          final ankiModUnix = (ankiNote['mod'] as num?)?.toInt() ?? 0;
          final ankiMs = ankiModUnix * 1000;
          final diff = mdMs - ankiMs;

          if (diff.abs() <= _toleranceMs) {
            skipped++;
          } else if (diff > 0) {
            // Markdown is newer → push to Anki
            final currentDeck = _deckName(ankiNote);
            if (currentDeck != card.deck) {
              await AnkiConnectService.changeDeck(ankiId, card.deck);
            }
            await AnkiConnectService.updateNote(card);
            updatedInAnki++;
          } else {
            // Anki is newer → update Markdown
            final updatedCard = _applyAnkiNote(card, ankiNote);
            await AnkiStorageService.saveCard(updatedCard);
            updatedMarkdown++;
          }
        } catch (_) {}
      }

      // ── Anki → MD: notes not present in Markdown ─────────────────────────
      for (final ankiNote in ankiNotes) {
        try {
          final id = (ankiNote['noteId'] as num?)?.toInt();
          if (id == null) continue;
          if (mdAnkiIds.contains(id.toString())) continue;
          await AnkiStorageService.createFromAnki(ankiNote);
          createdMarkdown++;
        } catch (_) {}
      }

      return AnkiSyncResult(
        createdInAnki: createdInAnki,
        updatedInAnki: updatedInAnki,
        createdMarkdown: createdMarkdown,
        updatedMarkdown: updatedMarkdown,
        trashed: trashed,
        skipped: skipped,
      );
    } catch (e) {
      return AnkiSyncResult(error: e.toString());
    }
  }

  static AnkiCard _applyAnkiNote(AnkiCard existing, Map<String, dynamic> ankiNote) {
    final fields = ankiNote['fields'] as Map?;
    final rawTags = ankiNote['tags'];
    final tags = rawTags is List ? rawTags.map((t) => t.toString()).toList() : existing.tags;
    final modUnix = (ankiNote['mod'] as num?)?.toInt() ?? 0;
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(modUnix * 1000, isUtc: true);
    final modelName = ankiNote['modelName']?.toString() ?? '';
    final noteType = modelName == 'Cloze' ? AnkiNoteType.cloze : AnkiNoteType.basic;
    final deck = _deckName(ankiNote);

    if (noteType == AnkiNoteType.cloze) {
      return existing.copyWith(
        noteType: noteType,
        deck: deck,
        tags: tags,
        updatedAt: updatedAt,
        text: _fieldValue(fields, 'Text'),
      );
    }
    return existing.copyWith(
      noteType: noteType,
      deck: deck,
      tags: tags,
      updatedAt: updatedAt,
      front: _fieldValue(fields, 'Front'),
      back: _fieldValue(fields, 'Back'),
    );
  }

  static String _fieldValue(Map? fields, String key) {
    if (fields == null) return '';
    final field = fields[key];
    if (field is Map) return (field['value'] ?? '').toString();
    return field?.toString() ?? '';
  }

  static String _deckName(Map<String, dynamic> note) =>
      note['deckName']?.toString() ?? 'Default';
}
