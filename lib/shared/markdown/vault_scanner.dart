import 'dart:io';

import 'package:path/path.dart' as p;

class VaultScanner {
  /// Yields all .md files under [basePath].
  ///
  /// When [recursive] is true (default), any path segment matching
  /// [excludedFolders] causes the file to be skipped.
  /// When [recursive] is false, yields only direct .md children of [basePath].
  /// Never throws; silently ignores unreadable entries and missing directories.
  static Stream<File> scan(
    String basePath, {
    Set<String> excludedFolders = const {},
    bool recursive = true,
  }) async* {
    try {
      final dir = Directory(basePath);
      await for (final entry in dir.list(recursive: recursive)) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        if (recursive && excludedFolders.isNotEmpty) {
          final rel = p.relative(entry.path, from: basePath);
          final folders = p.split(rel)..removeLast();
          if (folders.any(excludedFolders.contains)) continue;
        }
        yield entry;
      }
    } catch (_) {}
  }
}
