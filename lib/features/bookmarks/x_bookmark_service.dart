import 'dart:convert';

import 'package:http/http.dart' as http;

class XBookmarkFetchResult {
  final String tweetId;
  final String tweetUrl;
  final String? authorName;
  final String? authorUrl;
  final String? sourceUrl;
  final String? tweetText;

  const XBookmarkFetchResult({
    required this.tweetId,
    required this.tweetUrl,
    this.authorName,
    this.authorUrl,
    this.sourceUrl,
    this.tweetText,
  });
}

class XBookmarkService {
  static final _tweetIdRe = RegExp(r'/status/(\d+)');
  static final _htmlTagRe = RegExp(r'<[^>]*>');

  /// Returns (error, result). On validation failure: (errorString, null).
  /// On network failure: (null, degraded result with nulls). Never throws.
  static Future<(String?, XBookmarkFetchResult?)> fetchMetadata(
      String tweetUrl) async {
    try {
      final uri = Uri.tryParse(tweetUrl.trim());
      if (uri == null) return ('Not a valid X link', null);

      final host = uri.host.toLowerCase();
      if (host != 'x.com' &&
          host != 'twitter.com' &&
          host != 'www.x.com' &&
          host != 'www.twitter.com') {
        return ('Not a valid X link', null);
      }

      final idMatch = _tweetIdRe.firstMatch(uri.path);
      if (idMatch == null) return ('Not a valid X link', null);
      final tweetId = idMatch.group(1)!;

      try {
        final oembedUri = Uri.parse(
          'https://publish.twitter.com/oembed'
          '?url=${Uri.encodeQueryComponent(tweetUrl)}'
          '&omit_script=true',
        );
        final response =
            await http.get(oembedUri).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final authorName = json['author_name'] as String?;
          final authorUrl = json['author_url'] as String?;
          final sourceUrl = json['url'] as String?;
          final html = json['html'] as String?;
          final tweetText = html != null ? _stripHtml(html) : null;
          return (
            null,
            XBookmarkFetchResult(
              tweetId: tweetId,
              tweetUrl: tweetUrl,
              authorName: authorName,
              authorUrl: authorUrl,
              sourceUrl: sourceUrl,
              tweetText: tweetText,
            ),
          );
        }
      } catch (_) {
        // degraded — network unavailable or oEmbed down
      }

      return (
        null,
        XBookmarkFetchResult(tweetId: tweetId, tweetUrl: tweetUrl),
      );
    } catch (_) {
      return (null, null);
    }
  }

  static String _stripHtml(String html) {
    var text = html.replaceAll(_htmlTagRe, '');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&rsquo;', '’')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”');
    return text.trim();
  }
}
