import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../readera/models/readera_highlight.dart';
import '../models/book.dart';

class BookStorageService {
  // ── Load ──────────────────────────────────────────────────────────────────

  static Future<List<Book>> loadBooks(String vaultPath) async {
    final dir = Directory(VaultService.booksPath(vaultPath));
    if (!await dir.exists()) return [];

    final books = <Book>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;
      try {
        final content = await entity.readAsString();
        final split = splitFrontmatter(content);
        if (split.frontmatter == null) continue;
        final yaml = parseYamlMap(split.frontmatter);
        if (yaml == null) continue;

        final type = yaml['type']?.toString();
        if (type == 'book_highlights') {
          // Lazy migration: upgrade legacy file in-place and return migrated model
          final book = _migrateFromLegacy(yaml, split.body, entity.path);
          await _writeMigratedFile(entity.path, book, split.body);
          books.add(book);
        } else if (type == 'book') {
          books.add(Book.fromFrontmatterYaml(yaml, split.body, entity.path));
        }
      } catch (_) {
        continue;
      }
    }
    return books;
  }

  // ── Identity lookups ──────────────────────────────────────────────────────

  static Future<Book?> findByHardcoverId(String vaultPath, int id) async {
    final books = await loadBooks(vaultPath);
    try {
      return books.firstWhere((b) => b.hardcoverId == id);
    } catch (_) {
      return null;
    }
  }

  static Future<Book?> findByReadwiseId(String vaultPath, int id) async {
    final books = await loadBooks(vaultPath);
    try {
      return books.firstWhere((b) => b.readwiseId == id);
    } catch (_) {
      return null;
    }
  }

  static Future<Book?> findByIsbn(String vaultPath, String isbn) async {
    final normalized = _normalizeIsbn(isbn);
    if (normalized.isEmpty) return null;
    final books = await loadBooks(vaultPath);
    try {
      return books.firstWhere(
          (b) => b.isbn != null && _normalizeIsbn(b.isbn!) == normalized);
    } catch (_) {
      return null;
    }
  }

  static Future<Book?> findByTitle(String vaultPath, String title) async {
    final slug = slugify(title);
    if (slug.isEmpty) return null;
    final books = await loadBooks(vaultPath);
    try {
      return books.firstWhere((b) => slugify(b.title) == slug);
    } catch (_) {
      return null;
    }
  }

  /// Reconcile: find an existing book matching any of the given anchors,
  /// checking in priority order: hardcoverId > readwiseId > isbn > title.
  static Future<Book?> reconcile(
    String vaultPath, {
    int? hardcoverId,
    int? readwiseId,
    String? isbn,
    String? title,
  }) async {
    final books = await loadBooks(vaultPath);

    if (hardcoverId != null) {
      try {
        return books.firstWhere((b) => b.hardcoverId == hardcoverId);
      } catch (_) {}
    }
    if (readwiseId != null) {
      try {
        return books.firstWhere((b) => b.readwiseId == readwiseId);
      } catch (_) {}
    }
    if (isbn != null && isbn.isNotEmpty) {
      final normalized = _normalizeIsbn(isbn);
      if (normalized.isNotEmpty) {
        try {
          return books.firstWhere(
              (b) => b.isbn != null && _normalizeIsbn(b.isbn!) == normalized);
        } catch (_) {}
      }
    }
    if (title != null && title.isNotEmpty) {
      final slug = slugify(title);
      if (slug.isNotEmpty) {
        try {
          return books.firstWhere((b) => slugify(b.title) == slug);
        } catch (_) {}
      }
    }
    return null;
  }

  // ── Patch ─────────────────────────────────────────────────────────────────

  /// Patches only the specified frontmatter fields, preserving the body and
  /// all other frontmatter keys. This is the minimal-patch primitive that
  /// allows Readwise and Hardcover to write to the same file without collision.
  static Future<void> patchFields(
      String filePath, Map<String, dynamic> updates) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final split = splitFrontmatter(content);
    if (split.frontmatter == null) return;
    final yaml = parseYamlMap(split.frontmatter);
    if (yaml == null) return;

    final merged = Map<String, dynamic>.from(yaml);
    merged.addAll(updates);

    final newContent = '${buildFrontmatterBlock(merged, _knownOrder)}\n${split.body}';
    await file.writeAsString(newContent);
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Creates a new canonical book file. Returns the file path.
  static Future<String> createBook(String vaultPath, Book book) async {
    final dir = Directory(VaultService.booksPath(vaultPath));
    await dir.create(recursive: true);

    final filename = '${sanitizeFilename(book.title.isNotEmpty ? book.title : book.alias)}.md';
    final filePath = p.join(dir.path, filename);

    final content = _buildNewBookContent(book);
    await File(filePath).writeAsString(content);
    return filePath;
  }

  // ── Frontmatter builder ───────────────────────────────────────────────────

  static const _knownOrder = [
    'type', 'alias', 'title', 'authors', 'isbn',
    'hardcover_id', 'readwise_id', 'status', 'rating',
    'started_at', 'finished_at', 'num_highlights',
    'last_highlight_at', 'updated_at',
  ];

  static String _buildNewBookContent(Book book) {
    final now = DateTime.now().toUtc().toIso8601String();
    final fields = <String, dynamic>{
      'type': 'book',
      'alias': book.alias,
      'title': book.title,
      'authors': book.authors,
      if (book.isbn != null) 'isbn': book.isbn,
      if (book.hardcoverId != null) 'hardcover_id': book.hardcoverId,
      if (book.readwiseId != null) 'readwise_id': book.readwiseId,
      if (book.status != null) 'status': book.status,
      if (book.rating != null) 'rating': book.rating,
      if (book.startedAt != null) 'started_at': book.startedAt,
      if (book.finishedAt != null) 'finished_at': book.finishedAt,
      if (book.numHighlights != null) 'num_highlights': book.numHighlights,
      if (book.lastHighlightAt != null) 'last_highlight_at': book.lastHighlightAt,
      'updated_at': now,
    };

    final buf = StringBuffer();
    buf.writeln(buildFrontmatterBlock(fields, _knownOrder));
    buf.writeln('# ${book.title}');
    if (book.authors.isNotEmpty) {
      buf.writeln();
      buf.writeln('*${book.authors.join(', ')}*');
    }
    buf.writeln();
    buf.writeln('## Highlights');
    buf.writeln();
    buf.writeln('*No highlights imported.*');
    return '${buf.toString().trimRight()}\n';
  }

  // ── ReadEra highlight appending ───────────────────────────────────────────

  /// Appends new ReadEra highlights to the `## Highlights (ReadEra)` section,
  /// creating it if absent. All other sections are preserved verbatim.
  /// Deduplication (^re anchors) must be handled by the caller before invoking.
  static Future<void> appendReaderaHighlights(
    String filePath,
    List<ReaderaHighlight> highlights,
  ) async {
    if (highlights.isEmpty) return;
    final file = File(filePath);
    if (!await file.exists()) return;

    final content = await file.readAsString();
    final split = splitFrontmatter(content);
    final sections = parseSectionsH2(split.body);

    final buf = StringBuffer();

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

    bool wroteSection = false;
    for (final entry in sections.entries) {
      buf.writeln();
      buf.writeln('## ${entry.key}');
      if (entry.key == 'Highlights (ReadEra)') {
        wroteSection = true;
        if (entry.value.isNotEmpty) {
          buf.writeln();
          buf.write(entry.value);
          buf.writeln();
        }
        for (final h in highlights) {
          buf.write(_buildReaderaHighlightBlock(h));
        }
      } else {
        if (entry.value.isNotEmpty) {
          buf.writeln();
          buf.write(entry.value);
          buf.writeln();
        }
      }
    }

    if (!wroteSection) {
      buf.writeln();
      buf.writeln('## Highlights (ReadEra)');
      buf.writeln();
      for (final h in highlights) {
        buf.write(_buildReaderaHighlightBlock(h));
      }
    }

    await file.writeAsString('${buf.toString().trimRight()}\n');
  }

  static String _buildReaderaHighlightBlock(ReaderaHighlight h) {
    final buf = StringBuffer();

    for (final line in h.text.trim().split('\n')) {
      buf.writeln('> $line');
    }
    buf.writeln();

    buf.writeln('^re${h.id}');

    final meta = StringBuffer();
    if (h.page != null) meta.write('Page ${h.page}');
    if (h.createdAt != null) {
      if (meta.isNotEmpty) meta.write(' · ');
      meta.write('Added: ${h.createdAt!.substring(0, 10)}');
    }
    if (meta.isNotEmpty) buf.writeln(meta.toString());

    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    return buf.toString();
  }

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

  // ── Migration ─────────────────────────────────────────────────────────────

  static Book _migrateFromLegacy(Map yaml, String body, String filePath) {
    final authors = _legacyAuthors(yaml);
    final alias = _generateAlias(
      yaml['title']?.toString() ?? '',
      authors,
    );
    final createdAtMs = parseIsoToMs(yaml['updated_at']?.toString()) ??
        DateTime.now().millisecondsSinceEpoch;

    return Book(
      alias: alias,
      title: yaml['title']?.toString() ?? '',
      authors: authors,
      isbn: yaml['isbn']?.toString(),
      readwiseId: _parseInt(yaml['readwise_id']),
      numHighlights: _parseInt(yaml['num_highlights']),
      lastHighlightAt: yaml['last_highlight_at']?.toString(),
      createdAt: createdAtMs,
      updatedAt: createdAtMs,
      filePath: filePath,
      rawSections: parseSectionsH2(body),
    );
  }

  static Future<void> _writeMigratedFile(
      String filePath, Book book, String body) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final fields = <String, dynamic>{
      'type': 'book',
      'alias': book.alias,
      'title': book.title,
      'authors': book.authors,
      if (book.isbn != null) 'isbn': book.isbn,
      if (book.hardcoverId != null) 'hardcover_id': book.hardcoverId,
      if (book.readwiseId != null) 'readwise_id': book.readwiseId,
      if (book.status != null) 'status': book.status,
      if (book.rating != null) 'rating': book.rating,
      if (book.startedAt != null) 'started_at': book.startedAt,
      if (book.finishedAt != null) 'finished_at': book.finishedAt,
      if (book.numHighlights != null) 'num_highlights': book.numHighlights,
      if (book.lastHighlightAt != null) 'last_highlight_at': book.lastHighlightAt,
      'updated_at': now,
    };
    final newContent = '${buildFrontmatterBlock(fields, _knownOrder)}\n$body';
    await File(filePath).writeAsString(newContent);
  }

  static List<String> _legacyAuthors(Map yaml) {
    final raw = yaml['author']?.toString() ?? '';
    if (raw.isEmpty) return [];
    return raw.split(', ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  // ── Alias generation ──────────────────────────────────────────────────────

  static String generateAlias(String title, List<String> authors,
      {Set<String>? existing}) {
    return _generateAlias(title, authors, existing: existing);
  }

  static String _generateAlias(String title, List<String> authors,
      {Set<String>? existing}) {
    var base = slugify(title);
    if (base.isEmpty) base = 'book';

    if (existing == null || !existing.contains(base)) return base;

    // Disambiguate with first author
    if (authors.isNotEmpty) {
      final withAuthor = '$base-${slugify(authors.first)}';
      if (!existing.contains(withAuthor)) return withAuthor;
    }

    // Numeric suffix fallback
    var n = 2;
    while (existing.contains('$base-$n')) {
      n++;
    }
    return '$base-$n';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static String _normalizeIsbn(String isbn) =>
      isbn.replaceAll(RegExp(r'[-\s]'), '').toLowerCase();

}
