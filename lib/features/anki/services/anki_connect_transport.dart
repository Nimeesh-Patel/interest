import 'dart:convert';

import 'package:http/http.dart' as http;

import 'anki_transport.dart';

/// Anki desktop transport: HTTP to the AnkiConnect add-on (API version 6),
/// default `http://127.0.0.1:8765`. Pure Dart — no platform channel — so it
/// runs from any build that can reach the URL; on a phone the localhost call
/// simply fails closed unless a LAN URL is configured in integrations.md.
class AnkiConnectTransport extends AnkiTransport {
  static const defaultUrl = 'http://127.0.0.1:8765';
  static const _apiVersion = 6;
  static const _timeout = Duration(seconds: 10);

  final Uri _endpoint;
  final http.Client _client;

  /// One model check per transport instance; a fresh instance is created per
  /// sync, so a model added mid-session is picked up on the next sync.
  bool _basicModelVerified = false;

  AnkiConnectTransport({String? url, http.Client? client})
    : _endpoint = Uri.parse(
        (url == null || url.trim().isEmpty) ? defaultUrl : url.trim(),
      ),
      _client = client ?? http.Client();

  @override
  String get displayName => 'Anki desktop';

  /// POSTs one AnkiConnect action. Returns the `result` value; throws
  /// [AnkiNoteFailure] carrying AnkiConnect's `error` string when present.
  Future<Object?> _invoke(String action, [Map<String, Object?>? params]) async {
    final response = await _client
        .post(
          _endpoint,
          // AnkiConnect's server closes the socket after every response
          // without advertising it; a reused keep-alive connection makes
          // every second request fail. Forcing close disables reuse.
          headers: {'Content-Type': 'application/json', 'Connection': 'close'},
          body: jsonEncode({
            'action': action,
            'version': _apiVersion,
            if (params != null) 'params': params,
          }),
        )
        .timeout(_timeout);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final error = decoded['error'];
    if (error != null) throw AnkiNoteFailure('$error');
    return decoded['result'];
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _invoke('version') is int;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final result = await _invoke('requestPermission');
      return result is Map && result['permission'] == 'granted';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> addNote(
    String deckName,
    String front,
    String back,
    List<String> tags,
  ) async {
    await _ensureBasicModel();
    try {
      // Idempotent: returns the existing deck's id, never duplicates
      // (verified live against AnkiConnect 6). addNote itself errors on a
      // missing deck, so this must come first.
      await _invoke('createDeck', {'deck': deckName});
      final result = await _invoke('addNote', {
        'note': {
          'deckName': deckName,
          'modelName': 'Basic',
          'fields': {'Front': front, 'Back': back},
          'tags': tags,
          'options': {'allowDuplicate': true},
        },
      });
      return result is int ? result : -1;
    } on AnkiNoteFailure {
      rethrow;
    } catch (_) {
      return -1;
    }
  }

  /// Same requirement as the AnkiDroid path's BASIC_MODEL_NOT_FOUND check:
  /// both transports create notes only on the model literally named "Basic"
  /// (fields Front/Back), so a note added by one updates cleanly via the other.
  Future<void> _ensureBasicModel() async {
    if (_basicModelVerified) return;
    List<Object?> names;
    try {
      names = (await _invoke('modelNames') as List?) ?? const [];
    } catch (_) {
      throw const AnkiSyncAbort('Could not list note types from Anki');
    }
    if (!names.contains('Basic')) {
      throw const AnkiSyncAbort(
        'Basic note type not found in Anki — it may have been renamed or deleted.',
      );
    }
    _basicModelVerified = true;
  }

  @override
  Future<bool> updateNote(
    int noteId,
    String front,
    String back,
    List<String> tags,
  ) async {
    try {
      await _invoke('updateNoteFields', {
        'note': {
          'id': noteId,
          'fields': {'Front': front, 'Back': back},
        },
      });
      await _invoke('updateNoteTags', {'note': noteId, 'tags': tags});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> noteExists(int noteId) async {
    try {
      final result = await _invoke('notesInfo', {
        'notes': [noteId],
      });
      if (result is! List || result.isEmpty) return false;
      // Missing notes come back as empty objects, not an error.
      final info = result.first;
      return info is Map && info.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> currentDeck(int noteId) async {
    try {
      final cards = await _cardIds(noteId);
      if (cards.isEmpty) return null;
      // getDecks maps deck name → the card ids it contains; a note's cards
      // normally share one deck, so the first key is that deck.
      final decks = await _invoke('getDecks', {'cards': cards});
      if (decks is Map && decks.isNotEmpty) return decks.keys.first.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> moveToDeck(int noteId, String deckName) async {
    try {
      final cards = await _cardIds(noteId);
      if (cards.isEmpty) return;
      // changeDeck errors on a missing deck; createDeck is idempotent.
      await _invoke('createDeck', {'deck': deckName});
      await _invoke('changeDeck', {'cards': cards, 'deck': deckName});
    } catch (_) {}
  }

  /// The card ids of [noteId] via `notesInfo`, or empty on any failure.
  Future<List<int>> _cardIds(int noteId) async {
    final result = await _invoke('notesInfo', {
      'notes': [noteId],
    });
    if (result is! List || result.isEmpty) return const [];
    final info = result.first;
    if (info is! Map) return const [];
    final cards = info['cards'];
    if (cards is! List) return const [];
    return cards.whereType<int>().toList();
  }
}
