import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/rss_entry.dart';

class RssFetchService {
  static const _standardFields = {'guid', 'title', 'link', 'pubDate', 'description'};

  // Returns (entries, errorString). Null entries means the fetch/parse failed.
  static Future<(List<RssEntry>?, String?)> fetch(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return (null, 'HTTP ${response.statusCode}');
      }

      final XmlDocument document;
      try {
        document = XmlDocument.parse(response.body);
      } catch (_) {
        return (null, 'Failed to parse RSS feed');
      }

      final entries = <RssEntry>[];
      for (final item in document.findAllElements('item')) {
        try {
          entries.add(_parseItem(item));
        } catch (_) {}
      }
      return (entries, null);
    } catch (e) {
      return (null, e.toString());
    }
  }

  static RssEntry _parseItem(XmlElement item) {
    String? guid;
    String title = '';
    String? link;
    String? pubDate;
    String? description;
    final extras = <String, String>{};

    for (final child in item.children.whereType<XmlElement>()) {
      final name = child.localName;
      final text = child.innerText.trim();
      switch (name) {
        case 'guid':
          guid = text.isNotEmpty ? text : null;
        case 'title':
          title = text;
        case 'link':
          // <link> is sometimes empty text with an href attribute (Atom-style)
          if (text.isNotEmpty) {
            link = text;
          } else {
            final href = child.getAttribute('href');
            if (href != null && href.isNotEmpty) link = href;
          }
          // Also check Letterboxd-style text-node siblings (handled in adapter)
        case 'pubDate':
          pubDate = text.isNotEmpty ? text : null;
        case 'description':
          description = text.isNotEmpty ? text : null;
      }
      // Populate extras for all elements (including the standard ones — adapters
      // may want them too, e.g. filmTitle overriding title).
      if (text.isNotEmpty && !_standardFields.contains(name)) {
        extras[name] = text;
      }
    }

    // Letterboxd puts the URL as a raw text node sibling of <link/> — capture it here
    // so the LetterboxdAdapter can find it in extras under a sentinel key.
    if (link == null) {
      for (final node in item.children.whereType<XmlText>()) {
        final t = node.value.trim();
        if (t.startsWith('http')) {
          extras['_textNodeUrl'] = t;
          break;
        }
      }
    }

    return RssEntry(
      guid: guid,
      title: title,
      link: link,
      pubDate: pubDate,
      description: description,
      extras: extras,
    );
  }
}
