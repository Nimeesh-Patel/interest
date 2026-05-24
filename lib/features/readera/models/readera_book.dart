class ReaderaBook {
  final String id; // doc_sha1 — stable content hash
  final String title;
  final String author;

  const ReaderaBook({
    required this.id,
    required this.title,
    required this.author,
  });
}
