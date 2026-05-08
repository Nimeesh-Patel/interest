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
    final tdir = Directory(templatesPath(vaultPath));
    if (!await edir.exists()) await edir.create(recursive: true);
    if (!await bdir.exists()) await bdir.create(recursive: true);
    if (!await tdir.exists()) await tdir.create(recursive: true);
    await _seedDefaultTemplates(tdir.path);
  }

  static String entitiesPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Entities');

  static String boardsPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Boards');

  static String templatesPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Templates');

  static Future<void> _seedDefaultTemplates(String templatesDirPath) async {
    try {
      final templates = {
        'default.md': _tmpl('General'),
        'person.md': _tmpl('People'),
        'product.md': _tmpl('Products'),
        'idea.md': _tmpl('Ideas'),
      };
      for (final entry in templates.entries) {
        final file = File(p.join(templatesDirPath, entry.key));
        if (!await file.exists()) {
          await file.writeAsString(entry.value);
        }
      }
    } catch (_) {}
  }

  static String _tmpl(String category) => '''---
category: $category
template: true
---
# {{title}}

## Why Interesting

## Related

## Sources
''';
}
