// Surgical frontmatter patch for a single vault file.
// Directory iteration lives in VaultScanner (the sole Directory.list site);
// pure text utilities live in md_utils.dart.

import 'dart:io';

import 'md_utils.dart';

/// Surgically patches one frontmatter field without touching the note body.
/// Failure is explicit; callers must not infer success from a swallowed error.
Future<FilePatchResult> patchFrontmatterField(
  String filePath,
  String key,
  String value,
) async {
  try {
    final content = await File(filePath).readAsString();
    final split = splitFrontmatter(content);
    if (split.frontmatter == null && content.trimLeft().startsWith('---')) {
      return FilePatchResult.failed(filePath, 'malformed opening frontmatter');
    }
    String fm = split.frontmatter ?? '';
    final body = split.body;
    final pattern = RegExp('^$key:.*', multiLine: true);
    if (pattern.hasMatch(fm)) {
      fm = fm.replaceAll(pattern, '$key: $value');
    } else {
      if (fm.isNotEmpty && !fm.endsWith('\n')) fm += '\n';
      fm += '$key: $value\n';
    }
    if (!fm.endsWith('\n')) fm += '\n';

    final patched = '---\n$fm---\n$body';
    final check = splitFrontmatter(patched);
    if (check.frontmatter == null || check.body.trim() != body.trim()) {
      return FilePatchResult.failed(filePath, 'patch changed the note body');
    }
    final file = File(filePath);
    if (await file.readAsString() != content) {
      return FilePatchResult.failed(
        filePath,
        'file changed before patch write',
      );
    }
    await file.writeAsString(patched);
    final observed = await file.readAsString();
    if (observed != patched) {
      return FilePatchResult.failed(
        filePath,
        'written state could not be verified',
      );
    }
    return FilePatchResult.applied(filePath, content, patched);
  } catch (error) {
    return FilePatchResult.failed(filePath, '$error');
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
      if (await file.readAsString() != after) return false;
      await file.writeAsString(before!);
      return await file.readAsString() == before;
    } catch (_) {
      return false;
    }
  }
}
