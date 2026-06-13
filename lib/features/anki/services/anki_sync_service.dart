import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/anki_problem_note.dart';
import 'anki_transport.dart';

class AnkiSyncResult {
  final int added;
  final int updated;
  final int failed;
  final List<String> errors;

  const AnkiSyncResult({
    required this.added,
    required this.updated,
    required this.failed,
    required this.errors,
  });
}

/// Transport-agnostic sync core: problem notes → Anki cards, one-way.
/// Owns everything both transports must agree on — front/back rendering,
/// `category:`→deck mapping (including deck moves on a category change), the
/// obsidian:// wikilink rewrite, and the `anki_note_id` round-trip — so the
/// same note yields the same card whichever transport carries it.
class AnkiSyncService {
  static Future<AnkiSyncResult> syncVault(AnkiTransport transport,
      List<AnkiProblemNote> problemNotes, String vaultPath) async {
    int added = 0;
    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    for (final note in problemNotes) {
      try {
        final (front, back) = _renderCard(note, vaultPath);
        final deckName = note.category ?? 'Default';
        final tags = note.tags;
        final ankiNoteId = note.ankiNoteId;

        if (ankiNoteId != null) {
          final noteIdLong = int.tryParse(ankiNoteId);
          if (noteIdLong == null) {
            failed++;
            errors.add('${note.sourceFile}: invalid anki_note_id "$ankiNoteId"');
            continue;
          }
          final exists = await transport.noteExists(noteIdLong);
          if (exists) {
            final ok =
                await transport.updateNote(noteIdLong, front, back, tags);
            if (ok) {
              // The card's deck tracks `category:`; if the user changed it
              // since the last sync, move the card. Transports that can't
              // report or move decks no-op (currentDeck == null skips it).
              final deck = await transport.currentDeck(noteIdLong);
              if (deck != null && deck != deckName) {
                await transport.moveToDeck(noteIdLong, deckName);
              }
              updated++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: update failed');
            }
          } else {
            // Note was deleted from Anki — re-add and write new ID back.
            final newId = await transport.addNote(deckName, front, back, tags);
            if (newId > 0) {
              await _patchAnkiNoteId(note.sourcePath, newId);
              added++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: add failed after missing note');
            }
          }
        } else {
          final newId = await transport.addNote(deckName, front, back, tags);
          if (newId > 0) {
            await _patchAnkiNoteId(note.sourcePath, newId);
            added++;
          } else {
            failed++;
            errors.add('${note.sourceFile}: add failed');
          }
        }
      } on AnkiSyncAbort catch (e) {
        errors.add(e.message);
        break;
      } on AnkiNoteFailure catch (e) {
        failed++;
        errors.add('${note.sourceFile}: ${e.message}');
      } catch (e) {
        failed++;
        errors.add('${note.sourceFile}: $e');
      }
    }

    return AnkiSyncResult(
        added: added, updated: updated, failed: failed, errors: errors);
  }

  /// Renders a problem note's (front, back) card HTML. The front is
  /// prepended with the right-aligned Obsidian source link.
  static (String, String) _renderCard(AnkiProblemNote note, String vaultPath) {
    final noteDisplayName = p.basenameWithoutExtension(note.sourcePath);
    final obsUri = obsidianUri(vaultPath, note.sourcePath);
    final obsLinkHtml =
        '<div style="text-align:right;font-size:0.75em;margin-bottom:6px;opacity:0.6;">'
        '<a href="$obsUri">$noteDisplayName ↗</a>'
        '</div>';
    final front = obsLinkHtml + _markdownToAnkiHtml(note.front ?? '', vaultPath);
    final back = _markdownToAnkiHtml(note.back ?? '', vaultPath);
    return (front, back);
  }

  /// Converts card Markdown to HTML. Wikilinks become `obsidian://open` links
  /// to the target note (note traversal lives in Obsidian, where the *** note
  /// renderer plugin shows the card with tap-to-reveal). Single newlines —
  /// collapsed to a space by standard Markdown — are promoted to hard breaks
  /// so the note's visual line structure survives into the card.
  static String _markdownToAnkiHtml(String text, String vaultPath) {
    // Normalize line endings first so the lone-newline detection below is not
    // defeated by CRLF (where a paragraph break is "\r\n\r\n").
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rewritten = rewriteWikilinksToHtml(normalized, (target, display) {
      final href = obsidianUriForName(vaultPath, target);
      return '<a href="$href">$display</a>';
    });
    final hardWrapped = rewritten.replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), '  \n');
    return md.markdownToHtml(hardWrapped,
        extensionSet: md.ExtensionSet.gitHubWeb);
  }

  /// The sync's ONLY vault write: surgically patches the `anki_note_id`
  /// frontmatter key via [patchFrontmatterField], which preserves the note body
  /// byte-for-byte. No sync code opens or rewrites a note body. Never throws.
  static Future<void> _patchAnkiNoteId(String filePath, int noteId) =>
      patchFrontmatterField(filePath, 'anki_note_id', '$noteId');
}
