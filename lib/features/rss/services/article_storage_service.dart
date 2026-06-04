import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/article.dart';

/// In-memory deduplication index built once per import run.
/// Adapters call [buildIndex] before iterating entries, then [register] after
/// each new file is created so subsequent entries in the same run don't collide.
class ArticleIndex {
  final Map<String, String> _byGuid = {};
  final Map<String, String> _byUrl = {};
  final Map<String, String> _byTitle = {};

  void _load(String? guid, String? url, String? title, String filePath) {
    if (guid != null && guid.isNotEmpty) _byGuid[guid] = filePath;
    if (url != null && url.isNotEmpty) _byUrl[_normalizeUrl(url)] = filePath;
    if (title != null && title.isNotEmpty) {
      _byTitle[title.trim().toLowerCase()] = filePath;
    }
  }

  /// Returns the existing file path, checking in priority order: guid > url > title.
  String? findPath({String? guid, String? url, String? title}) {
    if (guid != null && guid.isNotEmpty) {
      final hit = _byGuid[guid];
      if (hit != null) return hit;
    }
    if (url != null && url.isNotEmpty) {
      final hit = _byUrl[_normalizeUrl(url)];
      if (hit != null) return hit;
    }
    if (title != null && title.isNotEmpty) {
      final hit = _byTitle[title.trim().toLowerCase()];
      if (hit != null) return hit;
    }
    return null;
  }

  /// Call after creating a new file so within-run duplicates are detected.
  void register(String? guid, String? url, String? title, String filePath) {
    _load(guid, url, title, filePath);
  }

  static String _normalizeUrl(String url) => url.trim().toLowerCase();
}

class ArticleStorageService {
  static const _articleKnownOrder = [
    'type', 'alias', 'feed_id', 'guid', 'url',
    'author', 'published_at', 'created_at', 'updated_at',
  ];

  // ── Index ─────────────────────────────────────────────────────────────────

  static Future<ArticleIndex> buildIndex(String vaultPath) async {
    final index = ArticleIndex();
    try {
      final dir = Directory(VaultService.articlesPath(vaultPath));
      if (!await dir.exists()) return index;

      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          if (split.frontmatter == null) continue;
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml == null) continue;
          if (yaml['type']?.toString() != 'article') continue;

          final guid = yaml['guid']?.toString();
          final url = yaml['url']?.toString();
          final h1 = extractH1(split.body);
          index._load(guid, url, h1, entry.path);
        } catch (_) {}
      }
    } catch (_) {}
    return index;
  }

  // ── Patch ─────────────────────────────────────────────────────────────────

  static Future<void> patchFields(
      String filePath, Map<String, dynamic> updates) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final split = splitFrontmatter(content);
      if (split.frontmatter == null) return;
      final yaml = parseYamlMap(split.frontmatter);
      if (yaml == null) return;

      final merged = Map<String, dynamic>.from(yaml);
      merged.addAll(updates);

      final newContent =
          '${buildFrontmatterBlock(merged, _articleKnownOrder)}\n${split.body}';
      await file.writeAsString(newContent);
    } catch (_) {}
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Creates a new article file and returns its path.
  static Future<String> createArticle(
      String vaultPath, Article article) async {
    final dir = Directory(VaultService.articlesPath(vaultPath));
    await dir.create(recursive: true);

    final filename =
        '${sanitizeFilename(article.title.isNotEmpty ? article.title : article.alias)}.md';
    final filePath = p.join(dir.path, filename);
    await File(filePath).writeAsString(_buildContent(article));
    return filePath;
  }

  // ── Alias generation ──────────────────────────────────────────────────────

  static String uniqueAlias(String title, String dirPath) {
    final dir = Directory(dirPath);
    final existing = dir.existsSync()
        ? dir.listSync().whereType<File>()
            .map((f) => p.basenameWithoutExtension(f.path))
            .toSet()
        : <String>{};
    return generateUniqueId(title, existing, fallback: 'article');
  }

  // ── Builders ──────────────────────────────────────────────────────────────

  static String _buildContent(Article article) {
    final fields = <String, dynamic>{
      'type': 'article',
      'alias': article.alias,
      if (article.feedId?.isNotEmpty == true) 'feed_id': article.feedId,
      if (article.guid?.isNotEmpty == true) 'guid': article.guid,
      if (article.url?.isNotEmpty == true) 'url': article.url,
      if (article.author?.isNotEmpty == true) 'author': article.author,
      if (article.publishedAt?.isNotEmpty == true) 'published_at': article.publishedAt,
      'created_at': article.createdAt,
      'updated_at': article.updatedAt,
    };
    final buf = StringBuffer();
    buf.writeln(buildFrontmatterBlock(fields, _articleKnownOrder));
    buf.writeln('# ${article.title}');
    buf.writeln();
    buf.writeln('## Summary');
    if (article.summary?.isNotEmpty == true) {
      buf.writeln();
      buf.write(article.summary);
    }
    buf.writeln();
    buf.writeln();
    buf.writeln('## Sources');
    if (article.url?.isNotEmpty == true) {
      buf.writeln();
      buf.writeln('- ${article.url}');
    }
    return buf.toString();
  }

}
