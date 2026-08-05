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

/// Returns all `[[target]]` names found in [text], stripping any `|alias` suffix.
/// `[[Note Name]]` → `"Note Name"`;  `[[Note Name|alias]]` → `"Note Name"`.
List<String> extractWikilinks(String text) {
  final pattern = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]');
  return pattern.allMatches(text).map((m) => m.group(1)!.trim()).toList();
}

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

/// Rewrites `[[wikilinks]]` to HTML anchors via [buildHref].
/// Handles both `[[Name]]` and `[[Name|alias]]` forms.
String rewriteWikilinksToHtml(
  String text,
  String Function(String target, String display) buildHref,
) {
  return text.replaceAllMapped(
    RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
    (m) {
      final target = m.group(1)!.trim();
      final display = (m.group(2) ?? target).trim();
      return buildHref(target, display);
    },
  );
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
String obsidianUri(String vaultPath, String noteFilePath) =>
    obsidianUriForName(vaultPath, p.basenameWithoutExtension(noteFilePath));

/// Returns an `obsidian://open` URI for a bare note [noteName] (a wikilink
/// target, already extension-less) inside [vaultPath]. Shares the vault-name
/// derivation and percent-encoding of [obsidianUri]; the only difference is
/// that the note name is used verbatim rather than stripped from a file path.
String obsidianUriForName(String vaultPath, String noteName) {
  final vaultName = p.basename(vaultPath);
  return 'obsidian://open?vault=${Uri.encodeComponent(vaultName)}'
      '&file=${Uri.encodeComponent(noteName)}';
}

/// Reads scalar or list-style Obsidian `alias:` / `aliases:` values out of a
/// raw frontmatter block. Pure — no I/O, no YAML dependency.
/// Handles `aliases: foo`, `aliases: [a, b]`, and a `- item` block.
List<String> parseAliases(String? frontmatter) {
  if (frontmatter == null || frontmatter.isEmpty) return const [];
  final out = <String>[];
  var collecting = false;
  for (final line in frontmatter.split('\n')) {
    final stripped = line.trim();
    final topLevel = line.isNotEmpty &&
        !line.startsWith(RegExp(r'\s')) &&
        !stripped.startsWith('- ');
    if (topLevel) {
      final colon = line.indexOf(':');
      if (colon < 0) {
        collecting = false;
        continue;
      }
      final key = line.substring(0, colon).trim();
      collecting = key == 'alias' || key == 'aliases';
      final value = line.substring(colon + 1).trim();
      if (collecting && value.isNotEmpty) {
        final items = value.startsWith('[') && value.endsWith(']')
            ? value.substring(1, value.length - 1).split(',')
            : [value];
        out.addAll(items.map(_unquote));
      }
    } else if (collecting && stripped.startsWith('- ')) {
      out.add(_unquote(stripped.substring(2)));
    }
  }
  final seen = <String>{};
  return [
    for (final a in out)
      if (a.isNotEmpty && seen.add(a)) a
  ];
}

String _unquote(String value) {
  final t = value.trim();
  if (t.length >= 2 &&
      ((t.startsWith("'") && t.endsWith("'")) ||
          (t.startsWith('"') && t.endsWith('"')))) {
    return t.substring(1, t.length - 1).trim();
  }
  return t;
}

/// Resolves a wikilink [target] to a canonical vault-relative path using a map
/// built by `buildLinkTargets`. Returns [target] unchanged when it is unknown
/// or ambiguous — a wrong link is worse than a link that simply does not
/// resolve, so this never guesses. Pure — no I/O.
String resolveLinkTarget(String target, Map<String, String>? canonical) {
  if (canonical == null || canonical.isEmpty) return target;
  final hash = target.indexOf('#');
  final base = hash < 0 ? target : target.substring(0, hash);
  final anchor = hash < 0 ? '' : target.substring(hash);
  final key = base.replaceAll('\\', '/').trim().toLowerCase();
  final hit = canonical[key];
  return hit == null ? target : '$hit$anchor';
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

/// Leading characters that make a YAML plain scalar ambiguous (flow indicators,
/// anchors, tags, etc.). A value starting with one of these must be quoted —
/// e.g. `[[wikilink]]` would otherwise parse as a flow sequence.
const _yamlLeadingIndicators = {
  '[', ']', '{', '}', ',', '&', '*', '!', '|', '>', '@', '%', '?', '`'
};

/// Quotes and escapes [s] for use as a YAML scalar value when needed.
/// Wraps in double-quotes if the value is empty, contains `:`, `#`, `"`, `'`,
/// or leading/trailing whitespace, or begins with a YAML indicator character.
/// Backslashes are escaped before quotes.
String yamlScalar(String s) {
  if (s.isEmpty ||
      s.contains(':') ||
      s.contains('#') ||
      s.contains('"') ||
      s.contains("'") ||
      s.startsWith(' ') ||
      s.endsWith(' ') ||
      _yamlLeadingIndicators.contains(s[0])) {
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
