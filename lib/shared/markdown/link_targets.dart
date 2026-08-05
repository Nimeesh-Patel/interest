import 'dart:io';

import 'package:path/path.dart' as p;

import 'md_utils.dart';
import 'vault_scanner.dart';

/// Builds the map that turns a wikilink target into a canonical vault-relative
/// path, so `[[speed of progress]]` — an alias — reaches the note that declares
/// it rather than a note of that name which does not exist.
///
/// Ambiguity is dropped rather than guessed: a key resolves only when exactly
/// one note claims it, and a real filename always wins over an alias. An
/// `obsidian://` link built from a wrong target is worse than one that simply
/// fails to open, because it silently sends the reader to another note.
///
/// The only I/O is [VaultScanner.scan]; the parsing it feeds is pure.
/// System folders only. A link target may live anywhere a note lives, so this
/// is deliberately wider than the resurface scan scope: `Interesting/` is not
/// synced to Anki but a card may still link into it.
const kLinkTargetExcludes = {'.obsidian', '.trash', '.perspirator', 'Attachments'};

Future<Map<String, String>> buildLinkTargets(
  String vaultPath, {
  Set<String> excludedFolders = kLinkTargetExcludes,
}) async {
  final names = <String, Set<String>>{};
  final aliases = <String, Set<String>>{};

  await for (final file in VaultScanner.scan(vaultPath,
      excludedFolders: excludedFolders)) {
    final relative = p.relative(file.path, from: vaultPath).replaceAll('\\', '/');
    final canonical = relative.endsWith('.md')
        ? relative.substring(0, relative.length - 3)
        : relative;
    for (final key in {canonical, p.basenameWithoutExtension(file.path)}) {
      names.putIfAbsent(key.toLowerCase(), () => <String>{}).add(canonical);
    }
    String content;
    try {
      content = await file.readAsString();
    } on FileSystemException {
      continue;
    }
    for (final alias in parseAliases(splitFrontmatter(content).frontmatter)) {
      final key = alias
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
  return resolved;
}
