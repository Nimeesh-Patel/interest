/// Why a note, or a whole run, did not sync, in a form the app can show as a
/// card: what is wrong, which notes are involved, and the card at stake.
///
/// Each issue's [message] is also one of the run's `errors`, so code that
/// only reads errors (the manifest, logs, tests) sees every issue too.
enum AnkiIssueKind {
  /// Two or more notes carry one `anki_note_id`. The run stops before any
  /// card changes: only Nimeesh knows which note the card belongs to.
  sharedCard,

  /// A note's `anki_note_id` names a card that was made from a different
  /// note, which still exists. Updating it would hand that note's review
  /// history to this one, so this note is skipped.
  foreignCard,

  /// A note that had a card when Anki last received it has no
  /// `anki_note_id` now. The run stops: syncing would make a fresh card and
  /// cut the studied one loose.
  lostIdentity,

  /// One note could not be synced for another reason; the rest were.
  noteFailed,
}

class AnkiSyncIssue {
  final AnkiIssueKind kind;

  /// The full explanation, as it appears in the run's errors.
  final String message;

  /// Vault-relative paths, without `.md`, of the notes involved, so each
  /// can be opened in Obsidian. The first is the note the issue is about.
  final List<String> notes;

  /// The card at stake, when there is one.
  final int? cardId;

  /// Vault-relative path (without `.md`) of the note the card's own link
  /// names: the note it was made from. Null when unknown.
  final String? cardSource;

  /// The card's two sides as plain text, and its total reviews, when the
  /// collection could be read; empty or null otherwise.
  final String cardProblem;
  final String cardConjecture;
  final int? cardReviews;

  const AnkiSyncIssue({
    required this.kind,
    required this.message,
    required this.notes,
    this.cardId,
    this.cardSource,
    this.cardProblem = '',
    this.cardConjecture = '',
    this.cardReviews,
  });

  /// This issue with the card as the collection now holds it.
  AnkiSyncIssue withCard({
    required String? source,
    required String problem,
    required String conjecture,
    required int reviews,
  }) => AnkiSyncIssue(
    kind: kind,
    message: message,
    notes: notes,
    cardId: cardId,
    cardSource: source,
    cardProblem: problem,
    cardConjecture: conjecture,
    cardReviews: reviews,
  );
}
