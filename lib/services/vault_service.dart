import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<void> clearVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> ensureVaultDirectories(String vaultPath) async {
    final edir = Directory(entitiesPath(vaultPath));
    final bdir = Directory(boardsPath(vaultPath));
    if (!await edir.exists()) await edir.create(recursive: true);
    if (!await bdir.exists()) await bdir.create(recursive: true);
  }

  static String entitiesPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Entities');

  static String boardsPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Boards');
}
