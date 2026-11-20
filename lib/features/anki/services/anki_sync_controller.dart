import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/link_targets.dart';
import '../../../shared/markdown/md_io.dart';
import 'anki_problem_note_scanner.dart';
import 'anki_sync_lock.dart';
import 'anki_sync_service.dart';
import 'anki_transport.dart';
import 'card_relations.dart';
import 'sync_manifest.dart';

class AnkiSyncController {
  /// Discover either the whole vault or the files that need to be revisited.
  static Future<AnkiSyncResult?> sync(
    AnkiTransport transport, {
    bool preview = false,
  }) => _sync(transport, preview: preview);

  /// The note button also revisits files whose card or link targets changed.
  static Future<AnkiSyncResult?> syncChanged(AnkiTransport transport) =>
      _sync(transport, changedOnly: true);

  static Future<AnkiSyncResult?> _sync(
    AnkiTransport transport, {
    bool changedOnly = false,
    bool preview = false,
  }) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final clock = Stopwatch()..start();
      var startedAt = 0;
      var facts = <String, NoteFacts>{};
      var base = <String, NoteFacts>{};
      var summary = 'whole vault';

      return await AnkiSyncService.syncDiscovered(
        transport,
        vaultPath,
        (present) async {
          startedAt = DateTime.now().millisecondsSinceEpoch;
          final manifest = await SyncManifest.load(vaultPath);
          Future<AnkiDiscovery> wholeVault() async {
            final scanned = await AnkiProblemNoteScanner.scan(vaultPath);
            if (!scanned.isComplete) {
              return AnkiSyncStop(
                _scanStop(
                  scanned,
                  'Problem Note discovery did not complete',
                  present,
                  vaultPath,
                ),
              );
            }
            final identityStop = _identityStop(
              vaultPath,
              scanned,
              manifest,
              present,
            );
            if (identityStop != null) return identityStop;
            facts = scanned.facts;
            return AnkiSyncPlan(
              notes: scanned.notes,
              retirements: scanned.retirements,
              linkTargets: resolveLinkTargets(_aliases(facts)),
              relations: CardRelations.of(facts),
              reconcileCollection: true,
            );
          }

          if (!changedOnly || manifest == null || !manifest.quickReady) {
            return wholeVault();
          }
          final listed = await CurrentVaultContent.scan(vaultPath);
          if (!listed.isComplete) {
            return AnkiSyncStop(
              AnkiSyncResult.incomplete(
                errors: [
                  'The vault could not be listed; no cards were changed.',
                  ...listed.errors,
                ],
              ),
            );
          }
          final pathOf = <String, String>{};
          final changed = <String>{};
          for (final file in listed.files) {
            final key = AnkiProblemNoteScanner.relativeKey(
              vaultPath,
              file.path,
            );
            pathOf[key] = file.path;
            if (!manifest.unchanged(key, await file.stat())) changed.add(key);
          }
          final gone = manifest.notes.keys.where((k) => !pathOf.containsKey(k));
          if (gone.any((k) => manifest.notes[k]!.ankiNoteId != null)) {
            return wholeVault();
          }
          final stale = {
            for (final key in pathOf.keys)
              if (!changed.contains(key) &&
                  _cardDiffers(manifest.notes[key]!, present))
                key,
          };
          var scanned = await AnkiProblemNoteScanner.scanPaths(vaultPath, [
            for (final key in {...changed, ...stale}) pathOf[key]!,
          ]);
          if (!scanned.isComplete) {
            return AnkiSyncStop(
              _scanStop(
                scanned,
                'A changed note could not be read',
                present,
                vaultPath,
              ),
            );
          }

          final kept = {
            for (final key in pathOf.keys)
              if (!changed.contains(key) && !stale.contains(key))
                key: manifest.notes[key]!,
          };
          final before = resolveLinkTargets(manifest.aliases);
          var after = resolveLinkTargets(_aliases({...kept, ...scanned.facts}));
          // A card also shows which notes it is raised against. When that
          // changed, its own file did not, so it is read again like a
          // relinked note.
          final shownBefore = CardRelations.from(manifest.notes, before);
          final shownAfter = CardRelations.from({
            ...kept,
            ...scanned.facts,
          }, after);
          final relinked = [
            for (final entry in kept.entries)
              if (entry.value.links.any(
                    (link) => before[link] != after[link],
                  ) ||
                  shownBefore.signature(entry.key) !=
                      shownAfter.signature(entry.key))
                entry.key,
          ];
          if (relinked.isNotEmpty) {
            scanned = _merge(
              scanned,
              await AnkiProblemNoteScanner.scanPaths(vaultPath, [
                for (final key in relinked) pathOf[key]!,
              ]),
            );
            if (!scanned.isComplete) {
              return AnkiSyncStop(
                _scanStop(
                  scanned,
                  'A linking note could not be read',
                  present,
                  vaultPath,
                ),
              );
            }
            relinked.forEach(kept.remove);
            after = resolveLinkTargets(_aliases({...kept, ...scanned.facts}));
          }

          final identityStop = _identityStop(
            vaultPath,
            scanned,
            manifest,
            present,
            base: kept,
          );
          if (identityStop != null) return identityStop;
          facts = scanned.facts;
          base = kept;
          summary =
              '${changed.length} changed, ${stale.length} changed in Anki, '
              '${relinked.length} relinked, of ${pathOf.length}';
          return AnkiSyncPlan(
            notes: scanned.notes,
            retirements: scanned.retirements,
            linkTargets: after,
            relations: CardRelations.from({...kept, ...scanned.facts}, after),
          );
        },
        preview: preview,
        record: (result) async {
          await _record(
            vaultPath,
            result,
            facts,
            startedAt: startedAt,
            base: base,
          );
          debugPrint(
            'Interest sync: $summary; total ${clock.elapsedMilliseconds}ms',
          );
        },
      );
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki sync could not start: $error'],
      );
    }
  }

  static AnkiSyncStop? _identityStop(
    String vaultPath,
    AnkiProblemNoteScanResult scanned,
    SyncManifest? manifest,
    Map<int, AnkiNoteState> present, {
    Map<String, NoteFacts> base = const {},
  }) {
    final issues = [
      ..._lostIdentities(vaultPath, scanned, manifest),
      ..._sharedCards({...base, ...scanned.facts}),
    ];
    return issues.isEmpty
        ? null
        : AnkiSyncStop(
          AnkiSyncResult.stopped(_describe(issues, present, vaultPath)),
        );
  }

  /// Whether an untouched note's card is gone from Anki, or no longer holds
  /// what Interest last wrote there.
  static bool _cardDiffers(NoteFacts facts, Map<int, AnkiNoteState> present) {
    final id = int.tryParse(facts.ankiNoteId ?? '');
    if (id == null) return false;
    final state = present[id];
    return state == null || state.fingerprint != facts.card;
  }

  /// Records what Anki now holds.
  ///
  /// After a clean run, the manifest becomes [base] plus [facts], each note
  /// with the fingerprint of the card Anki received. Missing cards retain
  /// their IDs and lack a fingerprint, so quick sync checks them again. Anything unclean keeps
  /// the old manifest, so nothing is skipped.
  ///
  /// Either way, the `anki_note_id`s the run wrote are recorded as the notes
  /// now hold them, so the lost-identity guard protects a card from the
  /// moment its number is in the note. After an unclean run that is done only
  /// for notes the old manifest already lists: adding a new note there would
  /// make the next run think its name was already accounted for in other
  /// notes' links.
  static Future<void> _record(
    String vaultPath,
    AnkiSyncResult result,
    Map<String, NoteFacts> facts, {
    required int startedAt,
    Map<String, NoteFacts> base = const {},
    bool identityOnly = false,
  }) async {
    final received = {
      for (final entry in result.received.entries)
        AnkiProblemNoteScanner.relativeKey(vaultPath, entry.key): entry.value,
    };
    final Map<String, NoteFacts> notes;
    final int since;
    var quickReady = true;
    if (result.isSuccessful && !identityOnly) {
      notes = Map.of(base);
      facts.forEach((key, value) {
        notes[key] = value.copyWith(card: () => received[key]);
      });
      since = startedAt;
    } else {
      if (result.linked.isEmpty) return;
      final previous = await SyncManifest.load(vaultPath);
      if (previous == null) return;
      notes = Map.of(previous.notes);
      since = previous.startedAt;
      quickReady = previous.quickReady;
    }
    await _applyWrites(
      vaultPath,
      notes,
      result.linked,
      received: result.isSuccessful && !identityOnly ? received : const {},
    );
    await SyncManifest(
      notes,
      startedAt: since,
      quickReady: quickReady,
    ).save(vaultPath);
  }

  /// Updates [notes] for each file whose `anki_note_id` was written: its new
  /// time and size (written after the run began, so it is read again next
  /// time) and its new id. Only notes already in [notes] are touched.
  static Future<void> _applyWrites(
    String vaultPath,
    Map<String, NoteFacts> notes,
    Map<String, int?> linked, {
    Map<String, String> received = const {},
  }) async {
    for (final entry in linked.entries) {
      final key = AnkiProblemNoteScanner.relativeKey(vaultPath, entry.key);
      final prior = notes[key];
      if (prior == null) continue;
      try {
        final stat = await File(entry.key).stat();
        notes[key] = prior.copyWith(
          modified: stat.modified.millisecondsSinceEpoch,
          size: stat.size,
          ankiNoteId: () => entry.value?.toString(),
          card: () => received[key],
        );
      } on FileSystemException {
        notes.remove(key); // gone again: the next sync treats it as new
      }
    }
  }

  /// A note that had a card when Anki last received it, and now has no
  /// `anki_note_id`, would get a fresh card while its old card (and review
  /// history) is cut loose. A key lost in an edit (a property removed, a
  /// bulk rewrite that dropped frontmatter) must be put back, not acted on,
  /// so the run stops and says which id to restore.
  static List<AnkiSyncIssue> _lostIdentities(
    String vaultPath,
    AnkiProblemNoteScanResult scanned,
    SyncManifest? manifest,
  ) {
    if (manifest == null) return const [];
    final lost = <AnkiSyncIssue>[];
    for (final note in scanned.notes) {
      if (note.ankiNoteId?.isNotEmpty == true) continue;
      final key = AnkiProblemNoteScanner.relativeKey(
        vaultPath,
        note.sourcePath,
      );
      final id = manifest.notes[key]?.ankiNoteId;
      if (id == null) continue;
      final name = _withoutMd(key);
      lost.add(
        AnkiSyncIssue(
          kind: AnkiIssueKind.lostIdentity,
          message:
              '"$name" lost its anki_note_id. Syncing now would give it a new '
              'card and cut its old card loose with its review history. Add '
              '"anki_note_id: $id" back to its properties, then sync again. '
              'No cards were changed.',
          notes: [name],
          cardId: int.tryParse(id),
        ),
      );
    }
    return lost;
  }

  /// One issue per `anki_note_id` that more than one note carries.
  static List<AnkiSyncIssue> _sharedCards(Map<String, NoteFacts> facts) {
    final byId = <String, List<String>>{};
    facts.forEach((key, value) {
      final id = value.ankiNoteId;
      if (id != null) byId.putIfAbsent(id, () => []).add(_withoutMd(key));
    });
    return [
      for (final entry in byId.entries)
        if (entry.value.length > 1) _sharedCard(entry.key, entry.value..sort()),
    ];
  }

  static AnkiSyncIssue _sharedCard(String id, List<String> names) =>
      AnkiSyncIssue(
        kind: AnkiIssueKind.sharedCard,
        message:
            '${names.map((n) => '"$n"').join(' and ')} '
            '${names.length == 2 ? 'both' : 'all'} have anki_note_id '
            '$id. One card cannot belong to two notes, so no cards were '
            'changed. Keep the number on the note the card belongs to and '
            'delete it from the others, which then get their own cards.',
        notes: names,
        cardId: int.tryParse(id),
      );

  /// The stop for an incomplete scan: duplicate identities as issues, every
  /// other error as it was.
  static AnkiSyncResult _scanStop(
    AnkiProblemNoteScanResult scanned,
    String lead, [
    Map<int, AnkiNoteState>? present,
    String vaultPath = '',
  ]) {
    final shared = [
      for (final entry in scanned.conflicts.entries)
        _sharedCard(entry.key, entry.value),
    ];
    final other = scanned.errors.where(
      (error) =>
          !scanned.conflicts.keys.any(
            (id) => error.startsWith('Duplicate active anki_note_id "$id"'),
          ),
    );
    return AnkiSyncResult.incomplete(
      failed: scanned.conflictedRecords,
      skipped: scanned.operationCount - scanned.conflictedRecords,
      errors: [if (other.isNotEmpty) '$lead; no cards were changed.', ...other],
      issues: present == null ? shared : _describe(shared, present, vaultPath),
    );
  }

  static List<AnkiSyncIssue> _describe(
    List<AnkiSyncIssue> issues,
    Map<int, AnkiNoteState> present,
    String vaultPath,
  ) => [
    for (final issue in issues)
      switch (present[issue.cardId]) {
        final AnkiNoteState state => issue.withCard(
          source:
              issue.cardSource ??
              (vaultPath.isEmpty
                  ? null
                  : AnkiSyncService.sourceNoteOf(state.front, vaultPath)),
          problem: AnkiSyncService.plainTextOf(state.front),
          conjecture: AnkiSyncService.plainTextOf(state.back),
          reviews: state.reviews,
        ),
        null => issue,
      },
  ];

  static AnkiProblemNoteScanResult _merge(
    AnkiProblemNoteScanResult a,
    AnkiProblemNoteScanResult b,
  ) => AnkiProblemNoteScanResult(
    notes: [...a.notes, ...b.notes],
    retirements: [...a.retirements, ...b.retirements],
    errors: [...a.errors, ...b.errors],
    candidateCount: a.candidateCount + b.candidateCount,
    conflictedRecords: a.conflictedRecords + b.conflictedRecords,
    retirementCandidateCount:
        a.retirementCandidateCount + b.retirementCandidateCount,
    facts: {...a.facts, ...b.facts},
    conflicts: {...a.conflicts, ...b.conflicts},
  );

  static String _withoutMd(String key) => key.replaceAll(RegExp(r'\.md$'), '');

  static Map<String, List<String>> _aliases(Map<String, NoteFacts> facts) => {
    for (final entry in facts.entries) entry.key: entry.value.aliases,
  };

  /// Applies a confirmation of [AnkiSyncResult.missing] / [orphans] /
  /// a [AnkiIssueKind.foreignCard] move against a fresh whole-vault
  /// discovery, so nothing acts on a stale view.
  static Future<AnkiSyncResult?> resolve(
    AnkiTransport transport, {
    List<AnkiMissingCard> recreate = const [],
    List<AnkiOrphanCard> retire = const [],
    List<AnkiSyncIssue> reassign = const [],
  }) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final scanned = await AnkiProblemNoteScanner.scan(vaultPath);
      if (!scanned.isComplete) {
        return AnkiSyncResult.incomplete(
          errors: [
            'Problem Note discovery did not complete; no cards were changed.',
            ...scanned.errors,
          ],
        );
      }
      return await AnkiSyncService.resolve(
        transport,
        scanned.notes,
        vaultPath,
        retirements: scanned.retirements,
        recreate: recreate,
        retire: retire,
        reassign: reassign,
        linkTargets: resolveLinkTargets(_aliases(scanned.facts)),
        relations: CardRelations.of(scanned.facts),
        record: (result) {
          if (result.linked.isEmpty) return Future.value();
          return _record(
            vaultPath,
            result,
            const {},
            startedAt: 0,
            identityOnly: true,
          );
        },
      );
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki confirmation could not start: $error'],
      );
    }
  }

  static Future<String?> restoreIdentity(AnkiSyncIssue issue) =>
      _answerLostIdentity(issue, restore: true);

  static Future<String?> releaseIdentity(AnkiSyncIssue issue) =>
      _answerLostIdentity(issue, restore: false);

  /// Restore or release only the exact ID presented in the confirmation.
  static Future<String?> _answerLostIdentity(
    AnkiSyncIssue issue, {
    required bool restore,
  }) async {
    final id = issue.cardId;
    if (issue.kind != AnkiIssueKind.lostIdentity ||
        id == null ||
        issue.notes.length != 1) {
      return 'This is not a lost card number.';
    }
    AnkiSyncLock? lease;
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return 'No vault is chosen.';
      final path = p.normalize(p.join(vaultPath, '${issue.notes.single}.md'));
      if (!CurrentVaultContent.isEligible(vaultPath, path)) {
        return 'The note no longer exists.';
      }
      lease = await AnkiSyncLock.acquire(vaultPath);
      if (lease == null) return 'A sync is running; try again in a moment.';

      final manifest = await SyncManifest.load(vaultPath);
      final key = AnkiProblemNoteScanner.relativeKey(vaultPath, path);
      final prior = manifest?.notes[key];
      const stale = 'The note or its remembered card changed; sync again.';
      if (manifest == null || prior?.ankiNoteId != '$id') return stale;

      final scan = await AnkiProblemNoteScanner.scanPaths(vaultPath, [path]);
      if (!scan.isComplete || scan.notes.length != 1) return stale;
      final note = scan.notes.single;
      if (note.ankiNoteId?.isNotEmpty == true) return stale;
      if (restore) {
        final patch = await prepareFrontmatterField(
          path,
          'anki_note_id',
          '$id',
        );
        if (patch.before != note.sourceContent) return stale;
        final applied = await patch.apply();
        return applied.applied ? null : (applied.error ?? stale);
      }

      if (await readPreservingUtf8(File(path)) != note.sourceContent) {
        return stale;
      }
      final notes = Map.of(manifest.notes);
      notes[key] = prior!.copyWith(ankiNoteId: () => null, card: () => null);
      await SyncManifest(
        notes,
        startedAt: manifest.startedAt,
        quickReady: manifest.quickReady,
      ).save(vaultPath);
      final verified = (await SyncManifest.load(vaultPath))?.notes[key];
      return verified != null && verified.ankiNoteId == null
          ? null
          : 'The card decision could not be saved.';
    } catch (error) {
      return '$error';
    } finally {
      await lease?.release();
    }
  }
}
