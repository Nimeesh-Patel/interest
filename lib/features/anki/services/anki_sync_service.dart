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
import 'card_criticisms.dart';
import 'card_source_header.dart';
import 'sync_issue.dart';

export 'sync_issue.dart';

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
///
/// When its note exists and links a different card ([noteLinks]), it is an
/// extra card for that note that has been reviewed, so its history would go
/// with it: that removal waits for confirmation too.
class AnkiOrphanCard {
  final int ankiNoteId;
  final String sourceUri;

  /// The card its note links instead, when this is an extra card.
  final int? noteLinks;

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
    this.noteLinks,
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

  /// The errors that concern particular notes or cards, structured so each
  /// can be shown as a card. Every issue's message is also in [errors].
  final List<AnkiSyncIssue> issues;

  /// Source path → [cardFingerprint] of every note whose card Anki now holds
  /// exactly as rendered: unchanged, updated or added in this run.
  final Map<String, String> received;

  /// Source path → the `anki_note_id` this run wrote into it (null: removed).
  /// Recorded even when the run was not clean, because the note on disk
  /// already says it.
  final Map<String, int?> linked;

  const AnkiSyncResult({
    required this.added,
    required this.updated,
    this.unchanged = 0,
    required this.failed,
    this.skipped = 0,
    this.retired = 0,
    this.missing = const [],
    this.orphans = const [],
    this.changed = const [],
    this.preview = false,
    required this.errors,
    this.completed = true,
    this.issues = const [],
    this.received = const {},
    this.linked = const {},
  });

  /// Cards a sync would add, change or remove.
  int get pending => added + updated + retired;

  bool get isSuccessful => completed && failed == 0 && errors.isEmpty;

  bool get needsDecision => missing.isNotEmpty || orphans.isNotEmpty;

  factory AnkiSyncResult.incomplete({
    required List<String> errors,
    int failed = 0,
    int skipped = 0,
    List<AnkiSyncIssue> issues = const [],
  }) => AnkiSyncResult(
    added: 0,
    updated: 0,
    failed: failed,
    skipped: skipped,
    errors: [...errors, ...issues.map((issue) => issue.message)],
    completed: false,
    issues: issues,
  );

  /// The stopping result for [issues] alone: no card was changed.
  factory AnkiSyncResult.stopped(List<AnkiSyncIssue> issues) =>
      AnkiSyncResult.incomplete(errors: const [], issues: issues);
}

/// What a quick sync's discovery decided, inside the run's lease and from
/// the run's one observation of the collection.
sealed class AnkiDiscovery {
  const AnkiDiscovery();
}

/// Sync these notes and withdrawals.
class AnkiSyncPlan extends AnkiDiscovery {
  final List<AnkiProblemNote> notes;
  final List<AnkiNoteRetirement> retirements;
  final Map<String, String> linkTargets;
  final bool reconcileCollection;
  const AnkiSyncPlan({
    required this.notes,
    required this.retirements,
    required this.linkTargets,
    this.reconcileCollection = false,
  });
}

/// Change nothing and report this result.
class AnkiSyncStop extends AnkiDiscovery {
  final AnkiSyncResult result;
  const AnkiSyncStop(this.result);
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
    Map<String, String>? linkTargets,
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
      suppliedTargets: linkTargets,
    ),
  );

  /// Discover and write against one collection observation under one lease.
  static Future<AnkiSyncResult> syncDiscovered(
    AnkiTransport transport,
    String vaultPath,
    Future<AnkiDiscovery> Function(Map<int, AnkiNoteState> present) discover, {
    bool preview = false,
    Future<void> Function(AnkiSyncResult)? record,
  }) => _leased(vaultPath, 0, () async {
    final AnkiCollectionSnapshot observed;
    try {
      observed = await transport.snapshot();
    } on AnkiSyncAbort catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['${error.message}. No cards were changed.'],
      );
    }
    final discovery = await discover(observed.notes);
    if (discovery is AnkiSyncStop) return discovery.result;
    final plan = discovery as AnkiSyncPlan;
    final result = await _syncVault(
      transport,
      plan.notes,
      vaultPath,
      retirements: plan.retirements,
      reconcileCollection: plan.reconcileCollection,
      preview: preview,
      suppliedTargets: plan.linkTargets,
      observed: observed,
    );
    if (!preview) await record?.call(result);
    return result;
  });

  /// Applies Nimeesh's confirmation of an earlier sync's [AnkiSyncResult.missing]
  /// and [AnkiSyncResult.orphans] against a fresh discovery ([problemNotes],
  /// [retirements]) and a fresh collection observation. Each item is
  /// re-checked: a card that has since arrived is not re-created, and a card a
  /// current note now links is not removed.
  ///
  /// [reassign] confirms [AnkiIssueKind.foreignCard] issues: the card goes to
  /// the note that claims it, if the note still claims it and the card is
  /// still the one shown.
  static Future<AnkiSyncResult> resolve(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    List<AnkiNoteRetirement> retirements = const [],
    List<AnkiMissingCard> recreate = const [],
    List<AnkiOrphanCard> retire = const [],
    List<AnkiSyncIssue> reassign = const [],
    Future<void> Function(AnkiSyncResult)? record,
    Map<String, String>? linkTargets,
  }) => _leased(
    vaultPath,
    recreate.length + retire.length + reassign.length,
    () async {
      final result = await _resolve(
        transport,
        problemNotes,
        vaultPath,
        retirements: retirements,
        recreate: recreate,
        retire: retire,
        reassign: reassign,
        linkTargets: linkTargets,
      );
      await record?.call(result);
      return result;
    },
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
    int operations, {
    Map<String, String>? linkTargets,
    AnkiCollectionSnapshot? observed,
  }) async {
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
    // Callers holding every note's aliases already (a scan, the sync
    // manifest) supply the resolved targets instead of a second vault read.
    var targets = linkTargets;
    if (targets == null) {
      final built = await buildLinkTargets(vaultPath);
      if (!built.isComplete) {
        return (
          null,
          AnkiSyncResult.incomplete(
            skipped: operations,
            errors: [
              'Wikilink-target discovery did not complete; no cards were changed.',
              ...built.errors,
            ],
          ),
        );
      }
      targets = built.targets;
    }
    try {
      final snapshot = observed ?? await transport.snapshot();
      return ((linkTargets: targets, present: Map.of(snapshot.notes)), null);
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
    Map<String, String>? suppliedTargets,
    AnkiCollectionSnapshot? observed,
  }) async {
    final (prepared, stopped) = await _prepare(
      transport,
      problemNotes,
      retirements,
      vaultPath,
      problemNotes.length + retirements.length,
      linkTargets: suppliedTargets,
      observed: observed,
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
    bool completed = true;
    final errors = <String>[];
    final issues = <AnkiSyncIssue>[];
    final missing = <AnkiMissingCard>[];
    final orphans = <AnkiOrphanCard>[];
    final changed = <String>[];
    final received = <String, String>{};
    final linked = <String, int?>{};

    void noteFailed(String sourcePath, String sourceFile, String reason) {
      failed++;
      final message = '$sourceFile: $reason';
      errors.add(message);
      issues.add(
        AnkiSyncIssue(
          kind: AnkiIssueKind.noteFailed,
          message: message,
          notes: [_noteName(vaultPath, sourcePath)],
        ),
      );
    }

    for (final note in retirements) {
      try {
        if (!preview) {
          await _retireCollectionNote(transport, note, vaultPath);
          linked[note.sourcePath] = null;
        }
        present.remove(int.parse(note.ankiNoteId));
        retired++;
      } catch (error) {
        noteFailed(note.sourcePath, note.sourceFile, '$error');
      }
    }

    for (var index = 0; index < problemNotes.length; index++) {
      final note = problemNotes[index];
      try {
        final (front, back) = _renderCard(note, vaultPath, linkTargets);
        final deckName = note.category ?? 'Default';
        final tags = note.tags;
        final idText = note.ankiNoteId;
        final rendered = cardFingerprint(front, back, tags, [deckName]);

        if (idText == null) {
          changed.add(_noteName(vaultPath, note.sourcePath));
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
            onLinked: (id) => linked[note.sourcePath] = id,
          );
          received[note.sourcePath] = rendered;
          added++;
          continue;
        }
        final id = int.tryParse(idText);
        if (id == null || id <= 0) {
          noteFailed(
            note.sourcePath,
            note.sourceFile,
            'invalid anki_note_id "$idText"',
          );
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
        final claimed = _claimedElsewhere(state, note, vaultPath);
        if (claimed != null) {
          failed++;
          errors.add(claimed.message);
          issues.add(claimed);
          continue;
        }
        final fieldsHeld = state.holds(front, back, tags);
        // `category:` owns the projected deck.
        final deckHeld = state.isInDeck(deckName);
        if (fieldsHeld && deckHeld) {
          received[note.sourcePath] = rendered;
          unchanged++;
          continue;
        }
        changed.add(_noteName(vaultPath, note.sourcePath));
        if (preview) {
          updated++;
          continue;
        }
        await _writeProjection(transport, note, state, front, back);
        received[note.sourcePath] = rendered;
        updated++;
      } on AnkiSyncAbort catch (e) {
        noteFailed(note.sourcePath, note.sourceFile, e.message);
        skipped = problemNotes.length - index - 1;
        completed = false;
        break;
      } on AnkiNoteFailure catch (e) {
        noteFailed(note.sourcePath, note.sourceFile, e.message);
      } catch (e) {
        noteFailed(note.sourcePath, note.sourceFile, '$e');
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
        final owner = owners[obsidianUriForName(vaultPath, noteName)];
        final ownerId = int.tryParse(owner?.ankiNoteId ?? '');
        final linkedCard = ownerId == null ? null : present[ownerId];
        orphans.add(
          _orphan(state, sourceUri, noteName, noteLinks: linkedCard?.id),
        );
      }
    }

    return AnkiSyncResult(
      added: added,
      updated: updated,
      unchanged: unchanged,
      failed: failed,
      skipped: skipped,
      retired: retired,
      missing: missing,
      orphans: orphans,
      changed: changed,
      preview: preview,
      errors: errors,
      completed: completed,
      issues: issues,
      received: preview ? const {} : received,
      linked: linked,
    );
  }

  static AnkiOrphanCard _orphan(
    AnkiNoteState state,
    String sourceUri,
    String noteName, {
    int? noteLinks,
  }) => AnkiOrphanCard(
    ankiNoteId: state.id,
    sourceUri: sourceUri,
    noteName: noteName,
    noteLinks: noteLinks,
    problem: _plainText(state.front),
    conjecture: _plainText(CardCriticisms.withoutSection(state.back)),
    decks: state.decks,
    reviews: state.reviews,
  );

  /// A note's vault-relative path without `.md`, `/`-separated: the name its
  /// card's source link carries, and what Obsidian opens.
  static String _noteName(String vaultPath, String sourcePath) => p
      .withoutExtension(p.relative(sourcePath, from: vaultPath))
      .replaceAll('\\', '/');

  /// The issue when [note] links card [state] but the card was made from a
  /// different note that still exists: updating it would give that note's
  /// review history to [note]. A card whose source note no longer exists was
  /// renamed or merged into [note], so it is [note]'s. Names compare without
  /// case, because Android's and Windows' storage do.
  static AnkiSyncIssue? _claimedElsewhere(
    AnkiNoteState state,
    AnkiProblemNote note,
    String vaultPath,
  ) {
    final source = _ownedSource(state.front, vaultPath);
    if (source == null) return null;
    final self = _noteName(vaultPath, note.sourcePath);
    final owner = source.noteName;
    if (owner.toLowerCase() == self.toLowerCase()) return null;
    if (!File(p.join(vaultPath, '$owner.md')).existsSync()) return null;
    return AnkiSyncIssue(
      kind: AnkiIssueKind.foreignCard,
      message:
          '"$self" has anki_note_id ${state.id}, but that card was made from '
          '"$owner", which still exists. Updating it would give "$owner"\'s '
          'review history to "$self", so "$self" was not synced.',
      notes: [self, owner],
      cardId: state.id,
      cardSource: owner,
      cardProblem: _plainText(state.front),
      cardConjecture: _plainText(CardCriticisms.withoutSection(state.back)),
      cardReviews: state.reviews,
    );
  }

  static Future<AnkiSyncResult> _resolve(
    AnkiTransport transport,
    List<AnkiProblemNote> problemNotes,
    String vaultPath, {
    required List<AnkiNoteRetirement> retirements,
    required List<AnkiMissingCard> recreate,
    required List<AnkiOrphanCard> retire,
    required List<AnkiSyncIssue> reassign,
    Map<String, String>? linkTargets,
  }) async {
    final (prepared, stopped) = await _prepare(
      transport,
      problemNotes,
      retirements,
      vaultPath,
      recreate.length + retire.length + reassign.length,
      linkTargets: linkTargets,
    );
    if (stopped != null) return stopped;
    final present = prepared!.present;
    final referenced = _referencedIds(problemNotes, retirements);
    final byPath = {for (final note in problemNotes) note.sourcePath: note};
    final byName = {
      for (final note in problemNotes)
        _noteName(vaultPath, note.sourcePath): note,
    };

    int added = 0;
    int updated = 0;
    int unchanged = 0;
    int failed = 0;
    int retired = 0;
    final errors = <String>[];
    final linked = <String, int?>{};

    for (final claim in reassign) {
      final name = claim.notes.first;
      final note = byName[name];
      final id = claim.cardId;
      final state = id == null ? null : present[id];
      // Act only on what was shown: the note still claims this card, and the
      // card still names the note it was made from when Nimeesh saw it.
      if (claim.kind != AnkiIssueKind.foreignCard ||
          note == null ||
          state == null ||
          note.ankiNoteId != '$id' ||
          _ownedSource(state.front, vaultPath)?.noteName != claim.cardSource) {
        failed++;
        errors.add('"$name": the note or its card changed; sync again');
        continue;
      }
      try {
        final (front, back) = _renderCard(
          note,
          vaultPath,
          prepared.linkTargets,
        );
        await _writeProjection(transport, note, state, front, back);
        updated++;
      } on AnkiSyncAbort catch (e) {
        failed++;
        errors.add('"$name": ${e.message}');
        break;
      } catch (e) {
        failed++;
        errors.add('"$name": $e');
      }
    }

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
          onLinked: (id) => linked[note.sourcePath] = id,
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
      updated: updated,
      unchanged: unchanged,
      failed: failed,
      retired: retired,
      errors: errors,
      linked: linked,
    );
  }

  /// The note (vault-relative, without `.md`) a card's own link names, or
  /// null when the card is not an Interest projection of this vault.
  static String? sourceNoteOf(String front, String vaultPath) =>
      _ownedSource(front, vaultPath)?.noteName;

  /// A card side as readable text, as decisions and issues show it.
  static String plainTextOf(String html) => _plainText(html);

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
  ///
  /// The link ends at the quote that opened it, not at any quote: note names
  /// keep apostrophes unencoded ("The Pattern's cause"), and stopping at the
  /// first `'` read that card as "The Pattern"'s.
  static ({String sourceUri, String noteName})? _ownedSource(
    String front,
    String vaultPath,
  ) {
    final match = RegExp(
      r'''href=(?:"(obsidian://open\?[^"]+)"|'(obsidian://open\?[^']+)')''',
    ).firstMatch(front);
    if (match == null) return null;
    final sourceUri = (match.group(1) ?? match.group(2)!).replaceAll(
      '&amp;',
      '&',
    );
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
  /// Apply a projection to the already verified card and leave its review state alone.
  static Future<void> _writeProjection(
    AnkiTransport transport,
    AnkiProblemNote note,
    AnkiNoteState state,
    String front,
    String back,
  ) async {
    final current = await _currentSource(note);
    final deck = note.category ?? 'Default';
    final fieldsHeld = state.holds(front, back, note.tags);
    if (!fieldsHeld &&
        !await transport.updateNote(state.id, front, back, note.tags)) {
      throw const AnkiNoteFailure('update failed');
    }
    if (!state.isInDeck(deck) && !await transport.moveToDeck(state.id, deck)) {
      throw AnkiNoteFailure(
        '${fieldsHeld ? '' : 'content updated, but '}deck projection to "$deck" failed',
      );
    }
    if (await readPreservingUtf8(File(note.sourcePath)) != current) {
      throw const AnkiNoteFailure(
        'Anki received the discovered snapshot, but the source changed during sync; resync is required',
      );
    }
  }

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
    final front =
        CardSourceHeader.html(obsUri, noteDisplayName) +
        _markdownToAnkiHtml(note.front ?? '', vaultPath, linkTargets);
    // The conjecture, then whatever is still open against the note: the
    // objection is recovered at reveal, after his own first thought.
    final back =
        _markdownToAnkiHtml(note.back ?? '', vaultPath, linkTargets) +
        CardCriticisms.html(
          note.criticisms,
          (target) => obsidianUriForName(
            vaultPath,
            resolveLinkTarget(target, linkTargets),
          ),
        );
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
    String source, {
    void Function(int id)? onLinked,
  }) async {
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
    onLinked?.call(id);
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
