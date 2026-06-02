class ResurfaceNote {
  final String sourcePath;
  final String sourceFile;
  final String body;
  final bool isProblemNote;
  final String? front;
  final String? back;
  final List<String> decks;
  final String? category;
  final List<String> tags;
  final String? ankiNoteId;

  const ResurfaceNote({
    required this.sourcePath,
    required this.sourceFile,
    required this.body,
    required this.isProblemNote,
    this.front,
    this.back,
    this.decks = const [],
    this.category,
    this.tags = const [],
    this.ankiNoteId,
  });
}
