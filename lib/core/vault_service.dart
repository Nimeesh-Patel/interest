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
    final tsdir = Directory(tasksPath(vaultPath));
    if (!await tsdir.exists()) await tsdir.create(recursive: true);
    final bkdir = Directory(booksPath(vaultPath));
    if (!await bkdir.exists()) await bkdir.create(recursive: true);
    final artdir = Directory(articlesPath(vaultPath));
    if (!await artdir.exists()) await artdir.create(recursive: true);
    await _migrateBoardsToLists(vaultPath);
    final ldir = Directory(listsPath(vaultPath));
    if (!await ldir.exists()) await ldir.create(recursive: true);
    final sysdir = Directory(systemPath(vaultPath));
    if (!await sysdir.exists()) await sysdir.create(recursive: true);
    final prdir = Directory(projectsPath(vaultPath));
    if (!await prdir.exists()) await prdir.create(recursive: true);
  }

  static Future<void> _migrateBoardsToLists(String vaultPath) async {
    try {
      final oldDir = Directory(p.join(vaultPath, 'Interesting', 'Boards'));
      final newDir = Directory(listsPath(vaultPath));
      if (await oldDir.exists() && !await newDir.exists()) {
        await oldDir.rename(newDir.path);
      }
    } catch (_) {}
  }

  static String listsPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Lists');

  static String templatesPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Templates');

  static String tasksPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Tasks');

  static String booksPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Books');

  static String articlesPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Articles');

  static String systemPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'System');

  static String projectsPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Projects');

  static String bookmarksPath(String vaultPath) => vaultPath;
}
