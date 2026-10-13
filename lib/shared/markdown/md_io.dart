// Surgical frontmatter patch for a single vault file.
// Directory iteration lives in VaultScanner (the sole Directory.list site);
// pure text utilities live in md_utils.dart.

import 'dart:io';
import 'dart:convert';

import 'frontmatter_patch.dart';

/// Dart's UTF-8 decoder consumes the BOM. Retain it for exact-source patches.
Future<String> readPreservingUtf8(File file) async {
  final bytes = await file.readAsBytes();
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return '${bom ? '\uFEFF' : ''}${utf8.decode(bytes)}';
}

/// Surgically patches one frontmatter field without touching the note body.
/// Failure is explicit; callers must not infer success from a swallowed error.
Future<FilePatchResult> patchFrontmatterField(
  String filePath,
  String key,
  String? value,
) async {
  try {
    return await (await prepareFrontmatterField(filePath, key, value)).apply();
  } catch (error) {
    return FilePatchResult.failed(filePath, '$error');
  }
}

/// Validate a source-span patch before a dependent external mutation. Applying
/// it later still requires the exact observed source to remain unchanged.
Future<PreparedFrontmatterPatch> prepareFrontmatterField(
  String filePath,
  String key,
  String? value,
) async {
  final before = await readPreservingUtf8(File(filePath));
  final after = patchFrontmatterText(before, {key: value});
  return PreparedFrontmatterPatch(filePath, before, after);
}

class PreparedFrontmatterPatch {
  final String filePath;
  final String before;
  final String after;
  const PreparedFrontmatterPatch(this.filePath, this.before, this.after);

  Future<FilePatchResult> apply() async {
    try {
      final file = File(filePath);
      if (await readPreservingUtf8(file) != before) {
        return FilePatchResult.failed(
          filePath,
          'file changed before patch write',
        );
      }
      await file.writeAsString(after);
      final observed = await readPreservingUtf8(file);
      if (observed != after) {
        return FilePatchResult.failed(
          filePath,
          'written state could not be verified',
        );
      }
      return FilePatchResult.applied(filePath, before, after);
    } catch (error) {
      return FilePatchResult.failed(filePath, '$error');
    }
  }
}

class FilePatchResult {
  final String filePath;
  final bool applied;
  final String? error;
  final String? before;
  final String? after;

  const FilePatchResult._(
    this.filePath,
    this.applied,
    this.error,
    this.before,
    this.after,
  );

  factory FilePatchResult.applied(
    String filePath,
    String before,
    String after,
  ) => FilePatchResult._(filePath, true, null, before, after);

  factory FilePatchResult.failed(String filePath, String error) =>
      FilePatchResult._(filePath, false, error, null, null);

  /// Restore only while the file still equals the state this patch wrote.
  Future<bool> rollback() async {
    if (!applied || before == null || after == null) return false;
    try {
      final file = File(filePath);
      if (await readPreservingUtf8(file) != after) return false;
      await file.writeAsString(before!);
      return await readPreservingUtf8(file) == before;
    } catch (_) {
      return false;
    }
  }
}
