import 'dart:io';

import 'package:path/path.dart' as p;

import 'vault_scanner.dart';

/// The current-state role for which a vault path is being considered.
///
/// Semantic predicates still belong to their feature parsers. This enum only
/// distinguishes path ownership: a historical/system file cannot become live
/// input merely because its contents happen to match a feature predicate.
enum CurrentVaultUse { ankiProblemNote, entity, linkTarget }

class CurrentVaultContent {
  static const _systemFolderSegments = {
    '.obsidian',
    '.trash',
    '.perspirator',
    'templates',
    'attachments',
  };

  /// Returns whether [filePath] belongs to the current vault surface for [use].
  ///
  /// Root notes and ordinary authored subtrees (including `Clippings/`) remain
  /// eligible. Rollback/history, trash, templates, attachments, Basic Memory,
  /// and Interest's system configuration are never current cards or entities.
  /// Anki additionally excludes Interest-owned documents and accepts optional
  /// user-configured folder exclusions.
  static bool isEligible(
    String vaultPath,
    String filePath, {
    required CurrentVaultUse use,
    Iterable<String> additionalExcludedFolders = const [],
  }) {
    final root = p.canonicalize(p.absolute(vaultPath));
    final candidate = p.canonicalize(p.absolute(filePath));
    if (!p.isWithin(root, candidate)) return false;

    final relative = p.relative(candidate, from: root);
    final parts = p
        .split(relative)
        .map((part) => part.toLowerCase())
        .toList(growable: false);
    if (parts.isEmpty) return false;
    final folders = parts.take(parts.length - 1).toList(growable: false);

    if (folders.any(_systemFolderSegments.contains)) return false;
    if (folders.isNotEmpty && folders.first == 'memory') return false;
    if (folders.length >= 2 &&
        folders[0] == 'interesting' &&
        folders[1] == 'system') {
      return false;
    }
    if (use == CurrentVaultUse.ankiProblemNote &&
        folders.isNotEmpty &&
        folders.first == 'interesting') {
      return false;
    }

    final additional =
        additionalExcludedFolders
            .map((folder) => folder.trim().toLowerCase())
            .where((folder) => folder.isNotEmpty)
            .toSet();
    return !folders.any(additional.contains);
  }

  /// Collects the eligible current Markdown surface and preserves traversal
  /// errors from [VaultScanner].
  static Future<VaultScanResult> scan(
    String vaultPath, {
    required CurrentVaultUse use,
    Iterable<String> additionalExcludedFolders = const [],
  }) async {
    final scanned = await VaultScanner.scanResult(vaultPath);
    final files = <File>[
      for (final file in scanned.files)
        if (isEligible(
          vaultPath,
          file.path,
          use: use,
          additionalExcludedFolders: additionalExcludedFolders,
        ))
          file,
    ];
    return VaultScanResult(files: files, errors: scanned.errors);
  }
}
