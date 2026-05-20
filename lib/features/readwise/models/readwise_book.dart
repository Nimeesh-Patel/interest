class ReadwiseBook {
  final int id;
  final String title;
  final String author;
  final String category;
  final int numHighlights;
  final String? lastHighlightAt;
  final String? coverImageUrl;
  final String? sourceUrl;

  const ReadwiseBook({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.numHighlights,
    this.lastHighlightAt,
    this.coverImageUrl,
    this.sourceUrl,
  });

  factory ReadwiseBook.fromJson(Map<String, dynamic> json) => ReadwiseBook(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        category: json['category'] as String? ?? 'books',
        numHighlights: json['num_highlights'] as int? ?? 0,
        lastHighlightAt: json['last_highlight_at'] as String?,
        coverImageUrl: json['cover_image_url'] as String?,
        sourceUrl: json['source_url'] as String?,
      );
}
