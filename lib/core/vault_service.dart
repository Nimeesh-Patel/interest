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
    final tdir = Directory(templatesPath(vaultPath));
    if (!await tdir.exists()) await tdir.create(recursive: true);
    final sysdir = Directory(systemPath(vaultPath));
    if (!await sysdir.exists()) await sysdir.create(recursive: true);
    final prdir = Directory(projectsPath(vaultPath));
    if (!await prdir.exists()) await prdir.create(recursive: true);
  }

  static String templatesPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Templates');

  static String systemPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'System');

  static String projectsPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Projects');
}
