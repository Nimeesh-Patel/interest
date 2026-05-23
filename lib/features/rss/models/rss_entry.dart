class RssEntry {
  final String? guid;
  final String title;
  final String? link;
  final String? pubDate;
  final String? description;
  // All <item> child elements by localName — adapters use this for source-specific fields.
  final Map<String, String> extras;

  const RssEntry({
    this.guid,
    required this.title,
    this.link,
    this.pubDate,
    this.description,
    this.extras = const {},
  });
}
