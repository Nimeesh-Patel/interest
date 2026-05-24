import 'dart:io';

import '../../../core/vault_service.dart';
import '../../books/models/book.dart';
import '../../books/services/book_storage_service.dart';
import '../../rss/models/rss_import_result.dart';
import '../models/readera_highlight.dart';
import 'readera_parser.dart';

class ReaderaIngestionService {
  /// Parses a ReadEra `.bak` file and merges its highlights into canonical
  /// book files in the vault. Never throws; errors surface via ImportResult.
  static Future<ImportResult> ingest(
      String bakFilePath, String vaultPath) async {
    try {
      await Directory(VaultService.booksPath(vaultPath))
          .create(recursive: true);

      final parsed = await ReaderaParser.parse(bakFilePath);
      if (parsed.error != null) {
        return ImportResult(
            created: 0, updated: 0, skipped: 0, error: parsed.error);
      }
      if (parsed.books.isEmpty) {
        return const ImportResult(created: 0, updated: 0, skipped: 0);
      }

      // Index highlights by bookId (doc_sha1) for O(1) lookup per book
      final byBook = <String, List<ReaderaHighlight>>{};
      for (final h in parsed.highlights) {
        byBook.putIfAbsent(h.bookId, () => []).add(h);
      }

      int created = 0, updated = 0, skipped = 0;
      final now = DateTime.now().toUtc().toIso8601String();

      for (final reBook in parsed.books) {
        final highlights = byBook[reBook.id] ?? [];

        // Reconcile by normalized title (no ISBN in ReadEra exports)
        Book? existing = await BookStorageService.reconcile(
          vaultPath,
          title: reBook.title,
        );

        String filePath;
        if (existing == null) {
          final existingBooks = await BookStorageService.loadBooks(vaultPath);
          final existingAliases = existingBooks.map((b) => b.alias).toSet();
          final alias = BookStorageService.generateAlias(
            reBook.title,
            _splitAuthors(reBook.author),
            existing: existingAliases,
          );
          final book = Book(
            alias: alias,
            title: reBook.title,
            authors: _splitAuthors(reBook.author),
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          filePath = await BookStorageService.createBook(vaultPath, book);
          created++;
        } else {
          filePath = existing.filePath!;
          updated++;
        }

        if (highlights.isEmpty) {
          if (existing != null) skipped++;
          continue;
        }

        // Deduplicate: collect existing ^re{uuid} anchors already in the file
        final content = await File(filePath).readAsString();
        final existingIds = <String>{};
        for (final match
            in RegExp(r'\^re([a-f0-9\-]{36})').allMatches(content)) {
          existingIds.add(match.group(1)!);
        }
        final newHighlights =
            highlights.where((h) => !existingIds.contains(h.id)).toList();

        if (newHighlights.isNotEmpty) {
          await BookStorageService.appendReaderaHighlights(
              filePath, newHighlights);
          await BookStorageService.patchFields(filePath, {'updated_at': now});
        }
      }

      return ImportResult(created: created, updated: updated, skipped: skipped);
    } catch (e) {
      return ImportResult(
          created: 0, updated: 0, skipped: 0, error: e.toString());
    }
  }

  static List<String> _splitAuthors(String author) {
    if (author.isEmpty) return [];
    return author
        .split(', ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
