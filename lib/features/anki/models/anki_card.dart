enum AnkiNoteType { basic, cloze }

class AnkiCard {
  final String? ankiId;
  final String filePath;
  final AnkiNoteType noteType;
  final String deck;
  final List<String> tags;
  final DateTime updatedAt;
  final String front;
  final String back;
  final String text;
  final Map<String, String> extraSections;

  const AnkiCard({
    required this.ankiId,
    required this.filePath,
    required this.noteType,
    required this.deck,
    required this.tags,
    required this.updatedAt,
    required this.front,
    required this.back,
    required this.text,
    required this.extraSections,
  });

  AnkiCard copyWith({
    String? ankiId,
    bool clearAnkiId = false,
    String? filePath,
    AnkiNoteType? noteType,
    String? deck,
    List<String>? tags,
    DateTime? updatedAt,
    String? front,
    String? back,
    String? text,
    Map<String, String>? extraSections,
  }) {
    return AnkiCard(
      ankiId: clearAnkiId ? null : (ankiId ?? this.ankiId),
      filePath: filePath ?? this.filePath,
      noteType: noteType ?? this.noteType,
      deck: deck ?? this.deck,
      tags: tags ?? List.from(this.tags),
      updatedAt: updatedAt ?? this.updatedAt,
      front: front ?? this.front,
      back: back ?? this.back,
      text: text ?? this.text,
      extraSections: extraSections ?? Map.from(this.extraSections),
    );
  }

  String get displayTitle {
    if (noteType == AnkiNoteType.cloze) {
      final plain = text.replaceAll(RegExp(r'\{\{c\d+::(.*?)\}\}'), r'$1');
      return plain.trim().isEmpty ? '(empty)' : plain.trim();
    }
    return front.trim().isEmpty ? '(empty)' : front.trim();
  }
}
