import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import 'anki_problem_note_scanner.dart';
import 'anki_sync_service.dart';
import 'anki_transport.dart';

class AnkiSyncController {
  /// Returns null when no vault is configured.
  /// Otherwise returns the AnkiSyncResult from AnkiSyncService.syncVault.
  static Future<AnkiSyncResult?> sync(AnkiTransport transport) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final config = await IntegrationsConfigService.load(vaultPath);
      final scanned = await AnkiProblemNoteScanner.scan(
        vaultPath,
        excludedFolders: config.excludedFolders,
      );
      if (!scanned.isComplete) {
        return AnkiSyncResult.incomplete(
          failed: scanned.conflictedRecords,
          skipped: scanned.candidateCount - scanned.conflictedRecords,
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
      );
    } catch (error) {
      return AnkiSyncResult.incomplete(
        errors: ['Anki sync could not start: $error'],
      );
    }
  }
}
