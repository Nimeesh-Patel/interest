import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../books/models/book.dart';
import '../../books/services/book_storage_service.dart';
import '../../rss/models/rss_import_result.dart';
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
    ReadwiseBook rwBook,
    List<ReadwiseHighlight> highlights,
    String vaultPath,
  ) async {
    try {
      await Directory(VaultService.booksPath(vaultPath))
          .create(recursive: true);

      final now = DateTime.now().toUtc().toIso8601String();
      final authors = _splitAuthors(rwBook.author);

      // Reconcile: find existing canonical file by readwise_id or title
      Book? existing = await BookStorageService.reconcile(
        vaultPath,
        readwiseId: rwBook.id,
        title: rwBook.title.isNotEmpty ? rwBook.title : null,
      );

      if (existing == null) {
        // Create new canonical book file
        final existingBooks = await BookStorageService.loadBooks(vaultPath);
        final existingAliases = existingBooks.map((b) => b.alias).toSet();
        final alias = BookStorageService.generateAlias(
          rwBook.title.isNotEmpty ? rwBook.title : 'Book ${rwBook.id}',
          authors,
          existing: existingAliases,
        );
        final book = Book(
          alias: alias,
          title: rwBook.title.isNotEmpty ? rwBook.title : 'Book ${rwBook.id}',
          authors: authors,
          readwiseId: rwBook.id,
          numHighlights: rwBook.numHighlights,
          lastHighlightAt: rwBook.lastHighlightAt,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        final filePath = await BookStorageService.createBook(vaultPath, book);

        // Append all highlights to the freshly created file
        if (highlights.isNotEmpty) {
          await _appendHighlights(filePath, highlights, {});
        }
        return const ImportResult(created: 1, updated: 0, skipped: 0);
      }

      // Patch Readwise-owned frontmatter fields only
      await BookStorageService.patchFields(existing.filePath!, {
        'readwise_id': rwBook.id,
        'num_highlights': rwBook.numHighlights,
        if (rwBook.lastHighlightAt != null &&
            rwBook.lastHighlightAt!.isNotEmpty)
          'last_highlight_at': rwBook.lastHighlightAt,
        'updated_at': now,
      });

      // Append only new highlights (deduplicate by ^rw{id})
      final content = await File(existing.filePath!).readAsString();
      final existingIds = <int>{};
      for (final match in RegExp(r'\^rw(\d+)').allMatches(content)) {
        final id = int.tryParse(match.group(1)!);
        if (id != null) existingIds.add(id);
      }
      final newHighlights =
          highlights.where((h) => !existingIds.contains(h.id)).toList();

      if (newHighlights.isNotEmpty) {
        await _appendHighlights(existing.filePath!, newHighlights, existingIds);
      }

      return const ImportResult(created: 0, updated: 1, skipped: 0);
    } catch (e) {
      return ImportResult(
          created: 0, updated: 0, skipped: 0, error: e.toString());
    }
  }

  // ── Private: append highlights to ## Highlights section ──────────────────

  static Future<void> _appendHighlights(
    String filePath,
    List<ReadwiseHighlight> highlights,
    Set<int> existingIds,
  ) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final split = splitFrontmatter(content);
    final sections = parseSectionsH2(split.body);

    final buf = StringBuffer();

    // Preserve frontmatter + H1 + preamble unchanged
    if (split.frontmatter != null) {
      buf.writeln('---');
      buf.writeln(split.frontmatter);
      buf.writeln('---');
    }

    final h1 = extractH1(split.body);
    if (h1 != null) {
      buf.writeln();
      buf.writeln('# $h1');
      final preamble = _extractPreamble(split.body);
      if (preamble.isNotEmpty) {
        buf.writeln();
        buf.writeln(preamble);
      }
    }

    // Write all sections, appending to ## Highlights
    bool wroteHighlights = false;
    for (final entry in sections.entries) {
      buf.writeln();
      buf.writeln('## ${entry.key}');
      if (entry.key == 'Highlights') {
        wroteHighlights = true;
        if (entry.value.isNotEmpty) {
          buf.writeln();
          buf.write(entry.value);
          buf.writeln();
        }
        for (final h in highlights) {
          buf.write(_buildHighlightBlock(h));
        }
      } else {
        if (entry.value.isNotEmpty) {
          buf.writeln();
          buf.write(entry.value);
          buf.writeln();
        }
      }
    }

    // Add ## Highlights if it didn't exist yet
    if (!wroteHighlights && highlights.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Highlights');
      buf.writeln();
      for (final h in highlights) {
        buf.write(_buildHighlightBlock(h));
      }
    }

    await file.writeAsString('${buf.toString().trimRight()}\n');
  }

  // ── Private: highlight block builder ─────────────────────────────────────

  static String _buildHighlightBlock(ReadwiseHighlight h) {
    final buf = StringBuffer();

    for (final line in h.text.trim().split('\n')) {
      buf.writeln('> $line');
    }
    buf.writeln();

    if (h.note != null && h.note!.trim().isNotEmpty) {
      buf.writeln('**Note:** ${h.note!.trim()}');
      buf.writeln();
    }

    buf.writeln('^rw${h.id}');

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

  // ── Private: split author string into list ────────────────────────────────

  static List<String> _splitAuthors(String author) {
    if (author.isEmpty) return [];
    return author.split(', ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
