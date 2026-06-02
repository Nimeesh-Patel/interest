// Filesystem helpers for Markdown vault directories.
// All functions are catch-all — never throw.

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'md_utils.dart';

/// Returns all `.md` [File] objects directly inside [dirPath].
/// Returns `[]` if the directory does not exist or on any error.
/// Does NOT recurse into subdirectories.
Future<List<File>> listMdFiles(String dirPath) async {
  try {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.endsWith('.md')) {
        files.add(entry);
      }
    }
    return files;
  } catch (_) {
    return [];
  }
}

/// Reads [file], splits YAML frontmatter, and parses it.
/// Returns `({yaml, body})` on success, `null` on any failure
/// (file unreadable, no frontmatter, YAML not a map).
Future<({YamlMap yaml, String body})?> readFrontmatter(File file) async {
  try {
    final content = await file.readAsString();
    final split = splitFrontmatter(content);
    if (split.frontmatter == null || split.frontmatter!.isEmpty) return null;
    final yaml = loadYaml(split.frontmatter!);
    if (yaml is! YamlMap) return null;
    return (yaml: yaml, body: split.body);
  } catch (_) {
    return null;
  }
}

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

/// Reads all `.md` files in [dirPath] and returns a map of `File → content`.
/// Files that fail to read are silently skipped.
Future<Map<File, String>> readAllMdContents(String dirPath) async {
  final files = await listMdFiles(dirPath);
  final result = <File, String>{};
  for (final f in files) {
    try {
      result[f] = await f.readAsString();
    } catch (_) {}
  }
  return result;
}
