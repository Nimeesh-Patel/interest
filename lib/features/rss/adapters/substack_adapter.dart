import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/article.dart';
import '../models/rss_entry.dart';
import '../models/rss_import_result.dart';
import '../services/article_storage_service.dart';
import '../services/rss_utils.dart';
import 'rss_adapter.dart';

class SubstackAdapter implements RssAdapter {
  final String feedId;

  const SubstackAdapter({required this.feedId});

  @override
  Future<ImportResult> ingest(List<RssEntry> entries, String vaultPath) async {
    try {
      final dirPath = VaultService.articlesPath(vaultPath);
      final index = await ArticleStorageService.buildIndex(vaultPath);
      int created = 0, updated = 0, skipped = 0;
      final now = msToIso(DateTime.now().millisecondsSinceEpoch);

      for (final entry in entries) {
        try {
          if (entry.title.trim().isEmpty) {
            skipped++;
            continue;
          }

          final title = entry.title.trim();
          final guid = entry.guid;
          final url = entry.link;
          final author = entry.extras['author'] ?? entry.extras['creator'];
          final publishedAt = _parseDate(entry.pubDate);
          final summary = stripHtml(entry.description ?? '').trim();

          final existingPath =
              index.findPath(guid: guid, url: url, title: title);

          if (existingPath != null) {
            await ArticleStorageService.patchFields(existingPath, {
              if (guid != null) 'guid': guid,
              if (url != null) 'url': url,
              if (author != null) 'author': author,
              if (publishedAt != null) 'published_at': publishedAt,
              'updated_at': now,
            });
            updated++;
          } else {
            final alias =
                ArticleStorageService.uniqueAlias(title, dirPath);
            final article = Article(
              alias: alias,
              title: title,
              feedId: feedId,
              guid: guid,
              url: url,
              author: author,
              publishedAt: publishedAt,
              summary: summary.isNotEmpty ? summary : null,
              createdAt: now,
              updatedAt: now,
            );
            final filePath =
                await ArticleStorageService.createArticle(vaultPath, article);
            index.register(guid, url, title, filePath);
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

  static String? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toIso8601String().substring(0, 10);
    } catch (_) {}
    // RFC 822 dates (common in RSS) — return raw if we can't parse
    return raw;
  }
}
