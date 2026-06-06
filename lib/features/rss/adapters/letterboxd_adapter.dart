import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/article.dart';
import '../models/rss_entry.dart';
import '../models/rss_import_result.dart';
import '../services/article_storage_service.dart';
import 'rss_adapter.dart';

class LetterboxdAdapter implements RssAdapter {
  final String feedId;

  const LetterboxdAdapter({required this.feedId});

  @override
  Future<ImportResult> ingest(List<RssEntry> entries, String vaultPath) async {
    try {
      final dirPath = VaultService.articlesPath(vaultPath);
      final index = await ArticleStorageService.buildIndex(vaultPath);
      int created = 0, updated = 0, skipped = 0;
      final now = msToIso(DateTime.now().millisecondsSinceEpoch);

      for (final entry in entries) {
        try {
          final filmTitle =
              entry.extras['filmTitle'] ?? _extractRssTitle(entry.title);
          if (filmTitle.trim().isEmpty) {
            skipped++;
            continue;
          }

          final watchedDate = entry.extras['watchedDate'];
          final thoughts = stripHtml(entry.description ?? '').trim();
          final url = entry.link ?? entry.extras['_textNodeUrl'];

          final existingPath =
              index.findPath(guid: entry.guid, url: url, title: filmTitle);

          if (existingPath != null) {
            await ArticleStorageService.patchFields(existingPath, {
              if (url != null) 'url': url,
              if (watchedDate != null) 'published_at': watchedDate,
              'updated_at': now,
            });
            updated++;
          } else {
            final alias =
                ArticleStorageService.uniqueAlias(filmTitle, dirPath);
            final article = Article(
              alias: alias,
              title: filmTitle,
              feedId: feedId,
              guid: entry.guid,
              url: url,
              publishedAt: watchedDate ?? entry.pubDate,
              summary: thoughts.isNotEmpty ? thoughts : null,
              createdAt: now,
              updatedAt: now,
            );
            final filePath =
                await ArticleStorageService.createArticle(vaultPath, article);
            index.register(entry.guid, url, filmTitle, filePath);
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _extractRssTitle(String rssTitle) {
    var title = rssTitle.trim();
    title = title.replaceAll(RegExp(r'\s*-\s*[★½]+.*$'), '').trim();
    title = title.replaceAll(RegExp(r',\s*\d{4}$'), '').trim();
    return title;
  }
}
