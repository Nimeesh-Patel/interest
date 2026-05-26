// Pure Markdown text utilities. No I/O, no dart:io.
// All functions are top-level — no state, no class wrappers.

import 'package:yaml/yaml.dart';

// ── Frontmatter split ─────────────────────────────────────────────────────────

/// Splits a Markdown string into optional YAML frontmatter and body.
/// Uses line-based detection: opens on `---`, closes on next `---` line.
/// Returns frontmatter == null when no valid delimiters are found.
/// Body is the text after the closing `---`, left-trimmed.
({String? frontmatter, String body}) splitFrontmatter(String content) {
  final lines = content.split('\n');
  if (lines.isEmpty || lines[0].trim() != '---') {
    return (frontmatter: null, body: content);
  }
  int closeIdx = -1;
  for (int i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      closeIdx = i;
      break;
    }
  }
  if (closeIdx == -1) return (frontmatter: null, body: content);
  final frontmatter = lines.sublist(1, closeIdx).join('\n');
  final body = lines.sublist(closeIdx + 1).join('\n').trimLeft();
  return (frontmatter: frontmatter, body: body);
}

// ── Section parsers ───────────────────────────────────────────────────────────

/// Parses H2 (`##`) sections from a Markdown body.
/// `###` and deeper headings are treated as content within the parent H2.
/// Returns an insertion-ordered map of section name → raw content (trimRight).
/// Used by entity and Letterboxd services.
Map<String, String> parseSectionsH2(String body) {
  final result = <String, String>{};
  final lines = body.split('\n');
  String? currentSection;
  final buf = StringBuffer();

  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('## ') && !t.startsWith('### ')) {
      if (currentSection != null) {
        result[currentSection] = buf.toString().trimRight();
        buf.clear();
      }
      currentSection = t.substring(3).trim();
    } else if (currentSection != null) {
      buf.writeln(line);
    }
  }
  if (currentSection != null) {
    result[currentSection] = buf.toString().trimRight();
  }
  return result;
}

/// Parses H1 (`#`) sections from a Markdown body.
/// Used by Anki storage service (Front / Back / Text are H1 sections).
/// Section content is `.trim()`-ed (not `trimRight`).
Map<String, String> parseSectionsH1(String body) {
  final sections = <String, String>{};
  final lines = body.split('\n');
  String? currentSection;
  final buf = StringBuffer();

  for (final line in lines) {
    if (line.startsWith('# ')) {
      if (currentSection != null) {
        sections[currentSection] = buf.toString().trim();
      }
      currentSection = line.substring(2).trim();
      buf.clear();
    } else {
      if (currentSection != null) buf.writeln(line);
    }
  }
  if (currentSection != null) {
    sections[currentSection] = buf.toString().trim();
  }
  return sections;
}

// ── H1 title extractor ────────────────────────────────────────────────────────

/// Returns the first H1 title from a Markdown body, or null if absent.
String? extractH1(String body) {
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.startsWith('# ') && !t.startsWith('## ')) {
      return t.substring(2).trim();
    }
  }
  return null;
}

// ── Wikilink extractor ────────────────────────────────────────────────────────

final _wikilinkRegex = RegExp(r'\[\[([^\]]+)\]\]');

/// Returns all `[[name]]` targets found anywhere in [text].
List<String> extractWikilinks(String text) =>
    _wikilinkRegex.allMatches(text).map((m) => m.group(1)!).toList();

/// Returns wikilink targets from a pre-parsed section content string.
List<String> parseSectionAsWikilinks(String sectionContent) =>
    extractWikilinks(sectionContent);

/// Returns list items from a pre-parsed section content string.
/// Handles `- item`, `* item`, and bare non-empty lines.
List<String> parseSectionAsList(String sectionContent) {
  final result = <String>[];
  for (final line in sectionContent.split('\n')) {
    final t = line.trim();
    if (t.startsWith('- ') || t.startsWith('* ')) {
      result.add(t.substring(2).trim());
    } else if (t.isNotEmpty) {
      result.add(t);
    }
  }
  return result;
}

// ── Timestamp helpers ─────────────────────────────────────────────────────────

/// Converts milliseconds-since-epoch to ISO 8601 UTC string.
String msToIso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// Parses an ISO 8601 string to milliseconds-since-epoch. Returns null on failure.
int? parseIsoToMs(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    return DateTime.parse(iso).millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }
}

// ── String helpers ────────────────────────────────────────────────────────────

/// Lowercases [name], collapses whitespace to hyphens, strips non-alphanumeric.
/// Returns empty string if [name] is whitespace-only.
String slugify(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll(RegExp(r'[^a-z0-9\-]'), '');

/// Replaces filesystem-illegal characters with `_` and collapses internal whitespace.
String sanitizeFilename(String name) => name
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Generates a unique ID by slugifying [name], then appending `-2`, `-3`, …
/// if the base slug is already in [existing].
/// Falls back to [fallback] if the slug is empty after slugification.
String generateUniqueId(
    String name, Set<String> existing, {required String fallback}) {
  var base = slugify(name);
  if (base.isEmpty) base = fallback;
  if (!existing.contains(base)) return base;
  var n = 2;
  while (existing.contains('$base-$n')) {
    n++;
  }
  return '$base-$n';
}

// ── YAML helper ───────────────────────────────────────────────────────────────

/// Parses a frontmatter string into a [YamlMap]. Returns null on any failure.
YamlMap? parseYamlMap(String? frontmatter) {
  if (frontmatter == null || frontmatter.isEmpty) return null;
  try {
    final yaml = loadYaml(frontmatter);
    return yaml is YamlMap ? yaml : null;
  } catch (_) {
    return null;
  }
}

/// Extracts `deck:` membership from frontmatter YAML.
/// Supports scalar (`deck: name`) and list (`deck: [a, b]`) forms.
/// Returns [] when absent or unparseable.
List<String> parseDeckMetadata(String? frontmatter) {
  final map = parseYamlMap(frontmatter);
  if (map == null || !map.containsKey('deck')) return [];
  final d = map['deck'];
  if (d is String) return [d];
  if (d is YamlList) return d.map((e) => e.toString()).toList();
  return [];
}
