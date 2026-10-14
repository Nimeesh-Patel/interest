import 'package:people_tracker/shared/markdown/markdown_file.dart';
import '../../tasks/services/task_storage_service.dart';
import '../../../shared/markdown/md_utils.dart';

/// Item lines are editable projections; all other Markdown remains canonical.
class ProjectListDocument {
  final TaskFileSnapshot snapshot;
  final List<int> itemLines;
  final String title;
  const ProjectListDocument._(this.snapshot, this.itemLines, this.title);

  factory ProjectListDocument.parse(
    TaskFileSnapshot snapshot,
    String fallbackTitle,
  ) {
    final lines = snapshot.lines;
    var title = fallbackTitle;
    var hasTitle = false;
    final items = <int>[];
    for (final index in unfencedBodyLines(lines)) {
      final line = lines[index];
      if (!hasTitle && line.startsWith('# ')) {
        title = line.substring(2).trim();
        hasTitle = true;
      }
      if (line.startsWith('- ')) items.add(index);
    }
    return ProjectListDocument._(snapshot, List.unmodifiable(items), title);
  }

  List<String> get items => [
    for (final index in itemLines) snapshot.lines[index].substring(2),
  ];

  bool _plainTail(int item) {
    final start = itemLines[item] + 1;
    final end =
        item + 1 < itemLines.length
            ? itemLines[item + 1]
            : snapshot.lines.length;
    return snapshot.lines
        .sublist(start, end)
        .every((line) => line.trim().isEmpty);
  }

  Future<GuardedTaskMutationResult> edit(String path, int item, String text) {
    if (text.contains('\n') || text.contains('\r') || text.trim().isEmpty) {
      return Future.value(_refused);
    }
    return TaskStorageService.guardedUpdateLine(
      path,
      snapshot,
      itemLines[item],
      '- $text',
    );
  }

  Future<GuardedTaskMutationResult> add(String path, String text) =>
      MarkdownFile.guardedEditLines(path, snapshot, (lines) {
        if (text.contains('\n') || text.contains('\r') || text.trim().isEmpty) {
          return false;
        }
        if (lines.isNotEmpty && lines.last.isNotEmpty) lines.add('');
        lines.add('- $text');
        return true;
      });

  Future<GuardedTaskMutationResult> delete(String path, int item) =>
      _plainTail(item)
          ? TaskStorageService.guardedDeleteLine(
            path,
            snapshot,
            itemLines[item],
          )
          : Future.value(_refused);

  Future<GuardedTaskMutationResult> reorder(
    String path,
    int oldIndex,
    int newIndex,
  ) {
    if (!List.generate(itemLines.length, (index) => index).every(_plainTail)) {
      return Future.value(_refused);
    }
    return MarkdownFile.guardedEditLines(path, snapshot, (lines) {
      final ordered = items;
      ordered.insert(newIndex, ordered.removeAt(oldIndex));
      for (var index = 0; index < itemLines.length; index++) {
        lines[itemLines[index]] = '- ${ordered[index]}';
      }
      return true;
    });
  }

  static const _refused = GuardedTaskMutationResult(
    GuardedTaskMutationStatus.refused,
    'This item has additional content that the list editor cannot safely move or remove. Edit it in Obsidian.',
  );
}
