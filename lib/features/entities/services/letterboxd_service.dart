import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import '../../../shared/markdown/md_utils.dart';
import '../../../core/vault_service.dart';

class ImportResult {
  final int created;
  final int updated;
  final int skipped;
  final String? error;

  const ImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    this.error,
  });
}

class LetterboxdService {
  static const _rssUrlKey = 'letterboxd_rss_url';

  static Future<String?> getRssUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rssUrlKey);
  }

  static Future<void> setRssUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rssUrlKey, url);
  }

  static Future<ImportResult> fetchAndImport(String rssUrl) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) {
        return const ImportResult(created: 0, updated: 0, skipped: 0, error: 'No vault configured');
      }

      final entitiesDirPath = VaultService.entitiesPath(vaultPath);
      await Directory(entitiesDirPath).create(recursive: true);

      final existingMovies = await _buildMovieIndex(entitiesDirPath);

      final response = await http
          .get(Uri.parse(rssUrl))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return ImportResult(
          created: 0,
          updated: 0,
          skipped: 0,
          error: 'HTTP ${response.statusCode}',
        );
      }

      final XmlDocument document;
      try {
        document = XmlDocument.parse(response.body);
      } catch (e) {
        return ImportResult(created: 0, updated: 0, skipped: 0, error: 'Failed to parse RSS feed');
      }

      final items = document.findAllElements('item');
      int created = 0, updated = 0, skipped = 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final item in items) {
        try {
          // Extract film title — prefer letterboxd:filmTitle, fall back to <title>
          final filmTitle = _elemText(item, 'filmTitle') ??
              _extractRssTitle(_elemText(item, 'title') ?? '');
          if (filmTitle.isEmpty) {
            skipped++;
            continue;
          }

          final watchedDate = _elemText(item, 'watchedDate');
          final ratingStr = _elemText(item, 'memberRating');
          final score = ratingStr != null ? (double.tryParse(ratingStr) ?? 0) * 2.0 : null;
          final tmdbId = _elemText(item, 'movieId');
          final letterboxdUrl = _extractLink(item);
          final descHtml = _elemText(item, 'description') ?? '';
          final thoughts = _stripHtml(descHtml).trim();

          final normalizedTitle = _normalizeTitle(filmTitle);
          final existingPath = (tmdbId != null ? existingMovies[tmdbId] : null) ??
              existingMovies[normalizedTitle];

          if (existingPath != null) {
            await _updateMovieFile(
              filePath: existingPath,
              score: score,
              watchedDate: watchedDate,
              letterboxdUrl: letterboxdUrl,
              tmdbId: tmdbId,
              thoughts: thoughts,
              updatedAt: now,
            );
            updated++;
          } else {
            var alias = slugify(filmTitle);
            if (alias.isEmpty) alias = 'movie';
            alias = _uniqueAlias(alias, entitiesDirPath);

            final content = _buildMovieMarkdown(
              alias: alias,
              title: filmTitle,
              score: score,
              watchedDate: watchedDate,
              letterboxdUrl: letterboxdUrl,
              tmdbId: tmdbId,
              thoughts: thoughts,
              createdAt: now,
              updatedAt: now,
            );

            final filename = '${sanitizeFilename(filmTitle)}.md';
            final filePath = p.join(entitiesDirPath, filename);
            await File(filePath).writeAsString(content);

            // Update index so subsequent items in same feed don't duplicate
            if (tmdbId != null && tmdbId.isNotEmpty) existingMovies[tmdbId] = filePath;
            existingMovies[normalizedTitle] = filePath;
            created++;
          }
        } catch (_) {
          skipped++;
        }
      }

      return ImportResult(created: created, updated: updated, skipped: skipped);
    } catch (e) {
      return ImportResult(created: 0, updated: 0, skipped: 0, error: e.toString());
    }
  }

  // ── Private: index builder ────────────────────────────────────────────────

  static Future<Map<String, String>> _buildMovieIndex(String entitiesDirPath) async {
    final index = <String, String>{};
    try {
      final dir = Directory(entitiesDirPath);
      if (!await dir.exists()) return index;

      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          if (split.frontmatter == null) continue;
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml == null) continue;

          final category = yaml['category']?.toString() ?? '';
          if (category.toLowerCase() != 'movies') continue;

          final filePath = entry.path;
          final tmdbId = yaml['tmdb_id']?.toString();
          if (tmdbId != null && tmdbId.isNotEmpty) index[tmdbId] = filePath;

          // Extract H1 title for normalized title index
          final h1 = extractH1(split.body);
          if (h1 != null) index[_normalizeTitle(h1)] = filePath;
        } catch (_) {}
      }
    } catch (_) {}
    return index;
  }

  // ── Private: file builder ─────────────────────────────────────────────────

  static String _buildMovieMarkdown({
    required String alias,
    required String title,
    required double? score,
    required String? watchedDate,
    required String? letterboxdUrl,
    required String? tmdbId,
    required String thoughts,
    required int createdAt,
    required int updatedAt,
  }) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('alias: $alias');
    buf.writeln('category: Movies');
    if (score != null) buf.writeln('score: ${score.toStringAsFixed(1)}');
    if (watchedDate != null && watchedDate.isNotEmpty) buf.writeln('watched_date: $watchedDate');
    if (letterboxdUrl != null && letterboxdUrl.isNotEmpty) buf.writeln('letterboxd_url: $letterboxdUrl');
    if (tmdbId != null && tmdbId.isNotEmpty) buf.writeln('tmdb_id: $tmdbId');
    buf.writeln('created_at: ${msToIso(createdAt)}');
    buf.writeln('updated_at: ${msToIso(updatedAt)}');
    buf.writeln('---');
    buf.writeln('# $title');
    buf.writeln();
    buf.writeln('## Thoughts');
    if (thoughts.isNotEmpty) {
      buf.writeln();
      buf.write(thoughts);
    }
    buf.writeln();
    buf.writeln();
    buf.writeln('## Related');
    buf.writeln();
    buf.writeln('## Sources');
    if (letterboxdUrl != null && letterboxdUrl.isNotEmpty) {
      buf.writeln();
      buf.writeln('- $letterboxdUrl');
    }
    return buf.toString();
  }

  // ── Private: file updater ─────────────────────────────────────────────────

  static Future<void> _updateMovieFile({
    required String filePath,
    required double? score,
    required String? watchedDate,
    required String? letterboxdUrl,
    required String? tmdbId,
    required String thoughts,
    required int updatedAt,
  }) async {
    final content = await File(filePath).readAsString();
    final split = splitFrontmatter(content);
    if (split.frontmatter == null) return;
    final yaml = parseYamlMap(split.frontmatter);
    if (yaml == null) return;

    // Rebuild frontmatter with updated fields (preserve existing values for fields we don't override)
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('alias: ${yaml['alias'] ?? ''}');
    buf.writeln('category: ${yaml['category'] ?? 'Movies'}');

    final newScore = score ?? (yaml['score'] is num ? (yaml['score'] as num).toDouble() : null);
    if (newScore != null) buf.writeln('score: ${newScore.toStringAsFixed(1)}');

    final newWatched = (watchedDate != null && watchedDate.isNotEmpty)
        ? watchedDate
        : yaml['watched_date']?.toString();
    if (newWatched != null && newWatched.isNotEmpty) buf.writeln('watched_date: $newWatched');

    final newLetterboxdUrl = (letterboxdUrl != null && letterboxdUrl.isNotEmpty)
        ? letterboxdUrl
        : yaml['letterboxd_url']?.toString();
    if (newLetterboxdUrl != null && newLetterboxdUrl.isNotEmpty) buf.writeln('letterboxd_url: $newLetterboxdUrl');

    final newTmdbId = (tmdbId != null && tmdbId.isNotEmpty) ? tmdbId : yaml['tmdb_id']?.toString();
    if (newTmdbId != null && newTmdbId.isNotEmpty) buf.writeln('tmdb_id: $newTmdbId');

    final rawTags = yaml['tags'];
    if (rawTags is YamlList && rawTags.isNotEmpty) {
      buf.writeln('tags:');
      for (final t in rawTags) { buf.writeln('  - $t'); }
    }

    buf.writeln('created_at: ${yaml['created_at'] ?? msToIso(updatedAt)}');
    buf.writeln('updated_at: ${msToIso(updatedAt)}');
    buf.write('---');

    // Reconstruct body with updated Thoughts if currently empty
    final sections = parseSectionsH2(split.body);
    final h1 = extractH1(split.body) ?? yaml['alias']?.toString() ?? '';

    final bodyBuf = StringBuffer();
    bodyBuf.writeln('# $h1');

    for (final sectionName in sections.keys) {
      bodyBuf.writeln();
      bodyBuf.writeln('## $sectionName');
      var raw = sections[sectionName]!;
      // Inject thoughts only if section is currently empty
      if (sectionName == 'Thoughts' && raw.trim().isEmpty && thoughts.isNotEmpty) {
        raw = thoughts;
      }
      if (raw.isNotEmpty) {
        bodyBuf.writeln();
        bodyBuf.write(raw);
      }
    }

    // Append Sources entry if letterboxdUrl is new and not already listed
    if (newLetterboxdUrl != null && newLetterboxdUrl.isNotEmpty) {
      final sourcesContent = sections['Sources'] ?? '';
      if (!sourcesContent.contains(newLetterboxdUrl)) {
        if (!sections.containsKey('Sources')) {
          bodyBuf.writeln();
          bodyBuf.writeln('## Sources');
          bodyBuf.writeln();
          bodyBuf.writeln('- $newLetterboxdUrl');
        }
        // If Sources exists but URL not listed, it was already handled above — skip to avoid duplication
        // The existing Sources section was written as-is; we don't patch it further here.
      }
    }

    await File(filePath).writeAsString('${buf.toString()}\n${bodyBuf.toString().trimRight()}\n');
  }

  // ── Private: XML helpers ──────────────────────────────────────────────────

  // Finds the first descendant element matching localName (ignores namespace prefix).
  static String? _elemText(XmlElement element, String localName) {
    try {
      return element.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == localName)
          .firstOrNull
          ?.innerText
          .trim();
    } catch (_) {
      return null;
    }
  }

  // Extracts the href/text from <link> — handles both text nodes and atom:link[@href].
  static String? _extractLink(XmlElement item) {
    try {
      for (final child in item.children.whereType<XmlElement>()) {
        if (child.localName == 'link') {
          final text = child.innerText.trim();
          if (text.isNotEmpty) return text;
          final href = child.getAttribute('href');
          if (href != null && href.isNotEmpty) return href;
        }
      }
      // Letterboxd RSS sometimes puts the URL as a text node sibling of <link/>
      for (final node in item.children.whereType<XmlText>()) {
        final t = node.value.trim();
        if (t.startsWith('http')) return t;
      }
    } catch (_) {}
    return null;
  }

  // Strips year and star rating suffix from RSS <title> to get the film title.
  // e.g. "Interstellar, 2014 - ★★★★½" → "Interstellar"
  static String _extractRssTitle(String rssTitle) {
    var title = rssTitle.trim();
    // Remove trailing star rating block " - ★..."
    title = title.replaceAll(RegExp(r'\s*-\s*[★½]+.*$'), '').trim();
    // Remove trailing ", YYYY"
    title = title.replaceAll(RegExp(r',\s*\d{4}$'), '').trim();
    return title;
  }

  // ── Private: HTML stripper ────────────────────────────────────────────────

  static String _stripHtml(String html) {
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
    // Collapse 3+ consecutive newlines to 2
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  // ── Private: string/path helpers ─────────────────────────────────────────

  static String _normalizeTitle(String title) => title.trim().toLowerCase();

  // Appends -2, -3, etc. to alias until no file with that name exists.
  static String _uniqueAlias(String base, String entitiesDirPath) {
    if (!File(p.join(entitiesDirPath, '$base.md')).existsSync()) return base;
    var n = 2;
    while (File(p.join(entitiesDirPath, '$base-$n.md')).existsSync()) {
      n++;
    }
    return '$base-$n';
  }
}
