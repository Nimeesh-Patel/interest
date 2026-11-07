import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/link_target_cache.dart';
import 'anki_problem_note_scanner.dart';
import 'anki_sync_service.dart';
import 'anki_transport.dart';

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
      final clock = Stopwatch()..start();
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
      final result = await AnkiSyncService.syncVault(
        transport,
        scanned.notes,
        vaultPath,
        retirements: scanned.retirements,
        reconcileCollection: true,
        preview: preview,
      );
      debugPrint(
        'Interest vault ${preview ? 'preview' : 'sync'}: read ${read}ms, '
        'rest ${clock.elapsedMilliseconds - read}ms, '
        'total ${clock.elapsedMilliseconds}ms',
      );
      return result;
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki sync could not start: $error'],
      );
    }
  }

  /// The edit cycle's sync: Nimeesh changed one note in Obsidian and wants
  /// its card current before returning to review. Reads only that note and
  /// the few link targets it uses, against one complete collection snapshot.
  /// It never classifies unreferenced cards (only a whole-vault discovery
  /// can), and its missing-card and source-change guards are the whole-vault
  /// sync's own. [notePath] is vault-relative, as Obsidian names it.
  static Future<AnkiSyncResult?> syncNote(
    AnkiTransport transport,
    String notePath,
  ) async {
    final clock = Stopwatch()..start();
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final path = p.normalize(p.join(vaultPath, notePath));
      final scanned = await AnkiProblemNoteScanner.scanPaths(vaultPath, [path]);
      final read = clock.elapsedMilliseconds;
      if (!scanned.isComplete) {
        return AnkiSyncResult.incomplete(
          errors: [
            'The note could not be read; no cards were changed.',
            ...scanned.errors,
          ],
        );
      }
      if (scanned.notes.isEmpty && scanned.retirements.isEmpty) {
        return AnkiSyncResult.incomplete(
          errors: [
            '"$notePath" has no *** separator, so it is not a Problem Note '
                'and has no card.',
          ],
        );
      }
      final linkTargets = await LinkTargetCache.forTexts(vaultPath, [
        for (final note in scanned.notes) ...[note.front ?? '', note.back ?? ''],
      ]);
      final links = clock.elapsedMilliseconds;
      final result = await AnkiSyncService.syncVault(
        transport,
        scanned.notes,
        vaultPath,
        retirements: scanned.retirements,
        linkTargets: linkTargets,
      );
      debugPrint(
        'Interest note sync: read ${read}ms, links ${links - read}ms, '
        'anki ${clock.elapsedMilliseconds - links}ms, '
        'total ${clock.elapsedMilliseconds}ms',
      );
      return result;
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki sync could not start: $error'],
      );
    }
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
