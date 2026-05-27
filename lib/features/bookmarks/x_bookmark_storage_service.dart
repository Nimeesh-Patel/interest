import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/vault_service.dart';
import '../../shared/markdown/md_utils.dart';
import 'x_bookmark_service.dart';

class XBookmarkStorageService {
  static const _knownOrder = [
    'alias',
    'author',
    'author_url',
    'source_url',
    'date',
  ];

  /// Returns null on success or silent dedup skip. Never throws.
  static Future<String?> save(
    String vaultPath,
    String slug,
    XBookmarkFetchResult meta,
  ) async {
    try {
      final dir = Directory(VaultService.bookmarksPath(vaultPath));
      await dir.create(recursive: true);

      final filePath = p.join(dir.path, '$slug.md');
      if (await File(filePath).exists()) return null;

      final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final fields = <String, dynamic>{
        'alias': slug,
        if (meta.authorName != null && meta.authorName!.isNotEmpty)
          'author': meta.authorName,
        if (meta.authorUrl != null && meta.authorUrl!.isNotEmpty)
          'author_url': meta.authorUrl,
        if (meta.sourceUrl != null && meta.sourceUrl!.isNotEmpty)
          'source_url': meta.sourceUrl,
        'date': date,
      };

      final buf = StringBuffer();
      buf.writeln(buildFrontmatterBlock(fields, _knownOrder));

      if (meta.tweetText != null && meta.tweetText!.isNotEmpty) {
        buf.writeln(meta.tweetText);
        if (meta.authorName != null) {
          buf.writeln();
          final authorPart = meta.authorUrl != null
              ? '[${meta.authorName}](${meta.authorUrl})'
              : meta.authorName!;
          final sourcePart = meta.sourceUrl != null
              ? '[source](${meta.sourceUrl})'
              : 'source';
          buf.writeln('— $authorPart · $sourcePart');
        }
      }

      await File(filePath).writeAsString(buf.toString());
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns a slug that does not yet exist as a file in [dirPath].
  /// Appends -2, -3, … if [base].md already exists.
  static String uniqueSlug(String base, String dirPath) {
    if (!File(p.join(dirPath, '$base.md')).existsSync()) return base;
    var n = 2;
    while (File(p.join(dirPath, '$base-$n.md')).existsSync()) {
      n++;
    }
    return '$base-$n';
  }
}
