import '../../../shared/markdown/md_utils.dart';

/// An Entity is any vault note carrying a `collection:` frontmatter key.
/// It is a plain Markdown note that belongs to a collection and participates in
/// the wikilink graph — the app owns only its frontmatter, never its body.
class Entity {
  /// Stable graph identity: `alias` if present, else the filename slug.
  final String id;

  /// Display name — the note's filename (basename without extension).
  String name;

  /// Raw `collection:` value (e.g. "People"). Source of truth for grouping.
  String collection;

  List<String> tags;
  double? score;
  final int createdAt;
  int updatedAt;

  /// Absolute path of the backing `.md` file; null for an entity not yet saved.
  String? sourcePath;

  Entity({
    required this.id,
    required this.name,
    required this.collection,
    List<String>? tags,
    this.score,
    required this.createdAt,
    int? updatedAt,
    this.sourcePath,
  })  : tags = tags ?? [],
        updatedAt = updatedAt ?? createdAt;

  /// Slugified collection name — the grouping/filter key.
  String get collectionId => slugify(collection);

  Entity copyWith() => Entity(
        id: id,
        name: name,
        collection: collection,
        tags: List<String>.from(tags),
        score: score,
        createdAt: createdAt,
        updatedAt: updatedAt,
        sourcePath: sourcePath,
      );
}
