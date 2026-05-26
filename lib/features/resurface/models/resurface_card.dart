class ResurfaceCard {
  final String sourcePath;
  final String sourceFile;
  final String front;
  final String back;
  final List<String> decks;

  const ResurfaceCard({
    required this.sourcePath,
    required this.sourceFile,
    required this.front,
    required this.back,
    this.decks = const [],
  });
}
