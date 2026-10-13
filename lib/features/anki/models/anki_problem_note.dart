/// A review-ready `***` note without collection membership — the notes the
/// Anki sync pushes. This is a slim projection of exactly what the sync needs;
/// it is produced by [AnkiProblemNoteScanner] and consumed by [AnkiSyncService].
/// The app never edits or renders these notes — rendering lives in Obsidian
/// (the Problem Notes plugin); Interest only pushes them to Anki.
class AnkiProblemNote {
  final String sourcePath;
  final String sourceFile;
  final String? front;
  final String? back;

  /// `category:` frontmatter → Anki deck (default `Default`).
  final String? category;
  final List<String> tags;

  /// Anki collection note id, written back on first sync via the surgical
  /// frontmatter patch (the sync's only vault write).
  final String? ankiNoteId;

  const AnkiProblemNote({
    required this.sourcePath,
    required this.sourceFile,
    this.front,
    this.back,
    this.category,
    this.tags = const [],
    this.ankiNoteId,
  });
}

/// A current collection note still linked to a former Anki projection.
/// Its body need not remain a Problem Note; only the owned link is retired.
class AnkiNoteRetirement {
  final String sourcePath;
  final String sourceFile;
  final String ankiNoteId;

  const AnkiNoteRetirement({
    required this.sourcePath,
    required this.sourceFile,
    required this.ankiNoteId,
  });
}
