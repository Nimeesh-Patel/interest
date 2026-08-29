import 'dart:io';

import 'package:path/path.dart' as p;

class VaultScanResult {
  final List<File> files;
  final List<String> errors;

  const VaultScanResult({required this.files, required this.errors});

  bool get isComplete => errors.isEmpty;
}

class VaultScanner {
  /// Lists direct filesystem children without filtering.
  ///
  /// This keeps directory enumeration in one owner while allowing exact-file
  /// transaction recovery to distinguish an empty directory from an
  /// unreadable one. `null` means the observation could not be completed.
  static Future<List<FileSystemEntity>?> listDirect(
    String directoryPath,
  ) async {
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

  /// Collects all .md files under [basePath] and reports whether traversal was
  /// complete. Callers that can mutate external state must inspect [errors]
  /// before acting; a partial filesystem observation is not an empty/successful
  /// scan.
  ///
  /// When [recursive] is true (default), any path segment matching
  /// [excludedFolders] causes the file to be skipped.
  /// When [recursive] is false, yields only direct .md children of [basePath].
  /// Never throws. Missing or unreadable directories are explicit errors.
  static Future<VaultScanResult> scanResult(
    String basePath, {
    Set<String> excludedFolders = const {},
    bool recursive = true,
  }) async {
    final files = <File>[];
    final errors = <String>[];
    try {
      final dir = Directory(basePath);
      await for (final entry in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        if (recursive && excludedFolders.isNotEmpty) {
          final rel = p.relative(entry.path, from: basePath);
          final folders = p.split(rel)..removeLast();
          if (folders.any(excludedFolders.contains)) continue;
        }
        files.add(entry);
      }
    } catch (error) {
      errors.add('Could not completely scan "$basePath": $error');
    }
    return VaultScanResult(files: files, errors: errors);
  }

  /// Compatibility stream for read-only callers that do not expose scan
  /// completeness. Mutation and projection discovery use [scanResult].
  static Stream<File> scan(
    String basePath, {
    Set<String> excludedFolders = const {},
    bool recursive = true,
  }) async* {
    final result = await scanResult(
      basePath,
      excludedFolders: excludedFolders,
      recursive: recursive,
    );
    for (final file in result.files) {
      yield file;
    }
  }
}
