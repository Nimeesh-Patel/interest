abstract class TaskNode {}

class TaskHeaderNode extends TaskNode {
  final int lineIndex;
  final int headingLevel; // 2 = ##, 3 = ###
  final String text;

  TaskHeaderNode({
    required this.lineIndex,
    required this.headingLevel,
    required this.text,
  });
}

class TaskProseNode extends TaskNode {
  final int lineIndex;
  final String raw;

  TaskProseNode({required this.lineIndex, required this.raw});
}

class TaskBlock extends TaskNode {
  String text;
  bool completed;
  final int indentSpaces; // raw count of leading spaces before '-'
  final int startLine;    // 0-based line index in file
  final List<int> noteLineIndices; // line indices of attached prose/blank lines
  final List<TaskBlock> children;  // nested subtask blocks

  TaskBlock({
    required this.text,
    required this.completed,
    required this.indentSpaces,
    required this.startLine,
    required this.noteLineIndices,
    required this.children,
  });

  int get indentLevel => indentSpaces ~/ 2;

  // Last line belonging to this block's full subtree (inclusive).
  int get endLine {
    int end = startLine;
    for (final idx in noteLineIndices) {
      if (idx > end) end = idx;
    }
    for (final child in children) {
      if (child.endLine > end) end = child.endLine;
    }
    return end;
  }
}
