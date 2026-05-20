import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../entities/services/letterboxd_service.dart' show ImportResult;
import '../models/readwise_book.dart';
import '../models/readwise_highlight.dart';

class ReadwiseService {
  static const _tokenKey = 'readwise_access_token';
  static const _apiBase = 'https://readwise.io/api/v2';

  // ── Token storage ─────────────────────────────────────────────────────────

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ── API: fetch books (paginated) ──────────────────────────────────────────

  static Future<List<ReadwiseBook>?> fetchBooks(String token) async {
    final books = <ReadwiseBook>[];
    String? nextUrl = '$_apiBase/books/?page_size=1000';
    try {
      while (nextUrl != null) {
        final response = await http
            .get(Uri.parse(nextUrl),
                headers: {'Authorization': 'Token $token'})
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        for (final item in json['results'] as List) {
          books.add(ReadwiseBook.fromJson(item as Map<String, dynamic>));
        }
        nextUrl = json['next'] as String?;
      }
      return books;
    } catch (_) {
      return null;
    }
  }

  // ── API: fetch highlights for one book (paginated) ────────────────────────

  static Future<List<ReadwiseHighlight>?> fetchHighlights(
      String token, int bookId) async {
    final highlights = <ReadwiseHighlight>[];
    String? nextUrl = '$_apiBase/highlights/?book_id=$bookId&page_size=1000';
    try {
      while (nextUrl != null) {
        final response = await http
            .get(Uri.parse(nextUrl),
                headers: {'Authorization': 'Token $token'})
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        for (final item in json['results'] as List) {
          highlights
              .add(ReadwiseHighlight.fromJson(item as Map<String, dynamic>));
        }
        nextUrl = json['next'] as String?;
      }
      return highlights;
    } catch (_) {
      return null;
    }
  }

  // ── Import: write or patch book file ─────────────────────────────────────

  static Future<ImportResult> importBook(
    ReadwiseBook book,
    List<ReadwiseHighlight> highlights,
    String vaultPath,
  ) async {
    try {
      final booksDirPath = VaultService.booksPath(vaultPath);
      await Directory(booksDirPath).create(recursive: true);

      final title = book.title.isNotEmpty ? book.title : 'Book ${book.id}';
      final filename = '${sanitizeFilename(title)}.md';
      final filePath = p.join(booksDirPath, filename);
      final file = File(filePath);

      if (await file.exists()) {
        final existing = await file.readAsString();
        final patched = _patchBookFile(existing, book, highlights);
        await file.writeAsString(patched);
        return const ImportResult(created: 0, updated: 1, skipped: 0);
      } else {
        final content = _buildBookMarkdown(book, highlights);
        await file.writeAsString(content);
        return const ImportResult(created: 1, updated: 0, skipped: 0);
      }
    } catch (e) {
      return ImportResult(
          created: 0, updated: 0, skipped: 0, error: e.toString());
    }
  }

  // ── Private: build new book file ──────────────────────────────────────────

  static String _buildBookMarkdown(
      ReadwiseBook book, List<ReadwiseHighlight> highlights) {
    final now = DateTime.now().toUtc().toIso8601String();
    final title = book.title.isNotEmpty ? book.title : 'Book ${book.id}';
    final buf = StringBuffer();

    buf.writeln(_buildFrontmatter(book, now));
    buf.writeln('# $title');
    if (book.author.isNotEmpty) {
      buf.writeln();
      buf.writeln('*${book.author}*');
    }
    buf.writeln();
    buf.writeln('## Highlights');
    buf.writeln();

    if (highlights.isEmpty) {
      buf.writeln('*No highlights imported.*');
    } else {
      for (final h in highlights) {
        buf.write(_buildHighlightBlock(h));
      }
    }

    return buf.toString().trimRight() + '\n';
  }

  // ── Private: patch existing book file ────────────────────────────────────

  static String _patchBookFile(
    String existing,
    ReadwiseBook book,
    List<ReadwiseHighlight> highlights,
  ) {
    final split = splitFrontmatter(existing);
    if (split.frontmatter == null) return _buildBookMarkdown(book, highlights);
    final yaml = parseYamlMap(split.frontmatter);
    if (yaml == null) return _buildBookMarkdown(book, highlights);

    // Collect IDs already in the file
    final existingIds = <int>{};
    for (final match in RegExp(r'\^rw(\d+)').allMatches(existing)) {
      final id = int.tryParse(match.group(1)!);
      if (id != null) existingIds.add(id);
    }
    final newHighlights =
        highlights.where((h) => !existingIds.contains(h.id)).toList();

    final now = DateTime.now().toUtc().toIso8601String();
    final frontmatter = _buildFrontmatter(book, now);
    final sections = parseSectionsH2(split.body);
    final h1 =
        extractH1(split.body) ?? (book.title.isNotEmpty ? book.title : 'Book ${book.id}');
    final preamble = _extractPreamble(split.body);

    final buf = StringBuffer();
    buf.writeln(frontmatter);
    buf.writeln('# $h1');

    if (preamble.isNotEmpty) {
      buf.writeln();
      buf.writeln(preamble);
    }

    // If no H2 sections exist yet, add Highlights directly
    if (sections.isEmpty) {
      buf.writeln();
      buf.writeln('## Highlights');
      buf.writeln();
      for (final h in (newHighlights.isNotEmpty ? newHighlights : highlights)) {
        buf.write(_buildHighlightBlock(h));
      }
      return buf.toString().trimRight() + '\n';
    }

    for (final entry in sections.entries) {
      buf.writeln();
      buf.writeln('## ${entry.key}');
      if (entry.key == 'Highlights') {
        final existing = entry.value; // trimRight()'ed by parseSectionsH2
        if (existing.isNotEmpty) {
          buf.writeln();
          buf.write(existing);
          buf.writeln();
        }
        if (newHighlights.isNotEmpty) {
          if (existing.isEmpty) buf.writeln();
          for (final h in newHighlights) {
            buf.write(_buildHighlightBlock(h));
          }
        } else if (existing.isEmpty) {
          buf.writeln();
          buf.writeln('*No highlights imported.*');
        }
      } else {
        if (entry.value.isNotEmpty) {
          buf.writeln();
          buf.write(entry.value);
          buf.writeln();
        }
      }
    }

    // Add Highlights section if it didn't exist yet but we have highlights
    if (!sections.containsKey('Highlights') && highlights.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Highlights');
      buf.writeln();
      for (final h in highlights) {
        buf.write(_buildHighlightBlock(h));
      }
    }

    return buf.toString().trimRight() + '\n';
  }

  // ── Private: frontmatter builder ──────────────────────────────────────────

  static String _buildFrontmatter(ReadwiseBook book, String updatedAt) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('type: book_highlights');
    buf.writeln('source: readwise');
    buf.writeln('title: ${_yamlValue(book.title.isNotEmpty ? book.title : 'Book ${book.id}')}');
    buf.writeln('author: ${_yamlValue(book.author)}');
    buf.writeln('readwise_id: ${book.id}');
    buf.writeln('readwise_category: ${book.category}');
    buf.writeln('num_highlights: ${book.numHighlights}');
    if (book.lastHighlightAt != null && book.lastHighlightAt!.isNotEmpty) {
      buf.writeln('last_highlight_at: ${book.lastHighlightAt}');
    }
    buf.writeln('updated_at: $updatedAt');
    buf.write('---');
    return buf.toString();
  }

  // ── Private: highlight block builder ─────────────────────────────────────

  static String _buildHighlightBlock(ReadwiseHighlight h) {
    final buf = StringBuffer();

    // Blockquote — handle multi-line text
    for (final line in h.text.trim().split('\n')) {
      buf.writeln('> $line');
    }
    buf.writeln();

    // Optional note
    if (h.note != null && h.note!.trim().isNotEmpty) {
      buf.writeln('**Note:** ${h.note!.trim()}');
      buf.writeln();
    }

    // Block ID (Obsidian-compatible, used for deduplication on re-import)
    buf.writeln('^rw${h.id}');

    // Metadata line
    final meta = StringBuffer();
    if (h.location != null && h.location!.isNotEmpty) {
      meta.write('Location: ${h.location}');
    }
    if (h.tags.isNotEmpty) {
      if (meta.isNotEmpty) meta.write(' · ');
      meta.write('Tags: ${h.tags.join(', ')}');
    }
    if (meta.isNotEmpty) buf.writeln(meta.toString());

    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    return buf.toString();
  }

  // ── Private: extract preamble (content between H1 and first H2) ──────────

  static String _extractPreamble(String body) {
    final lines = body.split('\n');
    final result = <String>[];
    bool pastH1 = false;
    for (final line in lines) {
      final t = line.trimLeft();
      if (!pastH1 && t.startsWith('# ') && !t.startsWith('## ')) {
        pastH1 = true;
        continue;
      }
      if (!pastH1) continue;
      if (t.startsWith('## ')) break;
      result.add(line);
    }
    return result.join('\n').trim();
  }

  // ── Private: YAML value quoting ───────────────────────────────────────────

  // Quotes values that contain YAML-special sequences (colon-space, hash, etc.)
  static String _yamlValue(String value) {
    if (value.isEmpty) return '""';
    if (value.contains(': ') ||
        value.contains(' #') ||
        value.startsWith('"') ||
        value.startsWith("'") ||
        value.startsWith('[') ||
        value.startsWith('{')) {
      return '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }
    return value;
  }
}
