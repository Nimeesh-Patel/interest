import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/anki_card.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../core/vault_service.dart';

class AnkiStorageService {
  static Future<List<AnkiCard>> loadCards() async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null) return [];
      final dir = Directory(VaultService.ankiPath(vault));
      if (!await dir.exists()) return [];
      final cards = <AnkiCard>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.md')) continue;
        // Skip .trash subdirectory files
        if (p.basename(p.dirname(entity.path)) == '.trash') continue;
        try {
          final content = await entity.readAsString();
          final card = _parseCardFile(entity.path, content);
          if (card != null) cards.add(card);
        } catch (_) {}
      }
      return cards;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCard(AnkiCard card) async {
    try {
      final file = File(card.filePath);
      if (await file.exists()) {
        final existing = await file.readAsString();
        final patched = _patchCardContent(existing, card);
        await file.writeAsString(patched);
      } else {
        await file.writeAsString(_buildCardContent(card));
      }
    } catch (_) {}
  }

  static Future<AnkiCard?> createNewCard({
    required AnkiNoteType noteType,
    required String deck,
    required List<String> tags,
    required String front,
    required String back,
    required String text,
  }) async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null) return null;
      final ankiDir = VaultService.ankiPath(vault);
      await Directory(ankiDir).create(recursive: true);
      final existing = await _existingFileNames(ankiDir);
      final seed = noteType == AnkiNoteType.cloze ? text : front;
      final filePath = p.join(ankiDir, '${_slugifyTitle(seed, existing)}.md');
      final card = AnkiCard(
        ankiId: null,
        filePath: filePath,
        noteType: noteType,
        deck: deck,
        tags: tags,
        updatedAt: DateTime.now().toUtc(),
        front: front,
        back: back,
        text: text,
        extraSections: {},
      );
      await File(filePath).writeAsString(_buildCardContent(card));
      return card;
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateAnkiId(String filePath, String ankiId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final split = splitFrontmatter(content);
      if (split.frontmatter == null) return;
      var fm = split.frontmatter!;
      // Insert or replace anki_id line
      if (fm.contains('anki_id:')) {
        fm = fm.replaceAll(RegExp(r'anki_id:.*'), 'anki_id: $ankiId');
      } else {
        fm = 'anki_id: $ankiId\n$fm';
      }
      await file.writeAsString('---\n$fm\n---\n${split.body}');
    } catch (_) {}
  }

  static Future<void> trashCard(String filePath) async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null) return;
      final trashDir = VaultService.ankiTrashPath(vault);
      await Directory(trashDir).create(recursive: true);
      final dest = p.join(trashDir, p.basename(filePath));
      await File(filePath).rename(dest);
    } catch (_) {}
  }

  static Future<AnkiCard?> createFromAnki(Map<String, dynamic> ankiNote) async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null) return null;
      final ankiDir = VaultService.ankiPath(vault);
      await Directory(ankiDir).create(recursive: true);

      final noteId = (ankiNote['noteId'] as num?)?.toInt();
      if (noteId == null) return null;
      final modelName = ankiNote['modelName']?.toString() ?? '';
      final fields = ankiNote['fields'] as Map?;
      final rawTags = ankiNote['tags'];
      final tags = rawTags is List ? rawTags.map((t) => t.toString()).toList() : <String>[];
      final modUnix = (ankiNote['mod'] as num?)?.toInt() ?? 0;
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(modUnix * 1000, isUtc: true);

      AnkiNoteType noteType;
      String front = '', back = '', text = '';
      if (modelName == 'Cloze') {
        noteType = AnkiNoteType.cloze;
        text = _fieldValue(fields, 'Text');
      } else {
        noteType = AnkiNoteType.basic;
        front = _fieldValue(fields, 'Front');
        back = _fieldValue(fields, 'Back');
      }

      final existing = await _existingFileNames(ankiDir);
      final seed = noteType == AnkiNoteType.cloze ? text : front;
      final filePath = p.join(ankiDir, '${_slugifyTitle(seed, existing)}.md');

      final card = AnkiCard(
        ankiId: noteId.toString(),
        filePath: filePath,
        noteType: noteType,
        deck: _deckFromNote(ankiNote),
        tags: tags,
        updatedAt: updatedAt,
        front: front,
        back: back,
        text: text,
        extraSections: {},
      );
      await File(filePath).writeAsString(_buildCardContent(card));
      return card;
    } catch (_) {
      return null;
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  static AnkiCard? _parseCardFile(String filePath, String content) {
    try {
      final split = splitFrontmatter(content);
      if (split.frontmatter == null) return null;

      final yaml = parseYamlMap(split.frontmatter);
      if (yaml == null) return null;

      final ankiId = yaml['anki_id']?.toString();
      final noteTypeStr = yaml['note_type']?.toString() ?? 'Basic';
      final deck = yaml['deck']?.toString() ?? 'Default';
      final rawTags = yaml['tags'];
      final tags = rawTags is YamlList
          ? rawTags.map((t) => t.toString()).toList()
          : <String>[];
      final updatedAtStr = yaml['updated_at']?.toString();
      final updatedAt = updatedAtStr != null
          ? (DateTime.tryParse(updatedAtStr) ?? DateTime.now().toUtc())
          : DateTime.now().toUtc();
      final noteType =
          noteTypeStr == 'Cloze' ? AnkiNoteType.cloze : AnkiNoteType.basic;

      final sections = parseSectionsH1(split.body);
      String front = '', back = '', text = '';
      final extra = <String, String>{};
      for (final entry in sections.entries) {
        if (entry.key == 'Front') {
          front = entry.value.trim();
        } else if (entry.key == 'Back') {
          back = entry.value.trim();
        } else if (entry.key == 'Text') {
          text = entry.value.trim();
        } else {
          extra[entry.key] = entry.value;
        }
      }

      return AnkiCard(
        ankiId: ankiId,
        filePath: filePath,
        noteType: noteType,
        deck: deck,
        tags: tags,
        updatedAt: updatedAt,
        front: front,
        back: back,
        text: text,
        extraSections: extra,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Building/patching ─────────────────────────────────────────────────────

  static String _buildCardContent(AnkiCard card) {
    final fm = _buildFrontmatter(card);
    final body = _buildBody(card);
    return '$fm\n$body';
  }

  static String _buildFrontmatter(AnkiCard card) {
    final buf = StringBuffer('---\n');
    if (card.ankiId != null) buf.writeln('anki_id: ${card.ankiId}');
    buf.writeln('note_type: ${card.noteType == AnkiNoteType.cloze ? 'Cloze' : 'Basic'}');
    buf.writeln('deck: ${card.deck}');
    if (card.tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final t in card.tags) {
        buf.writeln('  - $t');
      }
    } else {
      buf.writeln('tags: []');
    }
    buf.writeln('updated_at: ${card.updatedAt.toIso8601String()}');
    buf.write('---');
    return buf.toString();
  }

  static String _buildBody(AnkiCard card) {
    final buf = StringBuffer();
    if (card.noteType == AnkiNoteType.basic) {
      buf.writeln('# Front\n');
      buf.writeln(card.front);
      buf.writeln('\n# Back\n');
      buf.writeln(card.back);
    } else {
      buf.writeln('# Text\n');
      buf.writeln(card.text);
    }
    for (final entry in card.extraSections.entries) {
      buf.writeln('\n# ${entry.key}\n');
      buf.write(entry.value);
    }
    return buf.toString();
  }

  // Patch: rewrite frontmatter + semantic sections; preserve extra sections
  static String _patchCardContent(String existing, AnkiCard card) {
    try {
      final split = splitFrontmatter(existing);
      if (split.frontmatter == null) return _buildCardContent(card);
      final sections = parseSectionsH1(split.body);
      final extra = <String, String>{};
      for (final entry in sections.entries) {
        if (!_isSemanticSection(entry.key, card.noteType)) {
          extra[entry.key] = entry.value;
        }
      }
      final updatedCard = card.copyWith(extraSections: extra);
      return _buildCardContent(updatedCard);
    } catch (_) {
      return _buildCardContent(card);
    }
  }

  static bool _isSemanticSection(String name, AnkiNoteType type) {
    if (type == AnkiNoteType.basic) return name == 'Front' || name == 'Back';
    return name == 'Text';
  }

  // ── Filename helpers ──────────────────────────────────────────────────────

  static Future<List<String>> _existingFileNames(String dir) async {
    try {
      final d = Directory(dir);
      if (!await d.exists()) return [];
      final names = <String>[];
      await for (final e in d.list()) {
        if (e is File) names.add(p.basenameWithoutExtension(e.path));
      }
      return names;
    } catch (_) {
      return [];
    }
  }

  // Unique to Anki: strips cloze syntax, caps at 50 chars.
  // Not in md_utils because of the cloze-specific logic.
  static String _slugifyTitle(String text, List<String> existing) {
    final clozeStripped = text.replaceAll(RegExp(r'\{\{c\d+::(.*?)\}\}'), r'$1');
    var slug = clozeStripped
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    if (slug.length > 50) slug = slug.substring(0, 50);
    if (slug.isEmpty) slug = 'card';
    if (!existing.contains(slug)) return slug;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$slug-$i';
      if (!existing.contains(candidate)) return candidate;
    }
    return '$slug-${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Misc helpers ──────────────────────────────────────────────────────────

  static String _fieldValue(Map? fields, String key) {
    if (fields == null) return '';
    final field = fields[key];
    if (field is Map) return (field['value'] ?? '').toString();
    return field?.toString() ?? '';
  }

  static String _deckFromNote(Map<String, dynamic> ankiNote) {
    // AnkiConnect notesInfo doesn't directly return deck; use cards[0] info if present
    // For V1, default to 'Default' — deck resolution happens via a separate findNotes query
    return ankiNote['deckName']?.toString() ?? 'Default';
  }
}
