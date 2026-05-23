enum RssFeedType { letterboxd, substack, generic }

extension RssFeedTypeLabel on RssFeedType {
  String get label => switch (this) {
        RssFeedType.letterboxd => 'Letterboxd',
        RssFeedType.substack => 'Substack',
        RssFeedType.generic => 'Generic',
      };

  static RssFeedType fromString(String s) => switch (s) {
        'letterboxd' => RssFeedType.letterboxd,
        'substack' => RssFeedType.substack,
        _ => RssFeedType.generic,
      };
}

class RssFeed {
  final String id;
  final String name;
  final String url;
  final RssFeedType type;

  const RssFeed({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
  });

  Map<String, String> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'type': type.name,
      };

  factory RssFeed.fromJson(Map<String, dynamic> json) => RssFeed(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        type: RssFeedTypeLabel.fromString(json['type'] as String? ?? ''),
      );
}
