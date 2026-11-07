import 'dart:io';

import 'package:path/path.dart' as p;

import 'current_vault_content.dart';
import 'md_utils.dart';

/// Builds the map that turns a wikilink target into a canonical vault-relative
/// path, so `[[speed of progress]]` — an alias — reaches the note that declares
/// it rather than a note of that name which does not exist.
///
/// Ambiguity is dropped rather than guessed: a key resolves only when exactly
/// one note claims it, and a real filename always wins over an alias. An
/// `obsidian://` link built from a wrong target is worse than one that simply
/// fails to open, because it silently sends the reader to another note.
///
/// The only I/O is [CurrentVaultContent.scan]; the parsing it feeds is pure.
/// A link target may be any current authored note, including one without a
/// `***` separator that never becomes a card itself.
class LinkTargetBuildResult {
  final Map<String, String> targets;
  final List<String> errors;

  const LinkTargetBuildResult({required this.targets, required this.errors});

  bool get isComplete => errors.isEmpty;
}

Future<LinkTargetBuildResult> buildLinkTargets(String vaultPath) async {
  final aliasesByNote = <String, List<String>>{};
  final errors = <String>[];

  final scanned = await CurrentVaultContent.scan(vaultPath);
  errors.addAll(scanned.errors);
  for (final file in scanned.files) {
    final relative = p
        .relative(file.path, from: vaultPath)
        .replaceAll(r'\', '/');
    String content;
    try {
      content = await file.readAsString();
    } on FileSystemException catch (error) {
      errors.add(
        'Could not read link target "${p.relative(file.path, from: vaultPath)}": '
        '$error',
      );
      continue;
    }
    aliasesByNote[relative] = parseAliases(splitFrontmatter(content).frontmatter);
  }
  return LinkTargetBuildResult(
    targets: resolveLinkTargets(aliasesByNote),
    errors: errors,
  );
}

/// The pure resolution behind [buildLinkTargets]: [aliasesByNote] maps every
/// current note's vault-relative path (with `.md`) to its declared aliases.
/// Callers that already hold those facts (a scan, the sync manifest) resolve
/// without reading the vault again.
Map<String, String> resolveLinkTargets(Map<String, List<String>> aliasesByNote) {
  final names = <String, Set<String>>{};
  final aliases = <String, Set<String>>{};
  aliasesByNote.forEach((relative, declared) {
    final canonical =
        relative.endsWith('.md')
            ? relative.substring(0, relative.length - 3)
            : relative;
    for (final key in {canonical, p.basename(canonical)}) {
      names.putIfAbsent(key.toLowerCase(), () => <String>{}).add(canonical);
    }
    for (final alias in declared) {
      final key =
          alias
              .replaceAll(r'\', '/')
              .replaceAll(RegExp(r'\.md$'), '')
              .toLowerCase();
      aliases.putIfAbsent(key, () => <String>{}).add(canonical);
    }
  });

  final resolved = <String, String>{};
  names.forEach((key, values) {
    if (values.length == 1) resolved[key] = values.first;
  });
  aliases.forEach((key, values) {
    if (!names.containsKey(key) && values.length == 1) {
      resolved[key] = values.first;
    }
  });
  return resolved;
}
