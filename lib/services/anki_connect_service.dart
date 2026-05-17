import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anki_card.dart';

class AnkiConnectService {
  static const String _prefKey = 'anki_connect_url';
  static const String _defaultUrl = 'http://localhost:8765';
  static const Duration _timeout = Duration(seconds: 15);

  static Future<String> getUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKey) ?? _defaultUrl;
    } catch (_) {
      return _defaultUrl;
    }
  }

  static Future<void> setUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, url.trim());
    } catch (_) {}
  }

  static Future<dynamic> _invoke(String action, Map<String, dynamic> params) async {
    try {
      final url = await getUrl();
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'action': action, 'version': 6, 'params': params}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['error'] != null) return null;
      return body['result'];
    } catch (_) {
      return null;
    }
  }

  static Future<bool> testConnection() async {
    try {
      final result = await _invoke('version', {});
      return result != null;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>?> deckNames() async {
    try {
      final result = await _invoke('deckNames', {});
      if (result == null) return null;
      return (result as List).map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<int?> addNote(AnkiCard card) async {
    try {
      final fields = _cardToFields(card);
      if (fields == null) return null;
      final result = await _invoke('addNote', {
        'note': {
          'deckName': card.deck,
          'modelName': _modelName(card.noteType),
          'fields': fields,
          'tags': card.tags,
        }
      });
      if (result == null) return null;
      return (result as num).toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> updateNote(AnkiCard card) async {
    try {
      if (card.ankiId == null) return false;
      final fields = _cardToFields(card);
      if (fields == null) return false;
      final noteId = int.tryParse(card.ankiId!);
      if (noteId == null) return false;
      await _invoke('updateNote', {
        'note': {
          'id': noteId,
          'fields': fields,
          'tags': card.tags,
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> changeDeck(String ankiId, String deck) async {
    try {
      final noteId = int.tryParse(ankiId);
      if (noteId == null) return false;
      // Get card IDs from note ID
      final infos = await notesInfo([noteId]);
      if (infos == null || infos.isEmpty) return false;
      final cards = infos.first['cards'];
      if (cards == null) return false;
      final cardIds = (cards as List).map((e) => (e as num).toInt()).toList();
      await _invoke('changeDeck', {'cards': cardIds, 'deck': deck});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>?> notesInfo(List<int> noteIds) async {
    try {
      if (noteIds.isEmpty) return [];
      final result = await _invoke('notesInfo', {'notes': noteIds});
      if (result == null) return null;
      return (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> findNotes(String query) async {
    try {
      final result = await _invoke('findNotes', {'query': query});
      if (result == null) return null;
      return (result as List).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return null;
    }
  }

  static String _modelName(AnkiNoteType type) =>
      type == AnkiNoteType.basic ? 'Basic' : 'Cloze';

  static Map<String, String>? _cardToFields(AnkiCard card) {
    if (card.noteType == AnkiNoteType.basic) {
      return {'Front': card.front, 'Back': card.back};
    } else if (card.noteType == AnkiNoteType.cloze) {
      return {'Text': card.text};
    }
    return null;
  }
}
