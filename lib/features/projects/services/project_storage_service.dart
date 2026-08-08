import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/markdown/vault_scanner.dart';
import '../models/project_file.dart';

class ProjectMeta {
  final String title;
  final Map<dynamic, dynamic> frontmatterMap;
  final String body;
  const ProjectMeta({required this.title, required this.frontmatterMap, required this.body});
}

class ProjectStorageService {
  static final _taskRegex = RegExp(r'^\s*-\s+\[([ xX])\]\s+');

  static Future<List<ProjectFile>> loadAll(String vaultPath) async {
    final results = <ProjectFile>[];
    final dirPath = VaultService.projectsPath(vaultPath);
    await for (final entry in VaultScanner.scan(dirPath, recursive: false)) {
      try {
        final content = await entry.readAsString();
        results.add(_parse(entry.path, content));
      } catch (_) {}
    }
    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  static ProjectFile _parse(String filePath, String content) {
    final split = splitFrontmatter(content);
    final yamlMap = parseYamlMap(split.frontmatter);
    final isListStyle = yamlMap != null && yamlMap['type'] == 'list';
    final name = extractH1(split.body) ?? p.basenameWithoutExtension(filePath);
    int total = 0, completed = 0;
    for (final line in split.body.split('\n')) {
      final m = _taskRegex.firstMatch(line);
      if (m != null) {
        total++;
        if (m.group(1)!.toLowerCase() == 'x') completed++;
      }
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
      final filePath = p.join(VaultService.projectsPath(vaultPath), '$safeName.md');
      final file = File(filePath);
      if (await file.exists()) return null;
      final content = listStyle
          ? '---\ntype: list\n---\n# $name\n\n'
          : '# $name\n\n';
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

  static Future<void> deleteProject(String vaultPath, ProjectFile project) async {
    try {
      final file = File(project.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<String?> loadProjectContent(String filePath) async {
    try {
      return await File(filePath).readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<ProjectMeta?> loadProjectMeta(String filePath) async {
    try {
      final content = await loadProjectContent(filePath);
      if (content == null) return null;
      final split = splitFrontmatter(content);
      final yamlMap = parseYamlMap(split.frontmatter) ?? {};
      final title = extractH1(split.body) ?? p.basenameWithoutExtension(filePath);
      return ProjectMeta(title: title, frontmatterMap: yamlMap, body: split.body);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProjectContent(String filePath, String content) async {
    try {
      await File(filePath).writeAsString(content);
    } catch (_) {}
  }

  // Named ByPath to avoid conflict with renameProject(vaultPath, ProjectFile, newName).
  static Future<String?> renameProjectByPath(String filePath, String newTitle) async {
    try {
      final lines = await File(filePath).readAsLines();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('# ') && !lines[i].startsWith('## ')) {
          lines[i] = '# $newTitle';
          break;
        }
      }
      final safeName = newTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final newPath = p.join(p.dirname(filePath), '$safeName.md');
      await File(filePath).writeAsString(lines.join('\n'));
      if (newPath != filePath) {
        if (await File(newPath).exists()) return null;
        await File(filePath).rename(newPath);
      }
      return newPath;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> renameProject(
      String vaultPath, ProjectFile project, String newName) async {
    try {
      final file = File(project.filePath);
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('# ') && !lines[i].startsWith('## ')) {
          lines[i] = '# $newName';
          break;
        }
      }
      final safeName = newName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final newPath = p.join(p.dirname(project.filePath), '$safeName.md');
      await file.writeAsString(lines.join('\n'));
      if (newPath != project.filePath) {
        if (await File(newPath).exists()) return null;
        await File(project.filePath).rename(newPath);
      }
      return newPath;
    } catch (_) {
      return null;
    }
  }
}
