import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_utils.dart';
import '../../entities/services/markdown_storage_service.dart';
import '../models/resurface_note.dart';

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

class AnkiDroidService {
  static const _channel = MethodChannel('com.nimeesh.interest/ankidroid');

  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAnkiDroidAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// AnkiDroid handles `anki://x-callback-url/browser?search=...` (in-app
  /// Card Browser deep link) from 2.16 onward. Older versions have no handler
  /// for the scheme, so card links must stay on interest://.
  static Future<bool> _supportsBrowserLinks() async {
    try {
      final version =
          await _channel.invokeMethod<String>('getAnkiDroidVersion');
      if (version == null) return false;
      final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(version);
      if (m == null) return false;
      final major = int.parse(m.group(1)!);
      final minor = int.parse(m.group(2)!);
      return major > 2 || (major == 2 && minor >= 16);
    } catch (_) {
      return false;
    }
  }

  static Future<AnkiSyncResult> syncVault(
      List<ResurfaceNote> problemNotes, String vaultPath) async {
    int added = 0;
    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    // In-AnkiDroid traversal: a wikilink whose target is a synced problem
    // note renders as an anki:// Card Browser link (nid:<id>); anything else
    // falls back to the interest:// deep link. The map starts from
    // frontmatter and grows as this sync assigns IDs, so notes later in the
    // loop resolve earlier additions immediately.
    final browserLinks = await _supportsBrowserLinks();
    final ankiIdByKey = <String, int>{};
    if (browserLinks) {
      for (final note in problemNotes) {
        final id = int.tryParse(note.ankiNoteId ?? '');
        if (id != null) ankiIdByKey[noteKey(note.sourcePath)] = id;
      }
    }
    final idByPath = <String, int>{};
    final newlyAssigned = <String>{};
    void registerNewId(ResurfaceNote note, int id) {
      idByPath[note.sourcePath] = id;
      if (browserLinks) {
        final key = noteKey(note.sourcePath);
        ankiIdByKey[key] = id;
        newlyAssigned.add(key);
      }
    }

    for (final note in problemNotes) {
      try {
        final (front, back) = _renderCard(note, vaultPath, ankiIdByKey);
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
          final exists = await _noteExists(noteIdLong);
          if (exists) {
            final ok = await _updateNote(noteIdLong, front, back, tags);
            if (ok) {
              idByPath[note.sourcePath] = noteIdLong;
              updated++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: update failed');
            }
          } else {
            // Note was deleted from AnkiDroid — re-add and write new ID back.
            final newId = await _addNote(deckName, front, back, tags);
            if (newId > 0) {
              await MarkdownStorageService.patchAnkiNoteId(note.sourcePath, newId);
              registerNewId(note, newId);
              added++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: add failed after missing note');
            }
          }
        } else {
          final newId = await _addNote(deckName, front, back, tags);
          if (newId > 0) {
            await MarkdownStorageService.patchAnkiNoteId(note.sourcePath, newId);
            registerNewId(note, newId);
            added++;
          } else {
            failed++;
            errors.add('${note.sourceFile}: add failed');
          }
        }
      } on PlatformException catch (e) {
        if (e.code == 'BASIC_MODEL_NOT_FOUND') {
          errors.add(e.message ?? 'Basic model not found in AnkiDroid');
          break;
        }
        failed++;
        errors.add('${note.sourceFile}: ${e.message}');
      } catch (e) {
        failed++;
        errors.add('${note.sourceFile}: $e');
      }
    }

    // Upgrade pass: a note rendered before a link target's ID was assigned
    // (first add, or re-add after deletion in AnkiDroid) carries the
    // interest:// fallback or a stale nid. Re-render those against the final
    // ID map. A failure here is ignored — the fallback link still works.
    if (browserLinks && newlyAssigned.isNotEmpty) {
      for (final note in problemNotes) {
        final id = idByPath[note.sourcePath];
        if (id == null) continue;
        final targets =
            extractWikilinks('${note.front ?? ''}\n${note.back ?? ''}')
                .map((t) => t.toLowerCase())
                .toSet();
        if (!targets.any(newlyAssigned.contains)) continue;
        try {
          final (front, back) = _renderCard(note, vaultPath, ankiIdByKey);
          await _updateNote(id, front, back, note.tags);
        } catch (_) {}
      }
    }

    return AnkiSyncResult(
        added: added, updated: updated, failed: failed, errors: errors);
  }

  /// Renders a problem note's (front, back) card HTML. The front is
  /// prepended with the right-aligned Obsidian source link.
  static (String, String) _renderCard(
      ResurfaceNote note, String vaultPath, Map<String, int> ankiIdByKey) {
    final noteDisplayName = p.basenameWithoutExtension(note.sourcePath);
    final obsUri = obsidianUri(vaultPath, note.sourcePath);
    final obsLinkHtml =
        '<div style="text-align:right;font-size:0.75em;margin-bottom:6px;opacity:0.6;">'
        '<a href="$obsUri">$noteDisplayName ↗</a>'
        '</div>';
    final front =
        obsLinkHtml + _markdownToAnkiHtml(note.front ?? '', ankiIdByKey);
    final back = _markdownToAnkiHtml(note.back ?? '', ankiIdByKey);
    return (front, back);
  }

  static Future<int> _addNote(
      String deckName, String front, String back, List<String> tags) async {
    try {
      final result = await _channel.invokeMethod<Object>('addNote', {
        'deckName': deckName,
        'front': front,
        'back': back,
        'tags': tags,
      });
      // Channel returns Long on Android which may arrive as int or String.
      if (result is int) return result;
      if (result is String) return int.tryParse(result) ?? -1;
      return -1;
    } on PlatformException {
      rethrow;
    } catch (_) {
      return -1;
    }
  }

  static Future<bool> _updateNote(
      int noteId, String front, String back, List<String> tags) async {
    try {
      return await _channel.invokeMethod<bool>('updateNote', {
            'noteId': noteId,
            'front': front,
            'back': back,
            'tags': tags,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _noteExists(int noteId) async {
    try {
      return await _channel.invokeMethod<bool>('noteExists', {
            'noteId': noteId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// A wikilink whose target is a synced problem note in [ankiIdByKey]
  /// becomes an in-AnkiDroid Card Browser deep link (back from the browser
  /// returns to the review session); any other wikilink becomes the
  /// interest:// deep link handled by this app.
  static String _markdownToAnkiHtml(String text, Map<String, int> ankiIdByKey) =>
      md.markdownToHtml(
        rewriteWikilinksToHtml(text, (target, display) {
          final id = ankiIdByKey[target.toLowerCase()];
          if (id != null) {
            final query = Uri.encodeQueryComponent('nid:$id');
            return '<a href="anki://x-callback-url/browser?search=$query">$display</a>';
          }
          final encoded = Uri.encodeComponent(target);
          return '<a href="interest://note/$encoded">$display</a>';
        }),
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
}
