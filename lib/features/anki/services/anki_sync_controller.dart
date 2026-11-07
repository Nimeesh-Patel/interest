import '../../../core/vault_service.dart';
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
      final scanned = await AnkiProblemNoteScanner.scan(vaultPath);
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
      return await AnkiSyncService.syncVault(
        transport,
        scanned.notes,
        vaultPath,
        retirements: scanned.retirements,
        reconcileCollection: true,
        preview: preview,
      );
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
