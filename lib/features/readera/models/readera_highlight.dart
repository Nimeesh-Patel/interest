class ReaderaHighlight {
  final String id; // note_uri — UUID, globally stable
  final String bookId; // doc_sha1 of the parent book
  final String text;
  final int? page;
  final String? createdAt; // ISO 8601 derived from note_insert_time

  const ReaderaHighlight({
    required this.id,
    required this.bookId,
    required this.text,
    this.page,
    this.createdAt,
  });
}
