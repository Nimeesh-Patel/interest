import 'package:path/path.dart' as p;

/// Interest's only footprint in a vault: a hidden, device-local `.interest/`
/// folder. Obsidian Sync does not carry dot-folders, which is what the sync
/// lock needs: it guards one physical copy of the vault, never another device.
class VaultPaths {
  VaultPaths._();

  static String interestDir(String vaultPath) => p.join(vaultPath, '.interest');

  static String syncLock(String vaultPath) =>
      p.join(interestDir(vaultPath), 'anki-sync.lock');

  /// Wikilink targets as the last whole-vault sync resolved them, so a
  /// one-note sync need not read every note again for aliases.
  static String linkTargets(String vaultPath) =>
      p.join(interestDir(vaultPath), 'link-targets.json');
}
