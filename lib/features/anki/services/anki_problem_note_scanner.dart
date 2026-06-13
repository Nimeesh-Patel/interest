import 'package:path/path.dart' as p;

import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../models/anki_problem_note.dart';

/// The sync's vault discovery: finds every `***` problem note to push to Anki.
/// Self-contained — depends only on shared Markdown utilities, so the anki
/// feature can scan and sync with no dependency on any viewer. Never throws.
///
/// A problem note is any `.md` whose body (frontmatter stripped) contains a
/// `***` front/back separator outside code fences ([splitFrontBack]). A note
/// with `exclude_resurface: true` frontmatter is skipped (vault convention).
class AnkiProblemNoteScanner {
  static const defaultExcludedFolders = [
    'Interesting',
    '.obsidian',
    'Templates',
    'Attachments',
  ];

  static Future<List<AnkiProblemNote>> scan(
    String vaultPath, {
    List<String> excludedFolders = defaultExcludedFolders,
  }) async {
    final notes = <AnkiProblemNote>[];
    try {
      await for (final entry in VaultScanner.scan(
        vaultPath,
        excludedFolders: excludedFolders.toSet(),
      )) {
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml != null && yaml['exclude_resurface'] == true) continue;
          final fb = splitFrontBack(split.body);
          if (fb == null) continue; // not a problem note
          notes.add(AnkiProblemNote(
            sourcePath: entry.path,
            sourceFile: p.basename(entry.path),
            front: fb.front,
            back: fb.back,
            category: yaml != null && yaml['category'] is String
                ? yaml['category'] as String
                : null,
            tags: yaml != null && yaml['tags'] is List
                ? (yaml['tags'] as List).whereType<String>().toList()
                : const [],
            ankiNoteId: yaml != null && yaml['anki_note_id'] != null
                ? '${yaml['anki_note_id']}'
                : null,
          ));
        } catch (_) {}
      }
    } catch (_) {}
    return notes;
  }
}
