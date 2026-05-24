import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../models/readera_book.dart';
import '../models/readera_highlight.dart';

typedef ReaderaParseResult = ({
  List<ReaderaBook> books,
  List<ReaderaHighlight> highlights,
  String? error,
});

/// Parses a ReadEra `.bak` file.
///
/// The backup is a ZIP archive containing `library.json`. That JSON has a
/// `docs` array; each doc carries a `citations` array of highlights.
/// All citation types in practice are 3 (highlighted passage).
class ReaderaParser {
  static Future<ReaderaParseResult> parse(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final libFile = archive.findFile('library.json');
      if (libFile == null) {
        return (
          books: <ReaderaBook>[],
          highlights: <ReaderaHighlight>[],
          error: 'library.json not found in backup. '
              'Found: ${archive.files.map((f) => f.name).join(', ')}',
        );
      }

      final jsonStr = utf8.decode(libFile.content as List<int>);
      final root = jsonDecode(jsonStr) as Map<String, dynamic>;
      final docs = root['docs'] as List<dynamic>? ?? [];

      final books = <ReaderaBook>[];
      final highlights = <ReaderaHighlight>[];

      for (final doc in docs) {
        final data = doc['data'] as Map<String, dynamic>? ?? {};
        final sha1 = (data['doc_sha1'] as String?) ?? '';
        final title = ((data['doc_title'] as String?) ?? '').trim();
        final author = ((data['doc_authors'] as String?) ?? '').trim();

        if (sha1.isEmpty || title.isEmpty) continue;

        books.add(ReaderaBook(id: sha1, title: title, author: author));

        final citations = doc['citations'] as List<dynamic>? ?? [];
        for (final c in citations) {
          final uri = (c['note_uri'] as String?) ?? '';
          final body = ((c['note_body'] as String?) ?? '').trim();
          if (uri.isEmpty || body.isEmpty) continue;

          final insertMs = c['note_insert_time'] as int?;
          highlights.add(ReaderaHighlight(
            id: uri,
            bookId: sha1,
            text: body,
            page: c['note_page'] as int?,
            createdAt: insertMs != null
                ? DateTime.fromMillisecondsSinceEpoch(insertMs, isUtc: true)
                    .toIso8601String()
                : null,
          ));
        }
      }

      return (books: books, highlights: highlights, error: null);
    } catch (e) {
      return (
        books: <ReaderaBook>[],
        highlights: <ReaderaHighlight>[],
        error: e.toString(),
      );
    }
  }
}
