class HardcoverBook {
  final int userBookId;
  final int bookId;
  final String title;
  final List<String> authors;
  final int statusId;
  final double? rating;
  final String? dateAdded;
  final String? firstStartedReadingDate;
  final String? lastReadDate;

  const HardcoverBook({
    required this.userBookId,
    required this.bookId,
    required this.title,
    required this.authors,
    required this.statusId,
    this.rating,
    this.dateAdded,
    this.firstStartedReadingDate,
    this.lastReadDate,
  });

  static const _statusSlugs = {
    1: 'want_to_read',
    2: 'reading',
    3: 'read',
    4: 'paused',
    5: 'dnf',
  };

  String get statusSlug => _statusSlugs[statusId] ?? 'read';

  static HardcoverBook? fromJson(Map<String, dynamic> json) {
    try {
      final book = json['book'] as Map<String, dynamic>?;
      if (book == null) return null;

      final rawContributors = book['cached_contributors'];
      final contributors = rawContributors is List ? rawContributors : [];
      final authors = contributors
          .map((c) {
            final m = c as Map?;
            // Try {author: {name: ...}} shape first, then flat {name: ...}
            final author = m?['author'] as Map?;
            return (author?['name'] ?? m?['name'])?.toString() ?? '';
          })
          .where((n) => n.isNotEmpty)
          .toList();

      final ratingRaw = json['rating'];
      final rating = ratingRaw != null
          ? double.tryParse(ratingRaw.toString())
          : null;

      return HardcoverBook(
        userBookId: (json['id'] as num).toInt(),
        bookId: (book['id'] as num).toInt(),
        title: book['title']?.toString() ?? '',
        authors: authors,
        statusId: (json['status_id'] as num?)?.toInt() ?? 3,
        rating: rating,
        dateAdded: json['date_added']?.toString(),
        firstStartedReadingDate:
            json['first_started_reading_date']?.toString(),
        lastReadDate: json['last_read_date']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
