import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import 'anki_sync_service.dart';
import 'anki_transport.dart';
import 'resurface_service.dart';

class AnkiSyncController {
  /// Returns null when no vault is configured.
  /// Otherwise returns the AnkiSyncResult from AnkiSyncService.syncVault.
  static Future<AnkiSyncResult?> sync(AnkiTransport transport) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final config = await IntegrationsConfigService.load(vaultPath);
      final allNotes = await ResurfaceService.getAllNotes(
        vaultPath,
        excludedFolders: config.resurfaceExcludedFolders,
      );
      final problemNotes = allNotes.where((n) => n.isProblemNote).toList();
      return await AnkiSyncService.syncVault(transport, problemNotes, vaultPath);
    } catch (_) {
      return null;
    }
  }
}
