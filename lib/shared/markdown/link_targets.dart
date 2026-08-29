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
/// A link target may live anywhere a current authored note lives, so this is
/// deliberately wider than the Anki scan: `Interesting/` is not synced to Anki
/// but a card may still link into a non-system Interest document.
class LinkTargetBuildResult {
  final Map<String, String> targets;
  final List<String> errors;

  const LinkTargetBuildResult({required this.targets, required this.errors});

  bool get isComplete => errors.isEmpty;
}

Future<LinkTargetBuildResult> buildLinkTargets(String vaultPath) async {
  final names = <String, Set<String>>{};
  final aliases = <String, Set<String>>{};
  final errors = <String>[];

  final scanned = await CurrentVaultContent.scan(
    vaultPath,
    use: CurrentVaultUse.linkTarget,
  );
  errors.addAll(scanned.errors);
  for (final file in scanned.files) {
    final relative = p
        .relative(file.path, from: vaultPath)
        .replaceAll('\\', '/');
    final canonical =
        relative.endsWith('.md')
            ? relative.substring(0, relative.length - 3)
            : relative;
    for (final key in {canonical, p.basenameWithoutExtension(file.path)}) {
      names.putIfAbsent(key.toLowerCase(), () => <String>{}).add(canonical);
    }
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
    for (final alias in parseAliases(splitFrontmatter(content).frontmatter)) {
      final key =
          alias
              .replaceAll('\\', '/')
              .replaceAll(RegExp(r'\.md$'), '')
              .toLowerCase();
      aliases.putIfAbsent(key, () => <String>{}).add(canonical);
    }
  }

  final resolved = <String, String>{};
  names.forEach((key, values) {
    if (values.length == 1) resolved[key] = values.first;
  });
  aliases.forEach((key, values) {
    if (!names.containsKey(key) && values.length == 1) {
      resolved[key] = values.first;
    }
  });
  return LinkTargetBuildResult(targets: resolved, errors: errors);
}
