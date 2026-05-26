import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/project_file.dart';

class ProjectStorageService {
  static final _taskRegex = RegExp(r'^\s*-\s+\[([ xX])\]\s+');

  static Future<List<ProjectFile>> loadAll(String vaultPath) async {
    await _migrateIfNeeded(vaultPath);
    final results = <ProjectFile>[];
    for (final dirPath in [
      VaultService.projectsPath(vaultPath),
      VaultService.listsPath(vaultPath),
      VaultService.tasksPath(vaultPath),
    ]) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entry in dir.list()) {
          if (entry is! File || !entry.path.endsWith('.md')) continue;
          try {
            final content = await entry.readAsString();
            results.add(_parse(entry.path, content));
          } catch (_) {}
        }
      } catch (_) {}
    }
    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  // Moves all .md files from Lists/ and Tasks/ into Projects/.
  // Best-effort: file-by-file; a failure on one does not abort others.
  // Idempotent: if source dirs are empty or absent, this is a no-op.
  static Future<void> _migrateIfNeeded(String vaultPath) async {
    final projectsDir = VaultService.projectsPath(vaultPath);
    for (final srcPath in [
      VaultService.listsPath(vaultPath),
      VaultService.tasksPath(vaultPath),
    ]) {
      try {
        final dir = Directory(srcPath);
        if (!await dir.exists()) continue;
        final files = <File>[];
        await for (final entry in dir.list()) {
          if (entry is File && entry.path.endsWith('.md')) files.add(entry);
        }
        for (final file in files) {
          try {
            final dest = _uniqueDestPath(projectsDir, p.basename(file.path));
            await file.copy(dest);
            await file.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  static String _uniqueDestPath(String projectsDir, String filename) {
    var dest = p.join(projectsDir, filename);
    if (!File(dest).existsSync()) return dest;
    final base = p.basenameWithoutExtension(filename);
    var i = 1;
    while (File(dest).existsSync()) {
      dest = p.join(projectsDir, '${base}_$i.md');
      i++;
    }
    return dest;
  }

  static ProjectFile _parse(String filePath, String content) {
    final split = splitFrontmatter(content);
    final yamlMap = parseYamlMap(split.frontmatter);
    final isListStyle = yamlMap != null && yamlMap['type'] == 'list';
    final lines = split.body.split('\n');
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
