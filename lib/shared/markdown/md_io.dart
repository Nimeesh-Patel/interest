// Surgical frontmatter patch for a single vault file. Catch-all — never throws.
// Directory iteration lives in VaultScanner (the sole Directory.list site);
// pure text utilities live in md_utils.dart.

import 'dart:io';

import 'md_utils.dart';

/// Surgically patches a single frontmatter field in a vault file.
/// If [key] already exists in the frontmatter it is replaced in-place;
/// otherwise it is appended. Never touches the note body. Never throws.
Future<void> patchFrontmatterField(
    String filePath, String key, String value) async {
  try {
    final content = await File(filePath).readAsString();
    final split = splitFrontmatter(content);
    String fm = split.frontmatter ?? '';
    final body = split.body;
    final pattern = RegExp('^$key:.*', multiLine: true);
    if (pattern.hasMatch(fm)) {
      fm = fm.replaceAll(pattern, '$key: $value');
    } else {
      if (fm.isNotEmpty && !fm.endsWith('\n')) fm += '\n';
      fm += '$key: $value\n';
    }
    await File(filePath).writeAsString('---\n$fm---\n$body');
  } catch (_) {}
}
