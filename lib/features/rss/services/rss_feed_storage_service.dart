import '../../../core/integrations_config_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/rss_feed.dart';

class RssFeedStorageService {
  static Future<List<RssFeed>> loadFeeds(String vaultPath) async {
    try {
      final raw = await IntegrationsConfigService.getRssFeeds(vaultPath);
      return raw.map(RssFeed.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveFeeds(String vaultPath, List<RssFeed> feeds) async {
    await IntegrationsConfigService.setRssFeeds(
      vaultPath,
      feeds.map((f) => f.toJson()).toList(),
    );
  }

  static Future<void> addFeed(String vaultPath, RssFeed feed) async {
    final feeds = await loadFeeds(vaultPath);
    feeds.add(feed);
    await saveFeeds(vaultPath, feeds);
  }

  static Future<void> removeFeed(String vaultPath, String id) async {
    final feeds = await loadFeeds(vaultPath);
    feeds.removeWhere((f) => f.id == id);
    await saveFeeds(vaultPath, feeds);
  }

  static Future<void> updateFeed(String vaultPath, RssFeed updated) async {
    final feeds = await loadFeeds(vaultPath);
    final idx = feeds.indexWhere((f) => f.id == updated.id);
    if (idx != -1) feeds[idx] = updated;
    await saveFeeds(vaultPath, feeds);
  }

  static String generateId(String name) {
    final slug = slugify(name);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return slug.isNotEmpty ? '$slug-$ts' : 'feed-$ts';
  }
}
