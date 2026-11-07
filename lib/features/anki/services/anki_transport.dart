import '../../../shared/projection/external_projection.dart';
export '../../../shared/projection/external_projection.dart'
    show ProjectionCapabilities;

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
    'retire': 'this transport does not implement guarded deletion',
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

  /// One complete observation of every "Basic" note in the collection. The
  /// sync core compares the vault against it, so a note absent from the
  /// snapshot is read as absent from Anki: an incomplete or unavailable
  /// observation must throw [AnkiSyncAbort], never return a partial map.
  Future<AnkiCollectionSnapshot> snapshot();

  /// Idempotently places the note's card(s) in [deckName], creating the deck if
  /// absent. Returns whether the requested projection was applied. Never
  /// throws: an unavailable deck operation is a reported note failure, not a
  /// reason to silently leave category and deck out of sync.
  Future<bool> moveToDeck(int noteId, String deckName);

  /// Retire only a note carrying this exact Obsidian source link. True means
  /// confirmed absence after deletion (or an already absent projection).
  /// Unknown identity/availability must fail and keep the local Anki id.
  Future<bool> retireNote(int noteId, String expectedSourceUri) async => false;
}

/// One Anki note as the collection currently holds it.
class AnkiNoteState {
  final int id;
  final String front;
  final String back;
  final Set<String> tags;

  /// Deck name of each of the note's cards.
  final Set<String> decks;

  const AnkiNoteState({
    required this.id,
    required this.front,
    required this.back,
    required this.tags,
    required this.decks,
  });

  /// Deck lookup is case-insensitive in both backends, so placement is too.
  bool isInDeck(String deckName) =>
      decks.isNotEmpty &&
      decks.every((deck) => deck.toLowerCase() == deckName.toLowerCase());

  bool holds(String front, String back, List<String> tags) =>
      this.front == front &&
      this.back == back &&
      this.tags.length == tags.toSet().length &&
      this.tags.containsAll(tags);
}

/// A complete observation of the collection's "Basic" notes, by note id.
class AnkiCollectionSnapshot {
  final Map<int, AnkiNoteState> notes;
  const AnkiCollectionSnapshot(this.notes);
}

/// Splits Anki's space-separated tag field into a set.
Set<String> parseAnkiTags(String raw) =>
    raw.split(RegExp(r'\s+')).where((tag) => tag.isNotEmpty).toSet();

/// Match the exact source href, accepting the renderer's original form and
/// HTML-escaped ampersands. Mere text mentioning a source is not ownership.
bool hasAnkiSourceLink(String front, String sourceUri) => [
  sourceUri,
  sourceUri.replaceAll('&', '&amp;'),
].any((uri) => front.contains('href="$uri"') || front.contains("href='$uri'"));

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
