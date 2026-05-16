import 'dart:convert';
import 'package:http/http.dart' as http;

class GrokipediaArticle {
  final String title;
  final String slug;
  final String? snippet;

  const GrokipediaArticle({
    required this.title,
    required this.slug,
    this.snippet,
  });

  String get webUrl => 'https://grokipedia.com/page/$slug';
}

class GrokipediaService {
  static const String _baseUrl = 'https://grokipedia.com';
  static const Duration _timeout = Duration(seconds: 10);

  // Returns first search match for entityName, or null on failure / no results.
  // Endpoint: GET /api/full-text-search?query=...&limit=5
  static Future<GrokipediaArticle?> findArticle(String entityName) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/full-text-search').replace(
        queryParameters: {'query': entityName, 'limit': '5'},
      );
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final title = first['title'] as String?;
      final slug = first['slug'] as String?;
      if (title == null || slug == null) return null;

      return GrokipediaArticle(
        title: title,
        slug: slug,
        snippet: first['snippet'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // Fetches truncated page content when the search snippet is absent.
  // Endpoint: GET /api/page?slug=...&includeContent=true
  // Response: { "found": bool, "page": { "content": str, ... } }
  // Returns null on any failure.
  static Future<String?> fetchPageSummary(String slug) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/page').replace(
        queryParameters: {'slug': slug, 'includeContent': 'true'},
      );
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['found'] != true) return null;

      final page = data['page'] as Map<String, dynamic>?;
      if (page == null) return null;

      final content = page['content'] as String?;
      if (content == null || content.isEmpty) return null;

      return content.length > 600 ? '${content.substring(0, 600)}…' : content;
    } catch (_) {
      return null;
    }
  }
}
