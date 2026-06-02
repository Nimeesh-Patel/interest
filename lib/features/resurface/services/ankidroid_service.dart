import 'package:flutter/services.dart';

import '../../../shared/markdown/md_io.dart';
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

  static Future<AnkiSyncResult> syncVault(
      List<ResurfaceNote> problemNotes) async {
    int added = 0;
    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    for (final note in problemNotes) {
      try {
        final front = note.front ?? '';
        final back = note.back ?? '';
        final deckName = note.category ?? 'Problem Notes';
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
              updated++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: update failed');
            }
          } else {
            // Note was deleted from AnkiDroid — re-add and write new ID back.
            final newId = await _addNote(deckName, front, back, tags);
            if (newId > 0) {
              await patchFrontmatterField(
                  note.sourcePath, 'anki_note_id', '$newId');
              added++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: add failed after missing note');
            }
          }
        } else {
          final newId = await _addNote(deckName, front, back, tags);
          if (newId > 0) {
            await patchFrontmatterField(
                note.sourcePath, 'anki_note_id', '$newId');
            added++;
          } else {
            failed++;
            errors.add('${note.sourceFile}: add failed');
          }
        }
      } catch (e) {
        failed++;
        errors.add('${note.sourceFile}: $e');
      }
    }

    return AnkiSyncResult(
        added: added, updated: updated, failed: failed, errors: errors);
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
}
