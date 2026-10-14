import '../../../shared/markdown/markdown_file.dart';

import '../../../shared/markdown/md_utils.dart';
import '../models/task_block.dart';

class TaskStorageService {
  static final _taskRegex = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.+)$');

  // ── Exact-snapshot mutations (Inbox) ─────────────────────────────────────

  static Future<GuardedTaskMutationResult> guardedAddTask(
    String filePath,
    TaskFileSnapshot expected,
    String text, {
    GuardedTaskFileOperations operations = const GuardedTaskFileOperations(),
  }) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    lines.add('- [ ] $text');
    return true;
  }, operations: operations);

  static Future<GuardedTaskMutationResult> guardedToggleBlock(
    String path,
    TaskFileSnapshot expected,
    TaskBlock block, {
    bool reorderRoot = false,
  }) => MarkdownFile.guardedEditLines(path, expected, (lines) {
    if (block.startLine < 0 || block.endLine >= lines.length) return false;
    final original = lines[block.startLine];
    if (_taskRegex.firstMatch(original) == null) return false;
    lines[block.startLine] =
        block.completed
            ? original.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]')
            : original.replaceFirst('[ ]', '[x]');
    if (!reorderRoot || block.indentSpaces > 0) return true;
    final content = lines.sublist(block.startLine, block.endLine + 1);
    lines.removeRange(block.startLine, block.endLine + 1);
    var insert = lines.length;
    if (block.completed) {
      final complete = lines.indexWhere(
        (line) =>
            _taskRegex.hasMatch(line) &&
            line.indexOf('-') == 0 &&
            RegExp(r'^\s*-\s+\[[xX]\]').hasMatch(line),
      );
      if (complete >= 0) insert = complete;
    }
    lines.insertAll(insert, content);
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedUpdateBlockText(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock block,
    String newText,
  ) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    return _updateTaskTextInLines(lines, block.startLine, newText);
  });

  static Future<GuardedTaskMutationResult> guardedDeleteBlock(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock block,
  ) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    if (block.startLine < 0 || block.endLine >= lines.length) return false;
    lines.removeRange(block.startLine, block.endLine + 1);
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedAddNote(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock parent,
    String noteText,
  ) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    if (parent.startLine < 0 || parent.startLine >= lines.length) return false;
    final indent = ' ' * (parent.indentSpaces + 2);
    final noteLines =
        noteText
            .split('\n')
            .map((line) => line.isEmpty ? '' : '$indent$line')
            .toList();
    lines.insertAll(parent.startLine + 1, noteLines);
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedAddSubtask(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock parent,
    String text,
  ) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    if (parent.endLine < 0 || parent.endLine >= lines.length) return false;
    final indent = ' ' * (parent.indentSpaces + 2);
    lines.insert(parent.endLine + 1, '$indent- [ ] $text');
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedUpdateLine(
    String filePath,
    TaskFileSnapshot expected,
    int lineIndex,
    String newText,
  ) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    lines[lineIndex] = newText;
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedDeleteLine(
    String filePath,
    TaskFileSnapshot expected,
    int lineIndex,
  ) => MarkdownFile.guardedEditLines(filePath, expected, (lines) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    lines.removeAt(lineIndex);
    return true;
  });

  static bool _updateTaskTextInLines(
    List<String> lines,
    int lineIndex,
    String newText,
  ) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    final match = _taskRegex.firstMatch(lines[lineIndex]);
    if (match == null) return false;
    final checkState = match.group(1)!;
    final dashIndex = lines[lineIndex].indexOf('-');
    final indent =
        dashIndex > 0 ? lines[lineIndex].substring(0, dashIndex) : '';
    lines[lineIndex] = '$indent- [$checkState] $newText';
    return true;
  }

  // ── Hierarchical block parser ──────────────────────────────────────────────

  // Parse a flat list of file lines into a tree of TaskNodes.
  // Pure function — no I/O. Uses the exact loaded snapshot lines.
  static List<TaskNode> parseNodes(List<String> lines) {
    final nodes = <TaskNode>[];
    final editableLines = unfencedBodyLines(lines).toSet();
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (!editableLines.contains(i)) {
        nodes.add(TaskProseNode(lineIndex: i, raw: line));
        i++;
        continue;
      }

      // Skip H1 (file title — shown in AppBar)
      if (line.startsWith('# ') && !line.startsWith('## ')) {
        i++;
        continue;
      }

      if (line.startsWith('### ')) {
        nodes.add(
          TaskHeaderNode(
            lineIndex: i,
            headingLevel: 3,
            text: line.substring(4).trim(),
          ),
        );
        i++;
        continue;
      }

      if (line.startsWith('## ')) {
        nodes.add(
          TaskHeaderNode(
            lineIndex: i,
            headingLevel: 2,
            text: line.substring(3).trim(),
          ),
        );
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
        i = _collectBlockContent(lines, i + 1, block, editableLines);
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
  static int _collectBlockContent(
    List<String> lines,
    int start,
    TaskBlock parent,
    Set<int> editableLines,
  ) {
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

      final m = editableLines.contains(i) ? _taskRegex.firstMatch(line) : null;
      if (m != null) {
        final child = TaskBlock(
          text: m.group(2)!,
          completed: m.group(1)!.toLowerCase() == 'x',
          indentSpaces: indent,
          startLine: i,
          noteLineIndices: [],
          children: [],
        );
        i = _collectBlockContent(lines, i + 1, child, editableLines);
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
  static Future<GuardedTaskMutationResult> guardedReorderRootBlocks(
    String path,
    TaskFileSnapshot expected,
    List<TaskNode> nodes,
    int oldIndex,
    int newIndex,
  ) => MarkdownFile.guardedEditLines(path, expected, (lines) {
    if (oldIndex == newIndex) return true;
    if (oldIndex < 0 || oldIndex >= nodes.length || newIndex < 0) return false;
    final moved = nodes[oldIndex];
    if (moved is! TaskBlock ||
        moved.indentSpaces != 0 ||
        moved.startLine < 0 ||
        moved.endLine >= lines.length) {
      return false;
    }
    final count = moved.endLine - moved.startLine + 1;
    final content = lines.sublist(moved.startLine, moved.endLine + 1);
    lines.removeRange(moved.startLine, moved.endLine + 1);
    final remaining = List<TaskNode>.from(nodes)..removeAt(oldIndex);
    var insert = lines.length;
    if (newIndex < remaining.length) {
      final reference = remaining[newIndex];
      if (reference is TaskBlock) {
        insert = reference.startLine;
      } else if (reference is TaskHeaderNode) {
        insert = reference.lineIndex;
      } else if (reference is TaskProseNode) {
        insert = reference.lineIndex;
      } else {
        return false;
      }
      if (insert > moved.startLine) insert -= count;
    }
    lines.insertAll(insert.clamp(0, lines.length), content);
    return true;
  });
}
