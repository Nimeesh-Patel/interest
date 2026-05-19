class EntityLink {
  final String id;
  final String from;
  final String to;
  final String type;

  const EntityLink({
    required this.id,
    required this.from,
    required this.to,
    this.type = 'related',
  });

  factory EntityLink.fromJson(Map<String, dynamic> json) => EntityLink(
        id: json['id'] as String,
        from: json['from'] as String,
        to: json['to'] as String,
        type: json['type'] as String? ?? 'related',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'type': type,
      };
}
