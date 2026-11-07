import 'package:shared_preferences/shared_preferences.dart';

/// The chosen vault folder. It must be known before the vault can be read, so
/// it lives in SharedPreferences rather than in the vault.
class VaultService {
  static const _key = 'vault_path';

  static Future<String?> getVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> setVaultPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }
}
