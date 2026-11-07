import 'dart:convert';
import 'dart:io';

import '../../../core/vault_paths.dart';

/// What one vault file looked like when it was last read: its modification
/// time and size (the cheap change signal), the aliases it declares (so link
/// targets resolve without reading every note) and its `anki_note_id` (so
/// identities stay checkable vault-wide).
class NoteFacts {
  final int modified;
  final int size;
  final List<String> aliases;
  final String? ankiNoteId;

  const NoteFacts({
    required this.modified,
    required this.size,
    this.aliases = const [],
    this.ankiNoteId,
  });


  Map<String, Object> toJson() => {
    'm': modified,
    's': size,
    if (aliases.isNotEmpty) 'a': aliases,
    if (ankiNoteId != null) 'i': ankiNoteId!,
  };

  static NoteFacts? fromJson(Object? raw) {
    if (raw is! Map || raw['m'] is! int || raw['s'] is! int) return null;
    return NoteFacts(
      modified: raw['m'] as int,
      size: raw['s'] as int,
      aliases: raw['a'] is List ? (raw['a'] as List).cast<String>() : const [],
      ankiNoteId: raw['i'] as String?,
    );
  }
}

/// The vault as Anki last received it, kept in the device-local `.interest/`
/// folder: one [NoteFacts] per current note (vault-relative path, `/`
/// separators), every note, not only Problem Notes.
///
/// It answers "what changed since the last sync?" by modification time and
/// size, so a sync after a few edits (by Nimeesh on any device, or by
/// Perspirator in bulk) reads only those files. It is written only after a
/// clean sync and only with facts observed *before* reading, so an edit that
/// lands during a sync still differs next time. Losing it costs one
/// whole-vault sync, never correctness.
class SyncManifest {
  final Map<String, NoteFacts> notes;

  /// When the run that wrote this began (ms since epoch).
  final int startedAt;

  /// Timestamps are coarse: an edit in the same second as the moment a file
  /// was looked at, keeping its size, would look unchanged. So a file
  /// modified within this margin of the run's start is never trusted as
  /// settled; it is read again next time.
  static const settleMargin = 2000;

  const SyncManifest(this.notes, {required this.startedAt});

  /// Whether [stat] shows the file exactly as recorded, and settled.
  bool unchanged(String key, FileStat stat) {
    final before = notes[key];
    return before != null &&
        stat.modified.millisecondsSinceEpoch == before.modified &&
        stat.size == before.size &&
        before.modified < startedAt - settleMargin;
  }

  static Future<SyncManifest?> load(String vaultPath) async {
    try {
      final raw = jsonDecode(
        await File(VaultPaths.syncManifest(vaultPath)).readAsString(),
      );
      if (raw is! Map || raw['notes'] is! Map || raw['startedAt'] is! int) {
        return null;
      }
      final notes = <String, NoteFacts>{};
      for (final entry in (raw['notes'] as Map).entries) {
        final facts = NoteFacts.fromJson(entry.value);
        if (entry.key is! String || facts == null) return null;
        notes[entry.key as String] = facts;
      }
      return SyncManifest(notes, startedAt: raw['startedAt'] as int);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String vaultPath) async {
    try {
      final file = File(VaultPaths.syncManifest(vaultPath));
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'startedAt': startedAt,
          'notes': {
            for (final entry in notes.entries) entry.key: entry.value.toJson(),
          },
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {
      // An unwritten manifest only makes the next sync read the whole vault.
    }
  }

  static Future<void> forget(String vaultPath) async {
    try {
      await File(VaultPaths.syncManifest(vaultPath)).delete();
    } catch (_) {}
  }

  Map<String, List<String>> get aliases => {
    for (final entry in notes.entries) entry.key: entry.value.aliases,
  };
}
