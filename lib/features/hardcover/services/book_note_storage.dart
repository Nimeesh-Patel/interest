import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../models/book_note.dart';

/// Reads and writes book notes — ordinary entities with `collection: Books`
/// living at the vault root, alongside every other entity. There is no separate
/// Books subsystem: a book is an entity that happens to carry a `hardcover_id`.
///
/// All-static, catch-all, never throws. Writes are frontmatter-only and
/// body-safe ([buildFrontmatterBlock] for new notes, [patchFrontmatterField]
/// for updates) — Hardcover never rebuilds a note body.
class BookNoteStorage {
  static const _collection = 'Books';
  static const _excludedFolders = {'.obsidian', 'Templates', 'Attachments'};

  /// Frontmatter key order for a book note. `collection` makes it an entity;
  /// the rest are Hardcover-owned. Any other key a user adds is preserved.
  static const _knownOrder = [
    'collection',
    'hardcover_id',
    'authors',
    'status',
    'rating',
    'updated_at',
  ];

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Every vault note with `collection: Books`. Title is the H1, else filename.
  static Future<List<BookNote>> loadBooks(String vaultPath) async {
    final books = <BookNote>[];
    try {
      await for (final entry in VaultScanner.scan(
        vaultPath,
        excludedFolders: _excludedFolders,
      )) {
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml == null) continue;
          if (yaml['collection']?.toString() != _collection) continue;
          books.add(BookNote(
            filePath: entry.path,
            title: extractH1(split.body) ??
                p.basenameWithoutExtension(entry.path),
            authors: _parseAuthors(yaml['authors']),
            hardcoverId: _parseInt(yaml['hardcover_id']),
            status: yaml['status']?.toString(),
            rating: _parseDouble(yaml['rating']),
          ));
        } catch (_) {}
      }
    } catch (_) {}
    return books;
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Writes a new book note at the vault root (collision-suffixed filename).
  /// Returns the path, or null on error.
  static Future<String?> createBookNote(
    String vaultPath, {
    required String title,
    required List<String> authors,
    required int hardcoverId,
    String? status,
    double? rating,
  }) async {
    try {
      final base = sanitizeFilename(title.isNotEmpty ? title : 'Book');
      var path = p.join(vaultPath, '$base.md');
      var n = 2;
      while (await File(path).exists()) {
        path = p.join(vaultPath, '$base $n.md');
        n++;
      }

      final fields = <String, dynamic>{
        'collection': _collection,
        'hardcover_id': hardcoverId,
        if (authors.isNotEmpty) 'authors': authors,
        if (status != null) 'status': status,
        if (rating != null) 'rating': rating,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final buf = StringBuffer();
      buf.writeln(buildFrontmatterBlock(fields, _knownOrder));
      buf.writeln('# $title');
      if (authors.isNotEmpty) {
        buf.writeln();
        buf.writeln('*${authors.join(', ')}*');
      }
      await File(path).writeAsString('${buf.toString().trimRight()}\n');
      return path;
    } catch (_) {
      return null;
    }
  }

  // ── Patch (frontmatter only, body preserved) ──────────────────────────────

  /// Updates Hardcover-owned scalar fields on an existing book note via the
  /// surgical [patchFrontmatterField] (body preserved). `null` values skipped.
  static Future<void> patchFields(
    String filePath, {
    int? hardcoverId,
    String? status,
    double? rating,
  }) async {
    if (hardcoverId != null) {
      await patchFrontmatterField(filePath, 'hardcover_id', '$hardcoverId');
    }
    if (status != null) {
      await patchFrontmatterField(filePath, 'status', status);
    }
    if (rating != null) {
      await patchFrontmatterField(filePath, 'rating', '$rating');
    }
    await patchFrontmatterField(
        filePath, 'updated_at', DateTime.now().toUtc().toIso8601String());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<String> _parseAuthors(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [raw.toString()];
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
