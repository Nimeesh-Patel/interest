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
    // A file that opens with `---` but does not split has malformed
    // frontmatter already. Treating it as bodyless would prepend a second
    // block and compound the damage, so refuse and leave it for repair.
    if (split.frontmatter == null && content.trimLeft().startsWith('---')) {
      return;
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
    // splitFrontmatter drops the block's trailing newline, and replacing an
    // existing key does not restore it. Without this the closing `---` is
    // written onto the end of the last value (`aliases:\n  - gumption---`),
    // the block stops being YAML, and every consumer loses up/category/id.
    if (!fm.endsWith('\n')) fm += '\n';

    final patched = '---\n$fm---\n$body';
    // Refuse rather than corrupt: a patch that does not re-split into valid
    // frontmatter and the same body is not a patch. Silent damage to an
    // authored note is the failure this function exists to prevent.
    final check = splitFrontmatter(patched);
    if (check.frontmatter == null || check.body.trim() != body.trim()) return;
    await File(filePath).writeAsString(patched);
  } catch (_) {}
}
