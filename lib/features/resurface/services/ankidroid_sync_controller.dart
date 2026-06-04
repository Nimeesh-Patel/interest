import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import 'ankidroid_service.dart';
import 'resurface_service.dart';

class AnkiDroidSyncController {
  /// Returns null when no vault is configured.
  /// Otherwise returns the AnkiSyncResult from AnkiDroidService.syncVault.
  static Future<AnkiSyncResult?> sync() async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return null;
      final config = await IntegrationsConfigService.load(vaultPath);
      final allNotes = await ResurfaceService.getAllNotes(
        vaultPath,
        excludedFolders: config.resurfaceExcludedFolders,
      );
      final problemNotes = allNotes.where((n) => n.isProblemNote).toList();
      return await AnkiDroidService.syncVault(problemNotes);
    } catch (_) {
      return null;
    }
  }
}
