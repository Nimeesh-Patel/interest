import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/vault_paths.dart';
import 'link_targets.dart';
import 'md_utils.dart';

/// The wikilink targets of the last whole-vault resolution, kept in the
/// device-local `.interest/` folder.
///
/// A one-note sync reads only its note, but rendering `[[speed of progress]]`
/// correctly needs to know which note declares that alias, which otherwise
/// means reading every note. The cache answers that from the last whole-vault
/// sync, and is trusted only where it can be checked cheaply: an entry is used
/// only if its target file still exists. A link the cache cannot vouch for
/// keeps its own text, which Obsidian resolves by name, so a stale cache can
/// lose an alias but never send a link to a note that is gone.
class LinkTargetCache {
  LinkTargetCache._();

  static Future<void> save(String vaultPath, Map<String, String> targets) async {
    try {
      final file = File(VaultPaths.linkTargets(vaultPath));
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(targets), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // A cache that could not be written only makes the next one-note sync
      // read the vault; it never affects correctness.
    }
  }

  static Future<Map<String, String>?> _load(String vaultPath) async {
    try {
      final raw = await File(VaultPaths.linkTargets(vaultPath)).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return null;
    }
  }

  /// The targets needed to render [texts]: only the keys their wikilinks use,
  /// each checked to still exist. With no cache yet, resolves the vault once
  /// (and caches it) so the first one-note sync is correct, just not fast.
  static Future<Map<String, String>> forTexts(
    String vaultPath,
    Iterable<String> texts,
  ) async {
    final keys = <String>{};
    for (final text in texts) {
      rewriteWikilinksToHtml(text, (target, display) {
        final hash = target.indexOf('#');
        final base = hash < 0 ? target : target.substring(0, hash);
        keys.add(base.replaceAll('\\', '/').trim().toLowerCase());
        return '';
      });
    }
    if (keys.isEmpty) return const {};

    var cached = await _load(vaultPath);
    if (cached == null) {
      final built = await buildLinkTargets(vaultPath);
      if (built.isComplete) await save(vaultPath, built.targets);
      cached = built.targets;
    }
    final targets = <String, String>{};
    for (final key in keys) {
      final hit = cached[key];
      if (hit == null) continue;
      final path = p.join(vaultPath, hit);
      if (await File('$path.md').exists() || await File(path).exists()) {
        targets[key] = hit;
      }
    }
    return targets;
  }
}
