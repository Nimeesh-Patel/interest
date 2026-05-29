class ResurfaceNote {
  final String sourcePath;
  final String sourceFile;
  final String body;
  final bool hasCard;
  final String? front;
  final String? back;
  final List<String> decks;

  const ResurfaceNote({
    required this.sourcePath,
    required this.sourceFile,
    required this.body,
    required this.hasCard,
    this.front,
    this.back,
    this.decks = const [],
  });
}
