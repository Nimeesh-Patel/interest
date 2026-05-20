class ReadwiseHighlight {
  final int id;
  final String text;
  final String? note;
  final String? location;
  final String? highlightedAt;
  final List<String> tags;

  const ReadwiseHighlight({
    required this.id,
    required this.text,
    this.note,
    this.location,
    this.highlightedAt,
    required this.tags,
  });

  factory ReadwiseHighlight.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'] as List? ?? [];
    final tags = rawTags
        .map((t) => (t as Map<String, dynamic>)['name'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toList();

    final locationRaw = json['location'];
    final location =
        locationRaw != null && locationRaw != 0 ? locationRaw.toString() : null;

    return ReadwiseHighlight(
      id: json['id'] as int,
      text: json['text'] as String? ?? '',
      note: json['note'] as String?,
      location: location,
      highlightedAt: json['highlighted_at'] as String?,
      tags: tags,
    );
  }
}
