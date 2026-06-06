import '../adapters/generic_adapter.dart';
import '../adapters/letterboxd_adapter.dart';
import '../adapters/rss_adapter.dart';
import '../adapters/substack_adapter.dart';
import '../models/rss_feed.dart';
import '../models/rss_import_result.dart';
import 'rss_fetch_service.dart';

class RssIngestionService {
  static Future<ImportResult> ingestFeed(
      RssFeed feed, String vaultPath) async {
    try {
      final (entries, error) = await RssFetchService.fetch(feed.url);
      if (error != null) {
        return ImportResult(created: 0, updated: 0, skipped: 0, error: error);
      }
      final adapter = _adapterFor(feed);
      return adapter.ingest(entries!, vaultPath);
    } catch (e) {
      return ImportResult(
          created: 0, updated: 0, skipped: 0, error: e.toString());
    }
  }

  static RssAdapter _adapterFor(RssFeed feed) => switch (feed.type) {
        RssFeedType.letterboxd => LetterboxdAdapter(feedId: feed.id),
        RssFeedType.substack => SubstackAdapter(feedId: feed.id),
        RssFeedType.generic => GenericAdapter(feedId: feed.id),
      };
}
