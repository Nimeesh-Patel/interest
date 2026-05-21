import '../../../shared/markdown/md_utils.dart';

class Book {
  final String alias;
  String title;
  List<String> authors;
  String? isbn;
  int? hardcoverId;
  int? readwiseId;
  String? status; // null | want_to_read | reading | read | paused | dnf
  double? rating;
  String? startedAt;
  String? finishedAt;
  int? numHighlights;
  String? lastHighlightAt;
  final int createdAt;
  int updatedAt;
  // runtime-only — not serialized
  String? filePath;
  Map<String, String>? rawSections;

  Book({
    required this.alias,
    required this.title,
    required this.authors,
    this.isbn,
    this.hardcoverId,
    this.readwiseId,
    this.status,
    this.rating,
    this.startedAt,
    this.finishedAt,
    this.numHighlights,
    this.lastHighlightAt,
    required this.createdAt,
    required this.updatedAt,
    this.filePath,
    this.rawSections,
  });

  static Book fromFrontmatterYaml(
      Map yaml, String body, String filePath) {
    final authors = _parseAuthors(yaml);
    final createdAtMs = parseIsoToMs(yaml['created_at']?.toString()) ??
        DateTime.now().millisecondsSinceEpoch;
    final updatedAtMs = parseIsoToMs(yaml['updated_at']?.toString()) ??
        DateTime.now().millisecondsSinceEpoch;

    return Book(
      alias: yaml['alias']?.toString() ?? '',
      title: yaml['title']?.toString() ?? '',
      authors: authors,
      isbn: yaml['isbn']?.toString(),
      hardcoverId: _parseInt(yaml['hardcover_id']),
      readwiseId: _parseInt(yaml['readwise_id']),
      status: yaml['status']?.toString(),
      rating: _parseDouble(yaml['rating']),
      startedAt: yaml['started_at']?.toString(),
      finishedAt: yaml['finished_at']?.toString(),
      numHighlights: _parseInt(yaml['num_highlights']),
      lastHighlightAt: yaml['last_highlight_at']?.toString(),
      createdAt: createdAtMs,
      updatedAt: updatedAtMs,
      filePath: filePath,
      rawSections: parseSectionsH2(body),
    );
  }

  Book copyWith({
    String? alias,
    String? title,
    List<String>? authors,
    String? isbn,
    int? hardcoverId,
    int? readwiseId,
    String? status,
    double? rating,
    String? startedAt,
    String? finishedAt,
    int? numHighlights,
    String? lastHighlightAt,
    int? updatedAt,
    String? filePath,
    Map<String, String>? rawSections,
    bool clearHardcoverId = false,
    bool clearReadwiseId = false,
  }) {
    return Book(
      alias: alias ?? this.alias,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      isbn: isbn ?? this.isbn,
      hardcoverId: clearHardcoverId ? null : (hardcoverId ?? this.hardcoverId),
      readwiseId: clearReadwiseId ? null : (readwiseId ?? this.readwiseId),
      status: status ?? this.status,
      rating: rating ?? this.rating,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      numHighlights: numHighlights ?? this.numHighlights,
      lastHighlightAt: lastHighlightAt ?? this.lastHighlightAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      filePath: filePath ?? this.filePath,
      rawSections: rawSections ?? this.rawSections,
    );
  }

  static List<String> _parseAuthors(Map yaml) {
    final raw = yaml['authors'];
    if (raw == null) {
      // Legacy: author (single string)
      final author = yaml['author']?.toString() ?? '';
      if (author.isEmpty) return [];
      return author.split(', ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [raw.toString()];
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
