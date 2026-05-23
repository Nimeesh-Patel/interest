class Article {
  final String alias;
  final String title;
  final String? feedId;
  final String? guid;
  final String? url;
  final String? author;
  final String? publishedAt;
  final String? summary;
  final String createdAt;
  final String updatedAt;
  final String? filePath;

  const Article({
    required this.alias,
    required this.title,
    this.feedId,
    this.guid,
    this.url,
    this.author,
    this.publishedAt,
    this.summary,
    required this.createdAt,
    required this.updatedAt,
    this.filePath,
  });
}
