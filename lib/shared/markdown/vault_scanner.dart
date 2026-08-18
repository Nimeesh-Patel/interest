import 'dart:io';

import 'package:path/path.dart' as p;

class VaultScanner {
  /// Lists direct filesystem children without filtering.
  ///
  /// This keeps directory enumeration in one owner while allowing exact-file
  /// transaction recovery to distinguish an empty directory from an
  /// unreadable one. `null` means the observation could not be completed.
  static Future<List<FileSystemEntity>?> listDirect(String directoryPath) async {
    try {
      final entries = <FileSystemEntity>[];
      await for (final entry in Directory(
        directoryPath,
      ).list(recursive: false, followLinks: false)) {
        entries.add(entry);
      }
      return entries;
    } catch (_) {
      return null;
    }
  }

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
