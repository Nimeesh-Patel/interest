import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/task.dart';
import '../models/task_block.dart';
import '../../../core/vault_service.dart';

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

  // ── Hierarchical block parser ──────────────────────────────────────────────

  // Parse a flat list of file lines into a tree of TaskNodes.
  // Pure function — no I/O. Call after loadLines().
  static List<TaskNode> parseNodes(List<String> lines) {
    final nodes = <TaskNode>[];
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Skip H1 (file title — shown in AppBar)
      if (line.startsWith('# ') && !line.startsWith('## ')) {
        i++;
        continue;
      }

      if (line.startsWith('### ')) {
        nodes.add(TaskHeaderNode(lineIndex: i, headingLevel: 3, text: line.substring(4).trim()));
        i++;
        continue;
      }

      if (line.startsWith('## ')) {
        nodes.add(TaskHeaderNode(lineIndex: i, headingLevel: 2, text: line.substring(3).trim()));
        i++;
        continue;
      }

      final m = _taskRegex.firstMatch(line);
      if (m != null) {
        final indentSpaces = line.indexOf('-');
        final block = TaskBlock(
          text: m.group(2)!,
          completed: m.group(1)!.toLowerCase() == 'x',
          indentSpaces: indentSpaces < 0 ? 0 : indentSpaces,
          startLine: i,
          noteLineIndices: [],
          children: [],
        );
        i = _collectBlockContent(lines, i + 1, block);
        nodes.add(block);
        continue;
      }

      nodes.add(TaskProseNode(lineIndex: i, raw: line));
      i++;
    }
    return nodes;
  }

  // Collect notes and children for [parent], starting at line [start].
  // Returns the next unconsumed line index.
  static int _collectBlockContent(List<String> lines, int start, TaskBlock parent) {
    int i = start;
    while (i < lines.length) {
      final line = lines[i];

      // Headers always terminate the block
      if (line.startsWith('#')) break;

      final trimmed = line.trimLeft();

      if (trimmed.isEmpty) {
        // Blank line: look ahead to decide if it belongs to this block
        final next = _nextNonBlankLine(lines, i + 1);
        if (next == null || next.startsWith('#')) break;
        final nextIndent = next.length - next.trimLeft().length;
        if (nextIndent <= parent.indentSpaces) break;
        parent.noteLineIndices.add(i);
        i++;
        continue;
      }

      final indent = line.length - trimmed.length;
      if (indent <= parent.indentSpaces) break;

      final m = _taskRegex.firstMatch(line);
      if (m != null) {
        final child = TaskBlock(
          text: m.group(2)!,
          completed: m.group(1)!.toLowerCase() == 'x',
          indentSpaces: indent,
          startLine: i,
          noteLineIndices: [],
          children: [],
        );
        i = _collectBlockContent(lines, i + 1, child);
        parent.children.add(child);
      } else {
        parent.noteLineIndices.add(i);
        i++;
      }
    }
    return i;
  }

  static String? _nextNonBlankLine(List<String> lines, int from) {
    for (int i = from; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) return lines[i];
    }
    return null;
  }

  // ── Block-level mutations ──────────────────────────────────────────────────

  // Insert a note immediately after the task's own line (before children).
  // Multiline noteText is split on '\n'; each piece is indented at
  // parent.indentSpaces + 2 to satisfy _collectBlockContent's indent check.
  static Future<void> addNote(
      String filePath, TaskBlock parent, String noteText) async {
    try {
      final lines = await File(filePath).readAsLines();
      final indent = ' ' * (parent.indentSpaces + 2);
      final noteLines = noteText
          .split('\n')
          .map((l) => l.isEmpty ? '' : '$indent$l')
          .toList();
      lines.insertAll(parent.startLine + 1, noteLines);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Insert a subtask as the last child of [parent].
  static Future<void> addSubtask(
      String filePath, TaskBlock parent, String text) async {
    try {
      final lines = await File(filePath).readAsLines();
      final indent = ' ' * (parent.indentSpaces + 2);
      lines.insert(parent.endLine + 1, '$indent- [ ] $text');
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Insert a sibling task immediately after [block]'s full subtree (same indent level).
  static Future<void> addSiblingTask(
      String filePath, TaskBlock block, String text) async {
    try {
      final lines = await File(filePath).readAsLines();
      final indent = ' ' * block.indentSpaces;
      lines.insert(block.endLine + 1, '$indent- [ ] $text');
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Delete a block and its entire subtree (notes + children).
  static Future<void> deleteBlock(String filePath, TaskBlock block) async {
    try {
      final lines = await File(filePath).readAsLines();
      final end = block.endLine;
      if (block.startLine < 0 || end >= lines.length) return;
      lines.removeRange(block.startLine, end + 1);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Update the text of a task block (thin wrapper over updateTaskText).
  static Future<void> updateBlockText(
      String filePath, TaskBlock block, String newText) async {
    await updateTaskText(filePath, block.startLine, newText);
  }

  // Replace a single arbitrary line (used for inline note editing).
  static Future<void> updateLine(
      String filePath, int lineIndex, String newText) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      lines[lineIndex] = newText;
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Rename a task file: update the # heading and rename the file on disk.
  // Returns the new file path, or null on failure / name collision.
  static Future<String?> renameTaskFile(
      String filePath, String newName) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('# ') && !lines[i].startsWith('## ')) {
          lines[i] = '# $newName';
          break;
        }
      }
      await file.writeAsString(lines.join('\n'));
      final dir = p.dirname(filePath);
      final safeName = newName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final newPath = p.join(dir, '$safeName.md');
      if (newPath == filePath) return filePath;
      if (await File(newPath).exists()) return null;
      final renamed = await file.rename(newPath);
      return renamed.path;
    } catch (_) {
      return null;
    }
  }
}
