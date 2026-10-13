import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/link_targets.dart';
import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/anki_problem_note.dart';
import 'anki_transport.dart';

class AnkiSyncResult {
  final int added;
  final int updated;
  final int failed;
  final int skipped;
  final int retired;
  final List<String> errors;
  final bool completed;

  const AnkiSyncResult({
    required this.added,
    required this.updated,
    required this.failed,
    this.skipped = 0,
    this.retired = 0,
    required this.errors,
    this.completed = true,
  });

  bool get isSuccessful => completed && failed == 0 && errors.isEmpty;

  factory AnkiSyncResult.incomplete({
    required List<String> errors,
    int failed = 0,
    int skipped = 0,
  }) => AnkiSyncResult(
    added: 0,
    updated: 0,
    failed: failed,
    skipped: skipped,
    errors: errors,
    completed: false,
  );
}

/// Transport-agnostic sync core: problem notes → Anki cards, one-way.
/// Owns everything both transports must agree on — front/back rendering,
/// `category:`→deck mapping (including deck moves on a category change), the
/// obsidian:// wikilink rewrite, and the `anki_note_id` round-trip — so the
/// same note yields the same card whichever transport carries it.
class AnkiSyncService {
  static Future<AnkiSyncResult> syncVault(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    List<AnkiNoteRetirement> retirements = const [],
  }) async {
    int added = 0;
    int updated = 0;
    int failed = 0;
    int skipped = 0;
    int retired = 0;
    bool completed = true;
    final errors = <String>[];

    final sourcePaths = [
      ...problemNotes.map((note) => note.sourcePath),
      ...retirements.map((note) => note.sourcePath),
    ];
    final ineligible =
        sourcePaths
            .where(
              (note) =>
                  !CurrentVaultContent.isEligible(
                    vaultPath,
                    note,
                    use: CurrentVaultUse.ankiProblemNote,
                  ),
            )
            .toList();
    if (ineligible.isNotEmpty) {
      final paths =
          ineligible.map((path) => p.relative(path, from: vaultPath)).toList()
            ..sort();
      return AnkiSyncResult.incomplete(
        failed: ineligible.length,
        skipped: sourcePaths.length - ineligible.length,
        errors: ['Refused non-current Problem Notes: ${paths.join(', ')}'],
      );
    }
    // Built once per sync: an alias like [[speed of progress]] must reach
    // the note that declares it, not a note of that name that does not exist.
    final builtLinkTargets = await buildLinkTargets(vaultPath);
    if (!builtLinkTargets.isComplete) {
      return AnkiSyncResult.incomplete(
        skipped: sourcePaths.length,
        errors: [
          'Wikilink-target discovery did not complete; no cards were changed.',
          ...builtLinkTargets.errors,
        ],
      );
    }
    final linkTargets = builtLinkTargets.targets;

    for (final note in retirements) {
      try {
        final id = int.tryParse(note.ankiNoteId);
        if (id == null || id <= 0) {
          throw const AnkiNoteFailure('invalid anki_note_id for retirement');
        }
        // Validate removal before deleting the external projection. A later
        // source edit still prevents the prepared patch from being applied.
        final patch = await prepareFrontmatterField(
          note.sourcePath,
          'anki_note_id',
          null,
        );
        final yaml = parseYamlMap(
          splitFrontmatter(
            patch.before.startsWith('\uFEFF')
                ? patch.before.substring(1)
                : patch.before,
          ).frontmatter,
        );
        if (yaml?.containsKey('collection') != true ||
            yaml?['anki_note_id']?.toString() != note.ankiNoteId) {
          throw const AnkiNoteFailure(
            'source role or Anki identity changed before retirement',
          );
        }
        if (!await transport.retireNote(
          id,
          obsidianUri(vaultPath, note.sourcePath),
        )) {
          throw const AnkiNoteFailure(
            'could not verify Anki retirement; local ID retained',
          );
        }
        final applied = await patch.apply();
        if (!applied.applied) {
          throw AnkiNoteFailure(
            'Anki projection retired, but local identity removal failed: ${applied.error}',
          );
        }
        retired++;
      } catch (error) {
        failed++;
        errors.add('${note.sourceFile}: $error');
      }
    }

    for (var index = 0; index < problemNotes.length; index++) {
      final note = problemNotes[index];
      try {
        final current = await readPreservingUtf8(File(note.sourcePath));
        final metadata = parseYamlMap(
          splitFrontmatter(
            current.startsWith('\uFEFF') ? current.substring(1) : current,
          ).frontmatter,
        );
        if (metadata?.containsKey('collection') == true) {
          throw const AnkiNoteFailure(
            'source is now a collection note; rescan before syncing',
          );
        }
        final (front, back) = _renderCard(note, vaultPath, linkTargets);
        final deckName = note.category ?? 'Default';
        final tags = note.tags;
        final ankiNoteId = note.ankiNoteId;

        if (ankiNoteId != null) {
          final noteIdLong = int.tryParse(ankiNoteId);
          if (noteIdLong == null || noteIdLong <= 0) {
            failed++;
            errors.add(
              '${note.sourceFile}: invalid anki_note_id "$ankiNoteId"',
            );
            continue;
          }
          final exists = await transport.noteExists(noteIdLong);
          if (exists == null) {
            failed++;
            errors.add(
              '${note.sourceFile}: could not verify whether Anki note '
              '$noteIdLong exists',
            );
            continue;
          }
          if (exists) {
            final ok = await transport.updateNote(
              noteIdLong,
              front,
              back,
              tags,
            );
            if (ok) {
              // `category:` owns the projected deck. Applying the requested
              // deck idempotently avoids a read-before-write race and prevents
              // an unavailable deck observation from silently skipping it.
              final moved = await transport.moveToDeck(noteIdLong, deckName);
              if (!moved) {
                failed++;
                errors.add(
                  '${note.sourceFile}: content updated, but deck projection '
                  'to "$deckName" failed',
                );
                continue;
              }
              updated++;
            } else {
              failed++;
              errors.add('${note.sourceFile}: update failed');
            }
          } else {
            // Note was deleted from Anki — re-add and write new ID back.
            final newId = await transport.addNote(deckName, front, back, tags);
            if (newId > 0) {
              final patch = await _patchAnkiNoteId(note.sourcePath, newId);
              if (patch.applied) {
                if (await transport.moveToDeck(newId, deckName)) {
                  added++;
                } else {
                  failed++;
                  errors.add(
                    '${note.sourceFile}: Anki note $newId created and linked, but deck projection to "$deckName" failed',
                  );
                }
              } else {
                failed++;
                errors.add(
                  '${note.sourceFile}: Anki note $newId was created, '
                  'but local identity patch failed: ${patch.error}',
                );
              }
            } else {
              failed++;
              errors.add('${note.sourceFile}: add failed after missing note');
            }
          }
        } else {
          final newId = await transport.addNote(deckName, front, back, tags);
          if (newId > 0) {
            final patch = await _patchAnkiNoteId(note.sourcePath, newId);
            if (patch.applied) {
              if (await transport.moveToDeck(newId, deckName)) {
                added++;
              } else {
                failed++;
                errors.add(
                  '${note.sourceFile}: Anki note $newId created and linked, but deck projection to "$deckName" failed',
                );
              }
            } else {
              failed++;
              errors.add(
                '${note.sourceFile}: Anki note $newId was created, '
                'but local identity patch failed: ${patch.error}',
              );
            }
          } else {
            failed++;
            errors.add('${note.sourceFile}: add failed');
          }
        }
      } on AnkiSyncAbort catch (e) {
        failed++;
        skipped = problemNotes.length - index - 1;
        completed = false;
        errors.add('${note.sourceFile}: ${e.message}');
        break;
      } on AnkiNoteFailure catch (e) {
        failed++;
        errors.add('${note.sourceFile}: ${e.message}');
      } catch (e) {
        failed++;
        errors.add('${note.sourceFile}: $e');
      }
    }

    return AnkiSyncResult(
      added: added,
      updated: updated,
      failed: failed,
      skipped: skipped,
      retired: retired,
      errors: errors,
      completed: completed,
    );
  }

  /// Renders a problem note's (front, back) card HTML. The front is
  /// prepended with the right-aligned Obsidian source link.
  static (String, String) _renderCard(
    AnkiProblemNote note,
    String vaultPath, [
    Map<String, String>? linkTargets,
  ]) {
    final noteDisplayName = p.basenameWithoutExtension(note.sourcePath);
    final obsUri = obsidianUri(vaultPath, note.sourcePath);
    final obsLinkHtml =
        '<div style="text-align:right;font-size:0.75em;margin-bottom:6px;opacity:0.6;">'
        '<a href="$obsUri">$noteDisplayName ↗</a>'
        '</div>';
    final front =
        obsLinkHtml +
        _markdownToAnkiHtml(note.front ?? '', vaultPath, linkTargets);
    final back = _markdownToAnkiHtml(note.back ?? '', vaultPath, linkTargets);
    return (front, back);
  }

  /// Converts card Markdown to HTML. Wikilinks become `obsidian://open` links
  /// to the target note (note traversal lives in Obsidian, where the *** note
  /// renderer plugin shows the card with tap-to-reveal). Single newlines —
  /// collapsed to a space by standard Markdown — are promoted to hard breaks
  /// so the note's visual line structure survives into the card.
  static String _markdownToAnkiHtml(
    String text,
    String vaultPath, [
    Map<String, String>? linkTargets,
  ]) {
    // Normalize line endings first so the lone-newline detection below is not
    // defeated by CRLF (where a paragraph break is "\r\n\r\n").
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rewritten = rewriteWikilinksToHtml(normalized, (target, display) {
      final href = obsidianUriForName(
        vaultPath,
        resolveLinkTarget(target, linkTargets),
      );
      return '<a href="$href">$display</a>';
    });
    final hardWrapped = rewritten.replaceAll(
      RegExp(r'(?<!\n)\n(?!\n)'),
      '  \n',
    );
    return md.markdownToHtml(
      hardWrapped,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
  }

  /// The sync's ONLY vault write: surgically patches the `anki_note_id`
  /// frontmatter key via [patchFrontmatterField], which preserves the note body
  /// byte-for-byte. No sync code opens or rewrites a note body. Never throws.
  static Future<FilePatchResult> _patchAnkiNoteId(
    String filePath,
    int noteId,
  ) => patchFrontmatterField(filePath, 'anki_note_id', '$noteId');
}
