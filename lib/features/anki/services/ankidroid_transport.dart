import 'package:flutter/services.dart';

import 'anki_transport.dart';

/// AnkiDroid transport: MethodChannel to AnkiBridge.kt (registered on
/// MainActivity), which talks to AnkiDroid's ContentProvider via AddContentApi.
/// Android only — on other platforms every call fails closed (isAvailable
/// returns false).
class AnkiDroidTransport extends AnkiTransport {
  static const _channel = MethodChannel('com.nimeesh.interest/ankidroid');

  @override
  String get displayName => 'AnkiDroid';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAnkiDroidAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
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
    } on PlatformException catch (e) {
      if (e.code == 'BASIC_MODEL_NOT_FOUND') {
        throw AnkiSyncAbort(e.message ?? 'Basic model not found in AnkiDroid');
      }
      throw AnkiNoteFailure(e.message ?? e.code);
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<bool> updateNote(
    int noteId,
    String front,
    String back,
    List<String> tags,
  ) async {
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

  @override
  Future<bool> noteExists(int noteId) async {
    try {
      return await _channel.invokeMethod<bool>('noteExists', {
            'noteId': noteId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> currentDeck(int noteId) async {
    try {
      return await _channel.invokeMethod<String>('getCardDeck', {
        'noteId': noteId,
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> moveToDeck(int noteId, String deckName) async {
    try {
      await _channel.invokeMethod<bool>('moveNoteToDeck', {
        'noteId': noteId,
        'deckName': deckName,
      });
    } catch (_) {}
  }
}
