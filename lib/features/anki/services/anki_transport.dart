import '../../../shared/projection/external_projection.dart';

/// Transport abstraction over an Anki backend. `AnkiSyncService` drives any
/// implementation with identical sync semantics; implementations translate
/// these calls into their wire protocol (AnkiDroid ContentProvider via
/// MethodChannel, or Anki desktop via AnkiConnect HTTP) and nothing else.
abstract class AnkiTransport implements ExternalProjectionTransport {
  @override
  ProjectionCapabilities
  get projectionCapabilities => const ProjectionCapabilities({
    'read': null,
    'create': null,
    'update': null,
    'verify': null,
    'retire': 'the current Anki transports expose no guarded delete',
    'local-rollback':
        'vault id patches can be reversed in-process; Anki mutations cannot',
  });

  /// Shown in user-facing sync messages ("Synced 3 problem notes to …").
  String get displayName;

  Future<bool> isAvailable();

  Future<bool> requestPermission();

  /// Creates a note in [deckName] (creating the deck only if absent).
  /// Returns the new note id, or -1 on failure.
  Future<int> addNote(
    String deckName,
    String front,
    String back,
    List<String> tags,
  );

  Future<bool> updateNote(
    int noteId,
    String front,
    String back,
    List<String> tags,
  );

  /// Whether [noteId] exists, or null when the transport could not establish
  /// the fact. Treating an unavailable observation as "missing" would create a
  /// duplicate note.
  Future<bool?> noteExists(int noteId);

  /// Idempotently places the note's card(s) in [deckName], creating the deck if
  /// absent. Returns whether the requested projection was applied. Never
  /// throws: an unavailable deck operation is a reported note failure, not a
  /// reason to silently leave category and deck out of sync.
  Future<bool> moveToDeck(int noteId, String deckName);
}

/// Collection-level fatal condition (e.g. no "Basic" model). Thrown by
/// transports and consumed only by `AnkiSyncService.syncVault`, which records
/// the message and aborts the remaining sync.
class AnkiSyncAbort implements Exception {
  final String message;
  const AnkiSyncAbort(this.message);

  @override
  String toString() => message;
}

/// Per-note failure that carries a message worth surfacing (e.g. AnkiConnect's
/// error string). The sync core records it against the note and continues;
/// message-less failures use the -1/false return values instead.
class AnkiNoteFailure implements Exception {
  final String message;
  const AnkiNoteFailure(this.message);

  @override
  String toString() => message;
}
