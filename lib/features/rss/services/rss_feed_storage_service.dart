import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/markdown/md_utils.dart';
import '../models/rss_feed.dart';

class RssFeedStorageService {
  static const _feedsKey = 'rss_feeds';
  static const _legacyLetterboxdKey = 'letterboxd_rss_url';

  static Future<List<RssFeed>> loadFeeds() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Migrate from the old single-feed letterboxd_rss_url key.
      if (!prefs.containsKey(_feedsKey)) {
        final legacyUrl = prefs.getString(_legacyLetterboxdKey);
        if (legacyUrl != null && legacyUrl.isNotEmpty) {
          final migrated = [
            RssFeed(
              id: 'letterboxd-default',
              name: 'Letterboxd',
              url: legacyUrl,
              type: RssFeedType.letterboxd,
            ),
          ];
          await _persist(prefs, migrated);
          await prefs.remove(_legacyLetterboxdKey);
          return migrated;
        }
        return [];
      }

      final raw = prefs.getString(_feedsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(RssFeed.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveFeeds(List<RssFeed> feeds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persist(prefs, feeds);
    } catch (_) {}
  }

  static Future<void> addFeed(RssFeed feed) async {
    final feeds = await loadFeeds();
    feeds.add(feed);
    await saveFeeds(feeds);
  }

  static Future<void> removeFeed(String id) async {
    final feeds = await loadFeeds();
    feeds.removeWhere((f) => f.id == id);
    await saveFeeds(feeds);
  }

  static Future<void> updateFeed(RssFeed updated) async {
    final feeds = await loadFeeds();
    final idx = feeds.indexWhere((f) => f.id == updated.id);
    if (idx != -1) feeds[idx] = updated;
    await saveFeeds(feeds);
  }

  /// Generates a stable unique ID for a new feed.
  static String generateId(String name) {
    final slug = slugify(name);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return slug.isNotEmpty ? '$slug-$ts' : 'feed-$ts';
  }

  static Future<void> _persist(
      SharedPreferences prefs, List<RssFeed> feeds) async {
    await prefs.setString(
        _feedsKey, jsonEncode(feeds.map((f) => f.toJson()).toList()));
  }
}
