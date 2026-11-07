import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/link_targets.dart';
import '../../../shared/markdown/md_io.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/anki_problem_note.dart';
import 'anki_transport.dart';
import 'anki_sync_lock.dart';

/// A linked note whose card is absent from the observed collection. Cards are
/// only ever created, changed and deleted from Obsidian, so a missing card was
/// not deliberately deleted in Anki: it is either still travelling through
/// AnkiWeb from the other device, or lost. Re-creating an undelivered card
/// makes a duplicate, and only Nimeesh can tell the two apart, so the sync
/// reports it and re-creates it only on confirmation.
class AnkiMissingCard {
  final String sourcePath;
  final String sourceFile;
  final int ankiNoteId;

  /// The note's two sides as authored, and its deck, so a confirmation
  /// shows the card.
  final String problem;
  final String conjecture;
  final String deck;

  const AnkiMissingCard({
    required this.sourcePath,
    required this.sourceFile,
    required this.ankiNoteId,
    this.problem = '',
    this.conjecture = '',
    this.deck = 'Default',
  });

  String get title => p.basenameWithoutExtension(sourceFile);
}

/// An Interest-owned card (its front carries this vault's source link) that no
/// current eligible note links. Its note may have been deleted, stopped being a
/// Problem Note, or not yet reached this device through Obsidian Sync; one
/// device cannot distinguish these, so removal waits for confirmation.
class AnkiOrphanCard {
  final int ankiNoteId;
  final String sourceUri;

  /// Vault-relative note path without extension, decoded from [sourceUri].
  final String noteName;

  /// The card's two sides as plain text (source link removed), so a
  /// confirmation can show exactly which card it would delete.
  final String problem;
  final String conjecture;

  /// Decks holding its cards, and its total reviews: what removal discards.
  final Set<String> decks;
  final int reviews;

  const AnkiOrphanCard({
    required this.ankiNoteId,
    required this.sourceUri,
    required this.noteName,
    this.problem = '',
    this.conjecture = '',
    this.decks = const {},
    this.reviews = 0,
  });

  String get title => p.basename(noteName);

  /// Anki note ids are creation times in milliseconds.
  DateTime get created => DateTime.fromMillisecondsSinceEpoch(ankiNoteId);
}

class AnkiSyncResult {
  final int added;
  final int updated;
  final int unchanged;
  final int failed;
  final int skipped;
  final int retired;

  /// Extra cards removed because their source note links a different card
  /// that is present. Always safe: the note keeps its linked card.
  final int duplicatesRetired;

  /// Awaiting Nimeesh's confirmation; not failures.
  final List<AnkiMissingCard> missing;
  final List<AnkiOrphanCard> orphans;

  /// Vault-relative paths (without `.md`) of the notes whose cards were (or,
  /// in a preview, would be) added or changed, so the outcome can be read
  /// and each note opened, not just counted.
  final List<String> changed;

  /// True when nothing was written: the counts describe what a sync would do.
  final bool preview;

  final List<String> errors;
  final bool completed;

  const AnkiSyncResult({
    required this.added,
    required this.updated,
    this.unchanged = 0,
    required this.failed,
    this.skipped = 0,
    this.retired = 0,
    this.duplicatesRetired = 0,
    this.missing = const [],
    this.orphans = const [],
    this.changed = const [],
    this.preview = false,
    required this.errors,
    this.completed = true,
  });

  /// Cards a sync would add, change or remove.
  int get pending => added + updated + retired + duplicatesRetired;

  bool get isSuccessful => completed && failed == 0 && errors.isEmpty;

  bool get needsDecision => missing.isNotEmpty || orphans.isNotEmpty;

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

/// What every sync and confirmation needs before touching Anki: proof that
/// each source is current, the wikilink targets, and one complete observation
/// of the collection.
typedef _Prepared =
    ({Map<String, String> linkTargets, Map<int, AnkiNoteState> present});

/// Transport-agnostic sync core: problem notes → Anki cards, one-way.
/// Owns everything both transports must agree on — front/back rendering,
/// `category:`→deck mapping (including deck moves on a category change), the
/// obsidian:// wikilink rewrite, and the `anki_note_id` round-trip — so the
/// same note yields the same card whichever transport carries it.
///
/// Each run reads the collection once and writes only differences, so its
/// native cost scales with what changed rather than with the vault.
class AnkiSyncService {
  /// [reconcileCollection] is true only for a complete whole-vault discovery:
  /// classifying unreferenced cards as duplicates or orphans is meaningful
  /// only when [problemNotes] is every eligible note, never for a
  /// file-bounded subset.
  ///
  /// [preview] computes the same outcome without writing to Anki or the vault.
  static Future<AnkiSyncResult> syncVault(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    List<AnkiNoteRetirement> retirements = const [],
    bool reconcileCollection = false,
    bool preview = false,
  }) => _leased(
    vaultPath,
    problemNotes.length + retirements.length,
    () => _syncVault(
      transport,
      problemNotes,
      vaultPath,
      retirements: retirements,
      reconcileCollection: reconcileCollection,
      preview: preview,
    ),
  );

  /// Applies Nimeesh's confirmation of an earlier sync's [AnkiSyncResult.missing]
  /// and [AnkiSyncResult.orphans] against a fresh discovery ([problemNotes],
  /// [retirements]) and a fresh collection observation. Each item is
  /// re-checked: a card that has since arrived is not re-created, and a card a
  /// current note now links is not removed.
  static Future<AnkiSyncResult> resolve(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    List<AnkiNoteRetirement> retirements = const [],
    List<AnkiMissingCard> recreate = const [],
    List<AnkiOrphanCard> retire = const [],
  }) => _leased(
    vaultPath,
    recreate.length + retire.length,
    () => _resolve(
      transport,
      problemNotes,
      vaultPath,
      retirements: retirements,
      recreate: recreate,
      retire: retire,
    ),
  );

  static Future<AnkiSyncResult> _leased(
    String vaultPath,
    int operations,
    Future<AnkiSyncResult> Function() run,
  ) async {
    AnkiSyncLock? lease;
    try {
      lease = await AnkiSyncLock.acquire(vaultPath);
      if (lease == null) {
        return AnkiSyncResult.incomplete(
          skipped: operations,
          errors: [
            'The vault sync is already running or its lock is unavailable. No cards were changed.',
          ],
        );
      }
      return await run();
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Vault sync could not run: $error'],
      );
    } finally {
      await lease?.release();
    }
  }

  /// Returns either the shared preconditions or the incomplete result that
  /// stops the run before any card changes.
  static Future<(_Prepared?, AnkiSyncResult?)> _prepare(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    List<AnkiNoteRetirement> retirements,
    String vaultPath,
    int operations,
  ) async {
    final ineligible =
        [
              ...problemNotes.map((note) => note.sourcePath),
              ...retirements.map((note) => note.sourcePath),
            ]
            .where((path) => !CurrentVaultContent.isEligible(vaultPath, path))
            .map((path) => p.relative(path, from: vaultPath))
            .toList()
          ..sort();
    if (ineligible.isNotEmpty) {
      return (
        null,
        AnkiSyncResult.incomplete(
          failed: ineligible.length,
          skipped: operations - ineligible.length,
          errors: [
            'Refused non-current Problem Notes: ${ineligible.join(', ')}',
          ],
        ),
      );
    }
    // Built once per run: an alias like [[speed of progress]] must reach the
    // note that declares it, not a note of that name that does not exist.
    final builtLinkTargets = await buildLinkTargets(vaultPath);
    if (!builtLinkTargets.isComplete) {
      return (
        null,
        AnkiSyncResult.incomplete(
          skipped: operations,
          errors: [
            'Wikilink-target discovery did not complete; no cards were changed.',
            ...builtLinkTargets.errors,
          ],
        ),
      );
    }
    try {
      final snapshot = await transport.snapshot();
      return (
        (
          linkTargets: builtLinkTargets.targets,
          present: Map.of(snapshot.notes),
        ),
        null,
      );
    } on AnkiSyncAbort catch (error) {
      return (
        null,
        AnkiSyncResult.incomplete(
          skipped: operations,
          errors: ['${error.message}. No cards were changed.'],
        ),
      );
    }
  }

  static Future<AnkiSyncResult> _syncVault(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    required List<AnkiNoteRetirement> retirements,
    required bool reconcileCollection,
    required bool preview,
  }) async {
    final (prepared, stopped) = await _prepare(
      transport,
      problemNotes,
      retirements,
      vaultPath,
      problemNotes.length + retirements.length,
    );
    if (stopped != null) return stopped;
    final linkTargets = prepared!.linkTargets;
    final present = prepared.present;

    int added = 0;
    int updated = 0;
    int unchanged = 0;
    int failed = 0;
    int skipped = 0;
    int retired = 0;
    int duplicatesRetired = 0;
    bool completed = true;
    final errors = <String>[];
    final missing = <AnkiMissingCard>[];
    final orphans = <AnkiOrphanCard>[];
    final changed = <String>[];
    // Vault-relative path without extension: displayable by its last
    // segment and openable in Obsidian.
    String titleOf(AnkiProblemNote note) => p
        .withoutExtension(p.relative(note.sourcePath, from: vaultPath))
        .replaceAll('\\', '/');

    for (final note in retirements) {
      try {
        if (!preview) await _retireCollectionNote(transport, note, vaultPath);
        present.remove(int.parse(note.ankiNoteId));
        retired++;
      } catch (error) {
        failed++;
        errors.add('${note.sourceFile}: $error');
      }
    }

    for (var index = 0; index < problemNotes.length; index++) {
      final note = problemNotes[index];
      try {
        final (front, back) = _renderCard(note, vaultPath, linkTargets);
        final deckName = note.category ?? 'Default';
        final tags = note.tags;
        final idText = note.ankiNoteId;

        if (idText == null) {
          changed.add(titleOf(note));
          if (preview) {
            added++;
            continue;
          }
          final current = await _currentSource(note);
          await _addAndLink(
            transport,
            note,
            deckName,
            front,
            back,
            tags,
            current,
          );
          added++;
          continue;
        }
        final id = int.tryParse(idText);
        if (id == null || id <= 0) {
          failed++;
          errors.add('${note.sourceFile}: invalid anki_note_id "$idText"');
          continue;
        }
        final state = present[id];
        if (state == null) {
          missing.add(
            AnkiMissingCard(
              sourcePath: note.sourcePath,
              sourceFile: note.sourceFile,
              ankiNoteId: id,
              problem: (note.front ?? '').trim(),
              conjecture: (note.back ?? '').trim(),
              deck: deckName,
            ),
          );
          continue;
        }
        final fieldsHeld = state.holds(front, back, tags);
        // `category:` owns the projected deck.
        final deckHeld = state.isInDeck(deckName);
        if (fieldsHeld && deckHeld) {
          unchanged++;
          continue;
        }
        changed.add(titleOf(note));
        if (preview) {
          updated++;
          continue;
        }
        final current = await _currentSource(note);
        if (!fieldsHeld && !await transport.updateNote(id, front, back, tags)) {
          failed++;
          errors.add('${note.sourceFile}: update failed');
          continue;
        }
        if (!deckHeld && !await transport.moveToDeck(id, deckName)) {
          failed++;
          errors.add(
            '${note.sourceFile}: '
            '${fieldsHeld ? '' : 'content updated, but '}deck projection '
            'to "$deckName" failed',
          );
          continue;
        }
        if (await readPreservingUtf8(File(note.sourcePath)) != current) {
          throw const AnkiNoteFailure(
            'Anki received the discovered snapshot, but the source changed during sync; resync is required',
          );
        }
        updated++;
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

    if (reconcileCollection && completed) {
      final referenced = _referencedIds(problemNotes, retirements);
      final owners = {
        for (final note in problemNotes)
          obsidianUri(vaultPath, note.sourcePath): note,
      };
      for (final state in present.values.toList()) {
        if (referenced.contains(state.id)) continue;
        final source = _ownedSource(state.front, vaultPath);
        if (source == null) continue; // not an Interest projection
        final (:sourceUri, :noteName) = source;
        final ownerId = int.tryParse(
          owners[obsidianUriForName(vaultPath, noteName)]?.ankiNoteId ?? '',
        );
        if (ownerId != null && present.containsKey(ownerId)) {
          if (preview) {
            duplicatesRetired++;
            continue;
          }
          try {
            if (await transport.retireNote(state.id, sourceUri)) {
              duplicatesRetired++;
            } else {
              failed++;
              errors.add(
                'Duplicate card ${state.id} for $noteName: could not verify removal',
              );
            }
          } on AnkiNoteFailure catch (e) {
            failed++;
            errors.add('Duplicate card ${state.id}: ${e.message}');
          }
        } else {
          orphans.add(
            AnkiOrphanCard(
              ankiNoteId: state.id,
              sourceUri: sourceUri,
              noteName: noteName,
              problem: _plainText(state.front),
              conjecture: _plainText(state.back),
              decks: state.decks,
              reviews: state.reviews,
            ),
          );
        }
      }
    }

    return AnkiSyncResult(
      added: added,
      updated: updated,
      unchanged: unchanged,
      failed: failed,
      skipped: skipped,
      retired: retired,
      duplicatesRetired: duplicatesRetired,
      missing: missing,
      orphans: orphans,
      changed: changed,
      preview: preview,
      errors: errors,
      completed: completed,
    );
  }

  static Future<AnkiSyncResult> _resolve(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    required List<AnkiNoteRetirement> retirements,
    required List<AnkiMissingCard> recreate,
    required List<AnkiOrphanCard> retire,
  }) async {
    final (prepared, stopped) = await _prepare(
      transport,
      problemNotes,
      retirements,
      vaultPath,
      recreate.length + retire.length,
    );
    if (stopped != null) return stopped;
    final present = prepared!.present;
    final referenced = _referencedIds(problemNotes, retirements);
    final byPath = {for (final note in problemNotes) note.sourcePath: note};

    int added = 0;
    int unchanged = 0;
    int failed = 0;
    int retired = 0;
    final errors = <String>[];

    for (final item in recreate) {
      final note = byPath[item.sourcePath];
      if (note == null || note.ankiNoteId != '${item.ankiNoteId}') {
        failed++;
        errors.add(
          '${item.sourceFile}: the note or its anki_note_id changed; sync again',
        );
        continue;
      }
      if (present.containsKey(item.ankiNoteId)) {
        unchanged++; // arrived meanwhile; re-creating would duplicate it
        continue;
      }
      try {
        final (front, back) = _renderCard(
          note,
          vaultPath,
          prepared.linkTargets,
        );
        await _addAndLink(
          transport,
          note,
          note.category ?? 'Default',
          front,
          back,
          note.tags,
          await _currentSource(note),
        );
        added++;
      } on AnkiSyncAbort catch (e) {
        failed++;
        errors.add('${item.sourceFile}: ${e.message}');
        break;
      } catch (e) {
        failed++;
        errors.add('${item.sourceFile}: $e');
      }
    }

    for (final item in retire) {
      if (referenced.contains(item.ankiNoteId)) {
        unchanged++; // a current note links it again
        continue;
      }
      if (!present.containsKey(item.ankiNoteId)) continue; // already gone
      try {
        if (await transport.retireNote(item.ankiNoteId, item.sourceUri)) {
          retired++;
        } else {
          failed++;
          errors.add('${item.noteName}: could not verify card removal');
        }
      } catch (e) {
        failed++;
        errors.add('${item.noteName}: $e');
      }
    }

    return AnkiSyncResult(
      added: added,
      updated: 0,
      unchanged: unchanged,
      failed: failed,
      retired: retired,
      errors: errors,
    );
  }

  static Set<int> _referencedIds(
    List<AnkiProblemNote> problemNotes,
    List<AnkiNoteRetirement> retirements,
  ) => {
    for (final note in problemNotes)
      if (int.tryParse(note.ankiNoteId ?? '') case final int id) id,
    for (final note in retirements)
      if (int.tryParse(note.ankiNoteId) case final int id) id,
  };

  /// The source link of a card this vault's renderer produced, or null when
  /// the front carries no link into this vault (a card Interest does not own).
  /// [sourceUri] is the link exactly as stored, which the native retirement
  /// guard matches. [noteName] is decoded from the query, so links from an
  /// earlier renderer that wrote spaces as `+` are recognised too.
  static ({String sourceUri, String noteName})? _ownedSource(
    String front,
    String vaultPath,
  ) {
    final match = RegExp(
      r'''href=["'](obsidian://open\?[^"']+)["']''',
    ).firstMatch(front);
    if (match == null) return null;
    final sourceUri = match.group(1)!.replaceAll('&amp;', '&');
    final Map<String, String> query;
    try {
      query = Uri.parse(sourceUri).queryParameters;
    } on FormatException {
      return null;
    }
    final noteName = query['file'];
    if (query['vault'] != p.basename(vaultPath) ||
        noteName == null ||
        noteName.isEmpty) {
      return null;
    }
    return (sourceUri: sourceUri, noteName: noteName);
  }

  /// A card side as readable text: a leading source-link block and all
  /// markup removed, whitespace collapsed.
  static String _plainText(String front) =>
      front
          .replaceFirst(RegExp(r'^\s*<div[^>]*>.*?</div>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// The note's exact current source, refusing a note that changed since
  /// discovery or has become a collection note. Called only before a write.
  static Future<String> _currentSource(AnkiProblemNote note) async {
    final current = await readPreservingUtf8(File(note.sourcePath));
    if (note.sourceContent != current) {
      throw const AnkiNoteFailure(
        'source changed after discovery; rescan before syncing',
      );
    }
    final metadata = parseYamlMap(
      splitFrontmatter(
        current.startsWith('﻿') ? current.substring(1) : current,
      ).frontmatter,
    );
    if (metadata?.containsKey('collection') == true) {
      throw const AnkiNoteFailure(
        'source is now a collection note; rescan before syncing',
      );
    }
    return current;
  }

  static Future<void> _retireCollectionNote(
    AnkiTransport transport,
    AnkiNoteRetirement note,
    String vaultPath,
  ) async {
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
        patch.before.startsWith('﻿') ? patch.before.substring(1) : patch.before,
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

  static Future<void> _addAndLink(
    AnkiTransport transport,
    AnkiProblemNote note,
    String deck,
    String front,
    String back,
    List<String> tags,
    String source,
  ) async {
    final possiblePatch = await prepareFrontmatterField(
      note.sourcePath,
      'anki_note_id',
      '1',
    );
    if (possiblePatch.before != source) {
      throw const AnkiNoteFailure(
        'source changed before creation; rescan before syncing',
      );
    }
    final id = await transport.addNote(deck, front, back, tags);
    if (id <= 0) throw const AnkiNoteFailure('add failed');
    final patch = await _patchAnkiNoteId(
      note.sourcePath,
      id,
      expectedSource: source,
    );
    if (!patch.applied) {
      throw AnkiNoteFailure(
        'Anki note $id was created, but local identity patch failed: ${patch.error}',
      );
    }
    if (!await transport.moveToDeck(id, deck)) {
      throw AnkiNoteFailure(
        'Anki note $id created and linked, but deck projection to "$deck" failed',
      );
    }
    if (await readPreservingUtf8(File(note.sourcePath)) != patch.after) {
      throw const AnkiNoteFailure(
        'Anki was created and linked, but the source changed during deck placement; resync is required',
      );
    }
  }

  /// The sync's ONLY vault write: surgically patches the `anki_note_id`
  /// frontmatter key via [patchFrontmatterField], which preserves the note body
  /// byte-for-byte. No sync code opens or rewrites a note body. Never throws.
  static Future<FilePatchResult> _patchAnkiNoteId(
    String filePath,
    int noteId, {
    required String expectedSource,
  }) async {
    try {
      final patch = await prepareFrontmatterField(
        filePath,
        'anki_note_id',
        '$noteId',
      );
      if (patch.before != expectedSource) {
        return FilePatchResult.failed(
          filePath,
          'source changed during Anki creation; external ID retained in this error for reconciliation',
        );
      }
      return await patch.apply();
    } catch (error) {
      return FilePatchResult.failed(filePath, '$error');
    }
  }
}
