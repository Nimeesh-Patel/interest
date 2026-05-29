import 'dart:convert';

import 'package:http/http.dart' as http;

class XBookmarkFetchResult {
  final String tweetId;
  final String tweetUrl;
  final String? authorName;
  final String? authorUrl;
  final String? sourceUrl;
  final String? tweetText;
  // false = full text via nitter or syndication; true = oEmbed fallback or degraded
  final bool truncated;

  const XBookmarkFetchResult({
    required this.tweetId,
    required this.tweetUrl,
    this.authorName,
    this.authorUrl,
    this.sourceUrl,
    this.tweetText,
    this.truncated = false,
  });
}

class XBookmarkService {
  static final _tweetIdRe = RegExp(r'/status/(\d+)');
  static final _htmlTagRe = RegExp(r'<[^>]*>');
  static final _screenNameRe = RegExp(r'/([^/]+)/status/\d+');
  static final _nitterBodyRe = RegExp(
    r'class="tweet-content media-body"[^>]*>(.*?)</div>',
    dotAll: true,
  );
  static final _nitterFullnameRe =
      RegExp(r'<a class="fullname"[^>]*>([^<]+)</a>');
  static final _attributionTailRe = RegExp(
    r'\s*—\s+[^\n]+\(@[^\)]+\)[^\n]*\d{4}[^\n]*\s*$',
  );

  static const _nitterInstances = [
    'nitter.net',
    'nitter.privacydev.net',
    'nitter.poast.org',
  ];

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

      final screenMatch = _screenNameRe.firstMatch(uri.path);
      final screenName = screenMatch?.group(1);

      // Step 1: nitter — returns full untruncated text
      if (screenName != null) {
        for (final instance in _nitterInstances) {
          try {
            final nitterUri =
                Uri.parse('https://$instance/$screenName/status/$tweetId');
            final response =
                await http.get(nitterUri).timeout(const Duration(seconds: 8));
            if (response.statusCode == 200) {
              final bodyMatch = _nitterBodyRe.firstMatch(response.body);
              if (bodyMatch != null) {
                final tweetText =
                    _cleanBody(_stripHtml(bodyMatch.group(1)!));
                if (tweetText.isNotEmpty) {
                  final fullnameMatch =
                      _nitterFullnameRe.firstMatch(response.body);
                  final authorName =
                      fullnameMatch?.group(1)?.trim() ?? screenName;
                  return (
                    null,
                    XBookmarkFetchResult(
                      tweetId: tweetId,
                      tweetUrl: tweetUrl,
                      authorName: authorName,
                      authorUrl: 'https://twitter.com/$screenName',
                      sourceUrl: tweetUrl,
                      tweetText: tweetText,
                      truncated: false,
                    ),
                  );
                }
              }
            }
          } catch (_) {}
        }
      }

      // Step 2: syndication API — returns full text
      try {
        final syndUri = Uri.parse(
            'https://cdn.syndication.twimg.com/tweet-result?id=$tweetId');
        final syndResponse =
            await http.get(syndUri).timeout(const Duration(seconds: 8));
        if (syndResponse.statusCode == 200) {
          final json = jsonDecode(syndResponse.body) as Map<String, dynamic>;
          final text = json['text'] as String?;
          final user = json['user'] as Map<String, dynamic>?;
          if (text != null && user != null) {
            final authorName = user['name'] as String?;
            final screen = user['screen_name'] as String?;
            final authorUrl =
                screen != null ? 'https://twitter.com/$screen' : null;
            return (
              null,
              XBookmarkFetchResult(
                tweetId: tweetId,
                tweetUrl: tweetUrl,
                authorName: authorName,
                authorUrl: authorUrl,
                sourceUrl: tweetUrl,
                tweetText: _cleanBody(text),
                truncated: false,
              ),
            );
          }
        }
      } catch (_) {}

      // Step 3: oEmbed fallback — may be truncated
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
          final rawText = html != null ? _stripHtml(html) : null;
          return (
            null,
            XBookmarkFetchResult(
              tweetId: tweetId,
              tweetUrl: tweetUrl,
              authorName: authorName,
              authorUrl: authorUrl,
              sourceUrl: sourceUrl,
              tweetText: rawText != null ? _cleanBody(rawText) : null,
              truncated: true,
            ),
          );
        }
      } catch (_) {}

      // Step 4: all failed — URL and timestamp only
      return (
        null,
        XBookmarkFetchResult(
            tweetId: tweetId, tweetUrl: tweetUrl, truncated: true),
      );
    } catch (_) {
      return (null, null);
    }
  }

  static String _cleanBody(String text) =>
      text.replaceFirst(_attributionTailRe, '').trimRight();

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
