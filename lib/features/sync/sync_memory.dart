import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../anki/services/anki_sync_service.dart';

/// What the last completed sync did, kept on this device so the home screen
/// can say when the cards were last brought up to date.
class LastSync {
  final DateTime at;
  final int added;
  final int updated;
  final int removed;
  final List<String> changed;

  const LastSync({
    required this.at,
    required this.added,
    required this.updated,
    required this.removed,
    required this.changed,
  });

  factory LastSync.of(AnkiSyncResult result) => LastSync(
    at: DateTime.now(),
    added: result.added,
    updated: result.updated,
    removed: result.retired + result.duplicatesRetired,
    changed: result.changed.take(50).toList(),
  );

  Map<String, Object> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'added': added,
    'updated': updated,
    'removed': removed,
    'changed': changed,
  };

  static LastSync? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return LastSync(
      at: DateTime.fromMillisecondsSinceEpoch(raw['at'] as int),
      added: raw['added'] as int,
      updated: raw['updated'] as int,
      removed: raw['removed'] as int,
      changed: (raw['changed'] as List).cast<String>(),
    );
  }
}

/// Device-local memory: the last sync, and the cards Nimeesh chose to keep
/// although no note links them. Keeping is a decision, so a kept card is not
/// asked about again until he clears the list in Settings.
class SyncMemory {
  static const _lastKey = 'sync.last';
  static const _keptKey = 'sync.kept_cards';

  static Future<LastSync?> lastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastKey);
    if (raw == null) return null;
    try {
      return LastSync.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> recordSync(AnkiSyncResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastKey, jsonEncode(LastSync.of(result).toJson()));
  }

  static Future<Set<int>> keptCards() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keptKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  static Future<void> keep(int ankiNoteId) async {
    final kept =
        await keptCards()
          ..add(ankiNoteId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keptKey, [for (final id in kept) '$id']);
  }

  static Future<void> clearKept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keptKey);
  }
}
