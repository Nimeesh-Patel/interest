import 'dart:io';

import 'package:path/path.dart' as p;

import 'vault_scanner.dart';

class CurrentVaultContent {
  static const _systemFolderSegments = {
    '.obsidian',
    '.trash',
    '.perspirator',
    '.interest',
    'templates',
    'attachments',
  };

  /// Returns whether [filePath] belongs to the current vault surface for [use].
  ///
  /// Root notes and ordinary authored subtrees (including `Clippings/`) remain
  /// eligible. Rollback/history, trash, templates, attachments, Basic Memory
  /// and Interest's device-local `.interest/` folder are never current cards
  /// or link targets.
  static bool isEligible(String vaultPath, String filePath) {
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
    return folders.isEmpty || folders.first != 'memory';
  }

  /// Collects the eligible current Markdown surface and preserves traversal
  /// errors from [VaultScanner].
  static Future<VaultScanResult> scan(String vaultPath) async {
    final scanned = await VaultScanner.scanResult(vaultPath);
    final files = <File>[
      for (final file in scanned.files)
        if (isEligible(vaultPath, file.path)) file,
    ];
    return VaultScanResult(files: files, errors: scanned.errors);
  }
}
