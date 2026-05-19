import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/task.dart';
import 'vault_service.dart';

class TaskStorageService {
  static final _taskRegex = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.+)$');

  static Future<List<TaskFile>> loadTaskFiles() async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null) return [];
      final dir = Directory(VaultService.tasksPath(vault));
      if (!await dir.exists()) return [];
      final results = <TaskFile>[];
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.md')) continue;
        try {
          final content = await entity.readAsString();
          results.add(_parseTaskFile(entity.path, content));
        } catch (_) {}
      }
      results.sort((a, b) => a.name.compareTo(b.name));
      return results;
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> loadLines(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];
      return await file.readAsLines();
    } catch (_) {
      return [];
    }
  }

  static Future<void> toggleTask(String filePath, int lineIndex) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      final line = lines[lineIndex];
      final m = _taskRegex.firstMatch(line);
      if (m == null) return;
      final isDone = m.group(1)!.toLowerCase() == 'x';
      if (isDone) {
        lines[lineIndex] = line.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
      } else {
        lines[lineIndex] = line.replaceFirst('[ ]', '[x]');
      }
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  static Future<void> addTask(String filePath, String text) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final newLine = '- [ ] $text';
      final updated =
          content.endsWith('\n') ? '$content$newLine\n' : '$content\n$newLine\n';
      await file.writeAsString(updated);
    } catch (_) {}
  }

  static Future<void> deleteTask(String filePath, int lineIndex) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      lines.removeAt(lineIndex);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  static Future<void> updateTaskText(
      String filePath, int lineIndex, String newText) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      final m = _taskRegex.firstMatch(lines[lineIndex]);
      if (m == null) return;
      final checkState = m.group(1)!;
      final dashIdx = lines[lineIndex].indexOf('-');
      final indent = dashIdx > 0 ? lines[lineIndex].substring(0, dashIdx) : '';
      lines[lineIndex] = '$indent- [$checkState] $newText';
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  static Future<TaskFile?> createTaskFile(String name) async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null) return null;
      final dir = Directory(VaultService.tasksPath(vault));
      await dir.create(recursive: true);
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File(p.join(dir.path, '$safeName.md'));
      if (await file.exists()) return null;
      await file.writeAsString('# $name\n\n');
      return TaskFile(
        filePath: file.path,
        name: name,
        totalTasks: 0,
        completedTasks: 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteTaskFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static TaskFile _parseTaskFile(String filePath, String content) {
    final lines = content.split('\n');
    String name = p.basenameWithoutExtension(filePath);
    bool nameFound = false;
    int total = 0, completed = 0;
    for (final line in lines) {
      if (!nameFound && line.startsWith('# ') && !line.startsWith('## ')) {
        name = line.substring(2).trim();
        nameFound = true;
        continue;
      }
      final m = _taskRegex.firstMatch(line);
      if (m != null) {
        total++;
        if (m.group(1)!.toLowerCase() == 'x') completed++;
      }
    }
    return TaskFile(
      filePath: filePath,
      name: name,
      totalTasks: total,
      completedTasks: completed,
    );
  }
}
