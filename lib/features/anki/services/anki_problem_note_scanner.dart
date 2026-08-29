import 'package:path/path.dart' as p;

import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/anki_problem_note.dart';

class AnkiProblemNoteScanResult {
  final List<AnkiProblemNote> notes;
  final List<String> errors;

  /// Number of otherwise syncable records found before duplicate identities
  /// were withheld.
  final int candidateCount;
  final int conflictedRecords;

  const AnkiProblemNoteScanResult({
    required this.notes,
    required this.errors,
    required this.candidateCount,
    required this.conflictedRecords,
  });

  bool get isComplete => errors.isEmpty;
}

/// The sync's vault discovery: finds every `***` problem note to push to Anki.
/// Self-contained — depends only on shared Markdown utilities, so the anki
/// feature can scan and sync with no dependency on any viewer. Never throws;
/// incomplete traversal, unreadable files, and ambiguous external identities
/// are explicit non-success outcomes.
///
/// A problem note is any `.md` whose body (frontmatter stripped) contains a
/// `***` front/back separator outside code fences ([splitFrontBack]). A note
/// with `exclude_resurface: true` frontmatter is skipped (vault convention).
class AnkiProblemNoteScanner {
  static Future<AnkiProblemNoteScanResult> scan(
    String vaultPath, {
    List<String> excludedFolders = const [],
  }) async {
    final notes = <AnkiProblemNote>[];
    final errors = <String>[];
    try {
      final scanned = await CurrentVaultContent.scan(
        vaultPath,
        use: CurrentVaultUse.ankiProblemNote,
        additionalExcludedFolders: excludedFolders,
      );
      errors.addAll(scanned.errors);
      for (final entry in scanned.files) {
        try {
          final content = await entry.readAsString();
          final split = splitFrontmatter(content);
          final yaml = parseYamlMap(split.frontmatter);
          if (yaml != null && yaml['exclude_resurface'] == true) continue;
          final fb = splitFrontBack(split.body);
          if (fb == null) continue; // not a problem note
          notes.add(
            AnkiProblemNote(
              sourcePath: entry.path,
              sourceFile: p.basename(entry.path),
              front: fb.front,
              back: fb.back,
              category:
                  yaml != null && yaml['category'] is String
                      ? yaml['category'] as String
                      : null,
              tags:
                  yaml != null && yaml['tags'] is List
                      ? (yaml['tags'] as List).whereType<String>().toList()
                      : const [],
              ankiNoteId:
                  yaml != null && yaml['anki_note_id'] != null
                      ? '${yaml['anki_note_id']}'
                      : null,
            ),
          );
        } catch (error) {
          final relative = p.relative(entry.path, from: vaultPath);
          errors.add('Could not read Problem Note "$relative": $error');
        }
      }
    } catch (error) {
      errors.add('Problem Note discovery failed: $error');
    }

    final candidateCount = notes.length;
    final byExternalId = <String, List<AnkiProblemNote>>{};
    for (final note in notes) {
      final id = note.ankiNoteId;
      if (id != null && id.isNotEmpty) {
        byExternalId.putIfAbsent(id, () => []).add(note);
      }
    }

    final conflictedIds = <String>{};
    var conflictedRecords = 0;
    final sortedIds = byExternalId.keys.toList()..sort();
    for (final id in sortedIds) {
      final matches = byExternalId[id]!;
      if (matches.length < 2) continue;
      conflictedIds.add(id);
      conflictedRecords += matches.length;
      final paths =
          matches
              .map((note) => p.relative(note.sourcePath, from: vaultPath))
              .toList()
            ..sort();
      errors.add('Duplicate active anki_note_id "$id": ${paths.join(', ')}');
    }

    return AnkiProblemNoteScanResult(
      notes: [
        for (final note in notes)
          if (note.ankiNoteId == null ||
              !conflictedIds.contains(note.ankiNoteId))
            note,
      ],
      errors: errors,
      candidateCount: candidateCount,
      conflictedRecords: conflictedRecords,
    );
  }
}
