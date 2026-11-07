import 'package:path/path.dart' as p;

/// Interest's only footprint in a vault: a hidden, device-local `.interest/`
/// folder. Obsidian Sync does not carry dot-folders, which is what the sync
/// lock needs: it guards one physical copy of the vault, never another device.
class VaultPaths {
  VaultPaths._();

  static String interestDir(String vaultPath) => p.join(vaultPath, '.interest');

  static String syncLock(String vaultPath) =>
      p.join(interestDir(vaultPath), 'anki-sync.lock');

  /// The vault as Anki last received it (`SyncManifest`), so a sync after a
  /// few edits reads only the changed files.
  static String syncManifest(String vaultPath) =>
      p.join(interestDir(vaultPath), 'sync-manifest.json');
}
