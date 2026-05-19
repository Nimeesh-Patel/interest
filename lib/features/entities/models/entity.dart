class Entity {
  final String id;
  String name;
  String categoryId;
  List<String> notes;
  List<String> links;
  List<String> tags;
  double? score;
  final int createdAt;
  int updatedAt;
  Map<String, String>? rawSections;
  String? watchedDate;
  String? letterboxdUrl;
  String? tmdbId;

  Entity({
    required this.id,
    required this.name,
    required this.categoryId,
    List<String>? notes,
    List<String>? links,
    List<String>? tags,
    this.score,
    required this.createdAt,
    int? updatedAt,
    this.rawSections,
    this.watchedDate,
    this.letterboxdUrl,
    this.tmdbId,
  })  : notes = notes ?? [],
        links = links ?? [],
        tags = tags ?? [],
        updatedAt = updatedAt ?? createdAt;

  factory Entity.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    return Entity(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String? ?? '',
      notes: (json['notes'] as List<dynamic>?)?.cast<String>() ?? [],
      links: (json['links'] as List<dynamic>?)?.cast<String>() ?? [],
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      score: (json['score'] as num?)?.toDouble(),
      createdAt: createdAt,
      updatedAt: json['updated_at'] as int? ?? createdAt,
    );
  }

  Entity copyWith() => Entity(
        id: id,
        name: name,
        categoryId: categoryId,
        notes: List<String>.from(notes),
        links: List<String>.from(links),
        tags: List<String>.from(tags),
        score: score,
        createdAt: createdAt,
        updatedAt: updatedAt,
        rawSections: rawSections != null ? Map<String, String>.from(rawSections!) : null,
        watchedDate: watchedDate,
        letterboxdUrl: letterboxdUrl,
        tmdbId: tmdbId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category_id': categoryId,
        'notes': notes,
        'links': links,
        'tags': tags,
        'score': score,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
