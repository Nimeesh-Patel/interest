import 'package:flutter/foundation.dart';

import '../../../core/vault_service.dart';
import '../../../shared/markdown/current_vault_content.dart';
import '../../../shared/markdown/link_targets.dart';
import 'anki_problem_note_scanner.dart';
import 'anki_sync_service.dart';
import 'anki_transport.dart';
import 'sync_manifest.dart';

class AnkiSyncController {
  /// Whole-vault sync, or with [preview] the same outcome computed without
  /// writing. Returns null when no vault is configured.
  static Future<AnkiSyncResult?> sync(
    AnkiTransport transport, {
    bool preview = false,
  }) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      return await _syncVault(transport, vaultPath, preview: preview);
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki sync could not start: $error'],
      );
    }
  }

  static Future<AnkiSyncResult> _syncVault(
    AnkiTransport transport,
    String vaultPath, {
    bool preview = false,
  }) async {
    final clock = Stopwatch()..start();
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final scanned = await AnkiProblemNoteScanner.scan(vaultPath);
    final read = clock.elapsedMilliseconds;
    if (!scanned.isComplete) {
      return AnkiSyncResult.incomplete(
        failed: scanned.conflictedRecords,
        skipped: scanned.operationCount - scanned.conflictedRecords,
        errors: [
          'Problem Note discovery did not complete; no cards were changed.',
          ...scanned.errors,
        ],
      );
    }
    final lost = _lostIdentities(
      vaultPath,
      scanned,
      await SyncManifest.load(vaultPath),
    );
    if (lost.isNotEmpty) return AnkiSyncResult.incomplete(errors: lost);
    final result = await AnkiSyncService.syncVault(
      transport,
      scanned.notes,
      vaultPath,
      retirements: scanned.retirements,
      reconcileCollection: true,
      preview: preview,
      linkTargets: resolveLinkTargets(_aliases(scanned.facts)),
    );
    if (!preview) {
      await _record(vaultPath, result, scanned.facts, startedAt: startedAt);
    }
    debugPrint(
      'Interest vault ${preview ? 'preview' : 'sync'}: read ${read}ms, '
      'rest ${clock.elapsedMilliseconds - read}ms, '
      'total ${clock.elapsedMilliseconds}ms',
    );
    return result;
  }

  /// The sync the Obsidian button runs: everything that changed since Anki
  /// last received the vault, whoever changed it (Nimeesh on any device, or
  /// Perspirator in bulk through Obsidian Sync). Every current note is
  /// listed and compared with the [SyncManifest] by modification time and
  /// size; only differing files are read.
  ///
  /// It falls back to the whole-vault sync whenever the shortcut could be
  /// wrong: no manifest yet, a linked note deleted or renamed (only the whole
  /// vault can say what its card now is), or a changed alias (which can
  /// change other notes' links). Identities are checked vault-wide against
  /// the manifest. It never classifies unreferenced cards.
  static Future<AnkiSyncResult?> syncChanged(AnkiTransport transport) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final clock = Stopwatch()..start();
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final manifest = await SyncManifest.load(vaultPath);
      if (manifest == null) return await _syncVault(transport, vaultPath);

      final listed = await CurrentVaultContent.scan(vaultPath);
      if (!listed.isComplete) {
        return AnkiSyncResult.incomplete(
          errors: [
            'The vault could not be listed; no cards were changed.',
            ...listed.errors,
          ],
        );
      }
      final present = <String>{};
      final changed = <String>[];
      for (final file in listed.files) {
        final key = AnkiProblemNoteScanner.relativeKey(vaultPath, file.path);
        present.add(key);
        if (!manifest.unchanged(key, await file.stat())) {
          changed.add(file.path);
        }
      }
      final gone = manifest.notes.keys.where((k) => !present.contains(k));
      if (gone.any((k) => manifest.notes[k]!.ankiNoteId != null)) {
        return await _syncVault(transport, vaultPath);
      }
      final listedMs = clock.elapsedMilliseconds;

      final scanned = await AnkiProblemNoteScanner.scanPaths(
        vaultPath,
        changed,
      );
      if (!scanned.isComplete) {
        return AnkiSyncResult.incomplete(
          errors: [
            'A changed note could not be read; no cards were changed.',
            ...scanned.errors,
          ],
        );
      }
      final lost = _lostIdentities(vaultPath, scanned, manifest);
      if (lost.isNotEmpty) return AnkiSyncResult.incomplete(errors: lost);
      final aliasChanged = scanned.facts.entries.any((entry) {
        final before = manifest.notes[entry.key]?.aliases ?? const <String>[];
        return !listEquals(before, entry.value.aliases);
      });
      if (aliasChanged) return await _syncVault(transport, vaultPath);

      final unchanged = Map.of(manifest.notes)..removeWhere(
        (key, _) => !present.contains(key) || scanned.facts.containsKey(key),
      );
      final current = {...unchanged, ...scanned.facts};
      final duplicates = _duplicateIds(current);
      if (duplicates.isNotEmpty) {
        return AnkiSyncResult.incomplete(
          errors: [
            'Problem Note discovery did not complete; no cards were changed.',
            ...duplicates,
          ],
        );
      }
      final result = await AnkiSyncService.syncVault(
        transport,
        scanned.notes,
        vaultPath,
        retirements: scanned.retirements,
        linkTargets: resolveLinkTargets(_aliases(current)),
      );
      await _record(
        vaultPath,
        result,
        scanned.facts,
        startedAt: startedAt,
        base: unchanged,
      );
      debugPrint(
        'Interest changed sync: ${changed.length} of ${present.length} '
        'changed; list ${listedMs}ms, '
        'read+anki ${clock.elapsedMilliseconds - listedMs}ms, '
        'total ${clock.elapsedMilliseconds}ms',
      );
      return result;
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki sync could not start: $error'],
      );
    }
  }

  /// Records [facts] as received by Anki, over [base], after a clean run
  /// only. A note whose card is missing stays unrecorded so it is offered
  /// again; anything unclean leaves the old manifest, so nothing is skipped.
  static Future<void> _record(
    String vaultPath,
    AnkiSyncResult result,
    Map<String, NoteFacts> facts, {
    required int startedAt,
    Map<String, NoteFacts> base = const {},
  }) async {
    if (!result.completed || result.failed > 0 || result.errors.isNotEmpty) {
      return;
    }
    final missing = {
      for (final card in result.missing)
        AnkiProblemNoteScanner.relativeKey(vaultPath, card.sourcePath),
    };
    final notes = Map.of(base);
    facts.forEach((key, value) {
      if (!missing.contains(key)) notes[key] = value;
    });
    await SyncManifest(notes, startedAt: startedAt).save(vaultPath);
  }

  /// A note that had a card when Anki last received it, and now has no
  /// `anki_note_id`, would get a fresh card while its old card (and review
  /// history) is cut loose. A key lost in an edit (a property removed, a
  /// bulk rewrite that dropped frontmatter) must be put back, not acted on,
  /// so the run stops and says which id to restore.
  static List<String> _lostIdentities(
    String vaultPath,
    AnkiProblemNoteScanResult scanned,
    SyncManifest? manifest,
  ) {
    if (manifest == null) return const [];
    final lost = <String>[];
    for (final note in scanned.notes) {
      if (note.ankiNoteId?.isNotEmpty == true) continue;
      final key = AnkiProblemNoteScanner.relativeKey(vaultPath, note.sourcePath);
      final id = manifest.notes[key]?.ankiNoteId;
      if (id == null) continue;
      lost.add(
        '"${key.replaceAll(RegExp(r'\.md$'), '')}" lost its anki_note_id. '
        'Syncing now would give it a new card and cut its old card loose '
        'with its review history. Add "anki_note_id: $id" back to its '
        'properties, then sync again. No cards were changed.',
      );
    }
    return lost;
  }

  static Map<String, List<String>> _aliases(Map<String, NoteFacts> facts) => {
    for (final entry in facts.entries) entry.key: entry.value.aliases,
  };

  static List<String> _duplicateIds(Map<String, NoteFacts> facts) {
    final byId = <String, List<String>>{};
    facts.forEach((key, value) {
      final id = value.ankiNoteId;
      if (id != null) byId.putIfAbsent(id, () => []).add(key);
    });
    return [
      for (final entry in byId.entries)
        if (entry.value.length > 1)
          'Duplicate active anki_note_id "${entry.key}": '
              '${(entry.value..sort()).join(', ')}',
    ];
  }

  /// Applies a confirmation of [AnkiSyncResult.missing] / [orphans] against a
  /// fresh whole-vault discovery, so nothing acts on a stale view.
  static Future<AnkiSyncResult?> resolve(
    AnkiTransport transport, {
    List<AnkiMissingCard> recreate = const [],
    List<AnkiOrphanCard> retire = const [],
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
      );
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki confirmation could not start: $error'],
      );
    }
  }
}
