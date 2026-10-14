import 'package:people_tracker/shared/markdown/markdown_file.dart';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../../tasks/services/task_storage_service.dart';
import '../../tasks/models/task_block.dart';
import '../models/project_file.dart';

class ProjectStorageService {
  static Future<List<ProjectFile>> loadAll(String vaultPath) async {
    final results = <ProjectFile>[];
    final dirPath = VaultService.projectsPath(vaultPath);
    await for (final entry in VaultScanner.scan(dirPath, recursive: false)) {
      try {
        final content = await entry.readAsString();
        results.add(_parse(entry.path, content));
      } catch (_) {}
    }
    results.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return results;
  }

  static ProjectFile _parse(String filePath, String content) {
    final split = splitFrontmatter(content);
    final yamlMap = parseYamlMap(split.frontmatter);
    final isListStyle = yamlMap != null && yamlMap['type'] == 'list';
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final titles = unfencedBodyLines(
      lines,
    ).where((index) => lines[index].startsWith('# '));
    final name =
        titles.isEmpty
            ? p.basenameWithoutExtension(filePath)
            : lines[titles.first].substring(2).trim();
    int total = 0, completed = 0;
    void count(TaskBlock block) {
      total++;
      if (block.completed) completed++;
      for (final child in block.children) {
        count(child);
      }
    }

    for (final block
        in TaskStorageService.parseNodes(lines).whereType<TaskBlock>()) {
      count(block);
    }
    return ProjectFile(
      filePath: filePath,
      name: name,
      totalTasks: total,
      completedTasks: completed,
      isListStyle: isListStyle,
    );
  }

  static Future<ProjectFile?> createProject(
    String vaultPath,
    String name, {
    bool listStyle = false,
  }) async {
    try {
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = p.join(
        VaultService.projectsPath(vaultPath),
        '$safeName.md',
      );
      final file = File(filePath);
      if (await file.exists()) return null;
      final content =
          listStyle ? '---\ntype: list\n---\n# $name\n\n' : '# $name\n\n';
      await file.writeAsString(content);
      return ProjectFile(
        filePath: filePath,
        name: name,
        totalTasks: 0,
        completedTasks: 0,
        isListStyle: listStyle,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteProject(
    String vaultPath,
    ProjectFile project,
  ) async {
    try {
      final file = File(project.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<String?> renameProject(
    String filePath,
    String newTitle, {
    TaskFileSnapshot? expected,
  }) => MarkdownFile.renameTaskFile(filePath, newTitle, expected: expected);
}
