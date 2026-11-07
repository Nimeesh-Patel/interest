import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/anki_problem_note.dart';
import '../../../shared/markdown/md_io.dart';

class AnkiProblemNoteScanResult {
  final List<AnkiProblemNote> notes;
  final List<AnkiNoteRetirement> retirements;
  final List<String> errors;

  /// Number of otherwise syncable records found before duplicate identities
  /// were withheld.
  final int candidateCount;
  final int conflictedRecords;
  final int retirementCandidateCount;

  const AnkiProblemNoteScanResult({
    required this.notes,
    this.retirements = const [],
    required this.errors,
    required this.candidateCount,
    required this.conflictedRecords,
    this.retirementCandidateCount = 0,
  });

  bool get isComplete => errors.isEmpty;
  int get operationCount => candidateCount + retirementCandidateCount;
}

/// Discovers review-ready `***` notes and linked collection withdrawals.
/// Self-contained — depends only on shared Markdown utilities, so the anki
/// feature can scan and sync with no dependency on any viewer. Never throws;
/// incomplete traversal, unreadable files, and ambiguous external identities
/// are explicit non-success outcomes.
///
/// A problem note is any `.md` whose body (frontmatter stripped) contains a
/// `***` front/back separator outside code fences ([splitFrontBack]). A note
/// with collection membership opts out; a former Anki link is retired. Other
/// notes with `exclude_resurface: true` frontmatter are skipped.
class AnkiProblemNoteScanner {
  static Future<AnkiProblemNoteScanResult> scan(String vaultPath) async {
    final notes = <AnkiProblemNote>[];
    final retirements = <AnkiNoteRetirement>[];
    final errors = <String>[];
    try {
      final scanned = await CurrentVaultContent.scan(vaultPath);
      errors.addAll(scanned.errors);
      for (final entry in scanned.files) {
        await _read(vaultPath, entry, notes, retirements, errors);
      }
    } catch (error) {
      errors.add('Problem Note discovery failed: $error');
    }
    return _withoutConflicts(vaultPath, notes, retirements, errors);
  }

  /// Discovers only [paths] (absolute, inside [vaultPath]), for the edit
  /// cycle: one note changed in Obsidian, so only it is read. A path that is
  /// not a current eligible note is an error, never a silent skip. Duplicate
  /// identities are checked among [paths] only; the whole-vault [scan] owns
  /// the vault-wide check.
  static Future<AnkiProblemNoteScanResult> scanPaths(
    String vaultPath,
    List<String> paths,
  ) async {
    final notes = <AnkiProblemNote>[];
    final retirements = <AnkiNoteRetirement>[];
    final errors = <String>[];
    for (final path in paths) {
      final relative = p.relative(path, from: vaultPath);
      if (!path.toLowerCase().endsWith('.md') ||
          !CurrentVaultContent.isEligible(vaultPath, path)) {
        errors.add('"$relative" is not a current note of this vault');
        continue;
      }
      final file = File(path);
      if (!await file.exists()) {
        errors.add('"$relative" does not exist on this device yet');
        continue;
      }
      await _read(vaultPath, file, notes, retirements, errors);
    }
    return _withoutConflicts(vaultPath, notes, retirements, errors);
  }

  static Future<void> _read(
    String vaultPath,
    File entry,
    List<AnkiProblemNote> notes,
    List<AnkiNoteRetirement> retirements,
    List<String> errors,
  ) async {
    try {
      final content = await readPreservingUtf8(entry);
      final split = splitFrontmatter(
        content.startsWith('﻿') ? content.substring(1) : content,
      );
      final yaml = parseYamlMap(split.frontmatter);
      if (yaml == null && split.frontmatter?.trim().isNotEmpty == true) {
        throw const FormatException('frontmatter must be a valid YAML mapping');
      }
      final ankiNoteId = yaml?['anki_note_id']?.toString();
      if (yaml?.containsKey('collection') == true) {
        if (ankiNoteId != null && ankiNoteId.isNotEmpty) {
          retirements.add(
            AnkiNoteRetirement(
              sourcePath: entry.path,
              sourceFile: p.basename(entry.path),
              ankiNoteId: ankiNoteId,
            ),
          );
        }
        return;
      }
      if (yaml != null && yaml['exclude_resurface'] == true) return;
      final fb = splitFrontBack(split.body);
      if (fb == null) return; // not a problem note
      notes.add(
        AnkiProblemNote(
          sourcePath: entry.path,
          sourceFile: p.basename(entry.path),
          front: fb.front,
          back: fb.back,
          category: _deckCategory(yaml?['category']),
          tags:
              yaml != null && yaml['tags'] is List
                  ? (yaml['tags'] as List).whereType<String>().toList()
                  : const [],
          ankiNoteId: ankiNoteId,
          sourceContent: content,
        ),
      );
    } catch (error) {
      final relative = p.relative(entry.path, from: vaultPath);
      errors.add('Could not read Problem Note "$relative": $error');
    }
  }

  static AnkiProblemNoteScanResult _withoutConflicts(
    String vaultPath,
    List<AnkiProblemNote> notes,
    List<AnkiNoteRetirement> retirements,
    List<String> errors,
  ) {
    final candidateCount = notes.length;
    final byExternalId = <String, List<String>>{};
    for (final note in notes) {
      final id = note.ankiNoteId;
      if (id != null && id.isNotEmpty) {
        byExternalId.putIfAbsent(id, () => []).add(note.sourcePath);
      }
    }
    for (final retirement in retirements) {
      byExternalId
          .putIfAbsent(retirement.ankiNoteId, () => [])
          .add(retirement.sourcePath);
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
          matches.map((path) => p.relative(path, from: vaultPath)).toList()
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
      retirements: [
        for (final retirement in retirements)
          if (!conflictedIds.contains(retirement.ankiNoteId)) retirement,
      ],
      errors: errors,
      candidateCount: candidateCount,
      conflictedRecords: conflictedRecords,
      retirementCandidateCount: retirements.length,
    );
  }

  /// Obsidian properties may serialize a single deck as a one-item YAML list.
  /// One Basic note has one deck; ambiguous metadata must not become Default.
  static String? _deckCategory(Object? value) {
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is List && value.every((item) => item is String)) {
      final names =
          value
              .cast<String>()
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty)
              .toSet();
      if (names.isEmpty) return null;
      if (names.length == 1) return names.single;
    }
    throw const FormatException(
      'category must name one deck: a string or a one-item text list',
    );
  }
}
