/// A book is an ordinary entity: a vault-root note with `collection: Books` and
/// a `hardcover_id`. This is the slim projection the Hardcover screen and sync
/// read — the same note also appears in the Collections tab like any entity.
class BookNote {
  final String filePath;
  final String title;
  final List<String> authors;
  final int? hardcoverId;
  final String? status; // want_to_read | reading | read | paused | dnf
  final double? rating;

  const BookNote({
    required this.filePath,
    required this.title,
    this.authors = const [],
    this.hardcoverId,
    this.status,
    this.rating,
  });
}
