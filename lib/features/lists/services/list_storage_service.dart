import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/list_model.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../core/vault_service.dart';

class ListStorageService {
  static Future<List<ListModel>> loadLists(String vaultPath) async {
    try {
      final dir = Directory(VaultService.listsPath(vaultPath));
      if (!await dir.exists()) return [];
      final results = <ListModel>[];
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        try {
          final content = await entry.readAsString();
          final name = extractH1(content) ?? p.basenameWithoutExtension(entry.path);
          final id = slugify(name);
          if (id.isEmpty) continue;
          final items = _parseItems(content);
          results.add(ListModel(id: id, name: name, items: items));
        } catch (_) {}
      }
      results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return results;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveList(String vaultPath, ListModel list) async {
    try {
      final dir = Directory(VaultService.listsPath(vaultPath));
      await dir.create(recursive: true);
      final content = _buildContent(list);
      final file = File(p.join(dir.path, '${sanitizeFilename(list.name)}.md'));
      await file.writeAsString(content);
    } catch (_) {}
  }

  static Future<ListModel?> createList(String vaultPath, String name) async {
    try {
      final dir = Directory(VaultService.listsPath(vaultPath));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${sanitizeFilename(name)}.md'));
      if (await file.exists()) return null;
      final id = slugify(name);
      if (id.isEmpty) return null;
      await file.writeAsString('# $name\n');
      return ListModel(id: id, name: name, items: []);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteList(String vaultPath, ListModel list) async {
    try {
      final dir = VaultService.listsPath(vaultPath);
      final file = File(p.join(dir, '${sanitizeFilename(list.name)}.md'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<ListModel?> renameList(
      String vaultPath, ListModel list, String newName) async {
    try {
      final dir = VaultService.listsPath(vaultPath);
      final oldFile = File(p.join(dir, '${sanitizeFilename(list.name)}.md'));
      final newFile = File(p.join(dir, '${sanitizeFilename(newName)}.md'));
      if (await newFile.exists()) return null;
      final newId = slugify(newName);
      if (newId.isEmpty) return null;
      final updated = ListModel(id: newId, name: newName, items: List.from(list.items));
      await newFile.writeAsString(_buildContent(updated));
      if (await oldFile.exists()) await oldFile.delete();
      return updated;
    } catch (_) {
      return null;
    }
  }

  static Future<void> addItem(String vaultPath, ListModel list, String text) async {
    try {
      list.items.add(text);
      await saveList(vaultPath, list);
    } catch (_) {}
  }

  static Future<void> removeItem(String vaultPath, ListModel list, int index) async {
    try {
      if (index < 0 || index >= list.items.length) return;
      list.items.removeAt(index);
      await saveList(vaultPath, list);
    } catch (_) {}
  }

  static Future<void> reorderItems(
      String vaultPath, ListModel list, int oldIndex, int newIndex) async {
    try {
      if (oldIndex < 0 || oldIndex >= list.items.length) return;
      final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final item = list.items.removeAt(oldIndex);
      list.items.insert(adjusted, item);
      await saveList(vaultPath, list);
    } catch (_) {}
  }

  static Future<void> updateItem(
      String vaultPath, ListModel list, int index, String newText) async {
    try {
      if (index < 0 || index >= list.items.length) return;
      list.items[index] = newText;
      await saveList(vaultPath, list);
    } catch (_) {}
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static List<String> _parseItems(String content) {
    final items = <String>[];
    for (final line in content.split('\n')) {
      if (line.startsWith('- ')) {
        items.add(line.substring(2));
      }
    }
    return items;
  }

  static String _buildContent(ListModel list) {
    final buf = StringBuffer();
    buf.writeln('# ${list.name}');
    if (list.items.isNotEmpty) {
      buf.writeln();
      for (final item in list.items) {
        buf.writeln('- $item');
      }
    }
    return buf.toString();
  }
}
