import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../models/rss_entry.dart';
import '../models/rss_import_result.dart';
import '../services/rss_utils.dart';
import 'rss_adapter.dart';

class LetterboxdAdapter implements RssAdapter {
  const LetterboxdAdapter();

  @override
  Future<ImportResult> ingest(List<RssEntry> entries, String vaultPath) async {
    try {
      final existingMovies = await _buildMovieIndex(vaultPath);
      int created = 0, updated = 0, skipped = 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final entry in entries) {
        try {
          final filmTitle = entry.extras['filmTitle'] ??
              _extractRssTitle(entry.title);
          if (filmTitle.isEmpty) {
            skipped++;
            continue;
          }

          final watchedDate = entry.extras['watchedDate'];
          final ratingStr = entry.extras['memberRating'];
          final score =
              ratingStr != null ? (double.tryParse(ratingStr) ?? 0) * 2.0 : null;
          final tmdbId = entry.extras['movieId'];
          final letterboxdUrl =
              entry.link ?? entry.extras['_textNodeUrl'];
          final thoughts = stripHtml(entry.description ?? '').trim();

          final normalizedTitle = normalizeTitle(filmTitle);
          final existingPath =
              (tmdbId != null ? existingMovies[tmdbId] : null) ??
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
            alias = _uniqueAlias(alias, vaultPath);

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
            final filePath = p.join(vaultPath, filename);
            await File(filePath).writeAsString(content);

            if (tmdbId != null && tmdbId.isNotEmpty) {
              existingMovies[tmdbId] = filePath;
            }
            existingMovies[normalizedTitle] = filePath;
            created++;
          }
        } catch (_) {
          skipped++;
        }
      }

      return ImportResult(created: created, updated: updated, skipped: skipped);
    } catch (e) {
      return ImportResult(
          created: 0, updated: 0, skipped: 0, error: e.toString());
    }
  }

  // ── Index builder ─────────────────────────────────────────────────────────

  static Future<Map<String, String>> _buildMovieIndex(
      String entitiesDirPath) async {
    final index = <String, String>{};
    try {
      await for (final entry in VaultScanner.scan(
        entitiesDirPath,
        recursive: false,
      )) {
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          if (split.frontmatter == null) continue;
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml == null) continue;

          final category = yaml['category']?.toString() ?? '';
          if (category.toLowerCase() != 'movies') continue;

          final tmdbId = yaml['tmdb_id']?.toString();
          if (tmdbId != null && tmdbId.isNotEmpty) {
            index[tmdbId] = entry.path;
          }

          final h1 = extractH1(split.body);
          if (h1 != null) index[normalizeTitle(h1)] = entry.path;
        } catch (_) {}
      }
    } catch (_) {}
    return index;
  }

  static const _knownOrder = [
    'alias', 'category', 'score', 'watched_date', 'letterboxd_url',
    'tmdb_id', 'created_at', 'updated_at',
  ];

  // ── File builder ──────────────────────────────────────────────────────────

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
    final fields = <String, dynamic>{
      'alias': alias,
      'category': 'Movies',
      if (score != null) 'score': score.toStringAsFixed(1),
      if (watchedDate != null && watchedDate.isNotEmpty) 'watched_date': watchedDate,
      if (letterboxdUrl != null && letterboxdUrl.isNotEmpty) 'letterboxd_url': letterboxdUrl,
      if (tmdbId != null && tmdbId.isNotEmpty) 'tmdb_id': tmdbId,
      'created_at': msToIso(createdAt),
      'updated_at': msToIso(updatedAt),
    };
    final buf = StringBuffer();
    buf.writeln(buildFrontmatterBlock(fields, _knownOrder));
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

  // ── File updater ──────────────────────────────────────────────────────────

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

    final newScore =
        score ?? (yaml['score'] is num ? (yaml['score'] as num).toDouble() : null);
    final newWatched = (watchedDate != null && watchedDate.isNotEmpty)
        ? watchedDate
        : yaml['watched_date']?.toString();
    final newLetterboxdUrl = (letterboxdUrl != null && letterboxdUrl.isNotEmpty)
        ? letterboxdUrl
        : yaml['letterboxd_url']?.toString();
    final newTmdbId = (tmdbId != null && tmdbId.isNotEmpty)
        ? tmdbId
        : yaml['tmdb_id']?.toString();
    final rawTags = yaml['tags'];
    final tags = (rawTags is YamlList && rawTags.isNotEmpty)
        ? rawTags.map((t) => t.toString()).toList()
        : null;

    final fields = <String, dynamic>{
      'alias': yaml['alias'] ?? '',
      'category': yaml['category'] ?? 'Movies',
      if (newScore != null) 'score': newScore.toStringAsFixed(1),
      if (newWatched != null && newWatched.isNotEmpty) 'watched_date': newWatched,
      if (newLetterboxdUrl != null && newLetterboxdUrl.isNotEmpty)
        'letterboxd_url': newLetterboxdUrl,
      if (newTmdbId != null && newTmdbId.isNotEmpty) 'tmdb_id': newTmdbId,
      if (tags != null) 'tags': tags,
      'created_at': yaml['created_at']?.toString() ?? msToIso(updatedAt),
      'updated_at': msToIso(updatedAt),
    };
    const knownOrder = [
      'alias', 'category', 'score', 'watched_date', 'letterboxd_url',
      'tmdb_id', 'tags', 'created_at', 'updated_at',
    ];
    final buf = StringBuffer(buildFrontmatterBlock(fields, knownOrder));

    final sections = parseSectionsH2(split.body);
    final h1 = extractH1(split.body) ?? yaml['alias']?.toString() ?? '';

    final bodyBuf = StringBuffer();
    bodyBuf.writeln('# $h1');

    for (final sectionName in sections.keys) {
      bodyBuf.writeln();
      bodyBuf.writeln('## $sectionName');
      var raw = sections[sectionName]!;
      if (sectionName == 'Thoughts' && raw.trim().isEmpty && thoughts.isNotEmpty) {
        raw = thoughts;
      }
      if (raw.isNotEmpty) {
        bodyBuf.writeln();
        bodyBuf.write(raw);
      }
    }

    if (newLetterboxdUrl != null && newLetterboxdUrl.isNotEmpty) {
      final sourcesContent = sections['Sources'] ?? '';
      if (!sections.containsKey('Sources') &&
          !sourcesContent.contains(newLetterboxdUrl)) {
        bodyBuf.writeln();
        bodyBuf.writeln('## Sources');
        bodyBuf.writeln();
        bodyBuf.writeln('- $newLetterboxdUrl');
      }
    }

    await File(filePath).writeAsString(
        '${buf.toString()}\n${bodyBuf.toString().trimRight()}\n');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _extractRssTitle(String rssTitle) {
    var title = rssTitle.trim();
    title = title.replaceAll(RegExp(r'\s*-\s*[★½]+.*$'), '').trim();
    title = title.replaceAll(RegExp(r',\s*\d{4}$'), '').trim();
    return title;
  }

  static String _uniqueAlias(String base, String dirPath) {
    if (!File(p.join(dirPath, '$base.md')).existsSync()) return base;
    var n = 2;
    while (File(p.join(dirPath, '$base-$n.md')).existsSync()) {
      n++;
    }
    return '$base-$n';
  }
}
