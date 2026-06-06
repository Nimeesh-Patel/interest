// Pure Markdown text utilities. No I/O, no dart:io.
// All functions are top-level — no state, no class wrappers.

import 'package:path/path.dart' as p;
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

// ── Front/back separator ──────────────────────────────────────────────────────

/// Splits [body] into front/back at the first `***` separator outside code fences.
/// Returns null if no valid separator found or either side is empty after trim.
({String front, String back})? splitFrontBack(String body) {
  final hrPattern = RegExp(r'^\*{3,}\s*$');
  final lines = body.split('\n');
  bool inCodeFence = false;
  int? separatorIdx;
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inCodeFence = !inCodeFence;
      continue;
    }
    if (!inCodeFence && hrPattern.hasMatch(line)) {
      separatorIdx = i;
      break;
    }
  }
  if (separatorIdx == null) return null;
  final front = lines.sublist(0, separatorIdx).join('\n').trim();
  final back = lines.sublist(separatorIdx + 1).join('\n').trim();
  if (front.isEmpty || back.isEmpty) return null;
  return (front: front, back: back);
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

/// Strips wikilinks to plain text: [[Target|display]] → display, [[Target]] → Target.
String plainTextWikilinks(String text) => text.replaceAllMapped(
      RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
      (m) => m[2] ?? m[1]!,
    );

/// Rewrites [[Target]] and [[Target|Display]] as standard Markdown links
/// using the `wikilink:` URI scheme so flutter_markdown can render and
/// dispatch them via onTapLink.
String substituteWikilinks(String text) {
  return text.replaceAllMapped(
    RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
    (m) {
      final target = m.group(1)!.trim();
      final display = m.group(2)?.trim() ?? target;
      return '[$display](wikilink:${Uri.encodeComponent(target)})';
    },
  );
}

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

/// Canonical note identity string derived from a file path or bare filename.
/// Use this everywhere a note name is used as a map key or log entry.
String noteKey(String filePath) => p.basenameWithoutExtension(filePath).toLowerCase();

/// Returns an `obsidian://open` URI for [noteFilePath] inside [vaultPath].
/// Pure — no I/O. Both vault name and note name are percent-encoded.
String obsidianUri(String vaultPath, String noteFilePath) {
  final vaultName = p.basename(vaultPath);
  final noteName = p.basenameWithoutExtension(noteFilePath);
  return 'obsidian://open?vault=${Uri.encodeComponent(vaultName)}'
      '&file=${Uri.encodeComponent(noteName)}';
}

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

/// Strips HTML tags and common entities from [html], collapsing excess newlines.
String stripHtml(String html) {
  if (html.isEmpty) return '';
  var text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

// ── Frontmatter builder ───────────────────────────────────────────────────────

/// Builds a `---`-delimited frontmatter block from [fields].
/// Fields listed in [knownOrder] are written first; any remaining fields follow.
/// List values are emitted as YAML block sequences; scalars are quoted when needed.
/// Null values and empty strings are skipped silently.
String buildFrontmatterBlock(
    Map<String, dynamic> fields, List<String> knownOrder) {
  final buf = StringBuffer('---\n');
  final knownSet = knownOrder.toSet();
  for (final key in knownOrder) {
    if (fields.containsKey(key)) _writeFmField(buf, key, fields[key]);
  }
  for (final entry in fields.entries) {
    if (!knownSet.contains(entry.key)) _writeFmField(buf, entry.key, entry.value);
  }
  buf.write('---');
  return buf.toString();
}

void _writeFmField(StringBuffer buf, String key, dynamic val) {
  if (val == null) return;
  if (val is List) {
    if (val.isEmpty) return;
    buf.writeln('$key:');
    for (final item in val) {
      buf.writeln('  - ${yamlScalar(item.toString())}');
    }
  } else {
    final s = val.toString();
    if (s.isEmpty) return;
    buf.writeln('$key: ${yamlScalar(s)}');
  }
}

/// Quotes and escapes [s] for use as a YAML scalar value when needed.
/// Wraps in double-quotes if the value is empty, or contains `:`, `#`, `"`,
/// `'`, or leading/trailing whitespace. Backslashes are escaped before quotes.
String yamlScalar(String s) {
  if (s.isEmpty ||
      s.contains(':') ||
      s.contains('#') ||
      s.contains('"') ||
      s.contains("'") ||
      s.startsWith(' ') ||
      s.endsWith(' ')) {
    return '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }
  return s;
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
