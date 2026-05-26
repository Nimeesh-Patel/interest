import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/widgets/bottom_sheet_menu.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../tasks/screens/task_file_screen.dart';
import '../models/project_file.dart';
import '../screens/project_list_detail_screen.dart';
import '../services/project_storage_service.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => ProjectsScreenState();
}

class ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectFile> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vault = await VaultService.getVaultPath();
    if (!mounted) return;
    if (vault == null) {
      setState(() => _loading = false);
      return;
    }
    final projects = await ProjectStorageService.loadAll(vault);
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final vault = await VaultService.getVaultPath();
    if (vault == null || !mounted) return;
    final projects = await ProjectStorageService.loadAll(vault);
    if (mounted) setState(() => _projects = projects);
  }

  Future<void> showCreateDialog(BuildContext ctx) async {
    showBottomSheetMenu(ctx, items: [
      BottomSheetMenuItem(
        icon: Icons.check_box_outline_blank,
        label: 'Todo outline',
        onTap: () => _createProject(ctx, listStyle: false),
      ),
      BottomSheetMenuItem(
        icon: Icons.format_list_bulleted,
        label: 'Simple list',
        onTap: () => _createProject(ctx, listStyle: true),
      ),
    ]);
  }

  Future<void> _createProject(BuildContext ctx, {required bool listStyle}) async {
    final vault = await VaultService.getVaultPath();
    if (vault == null || !ctx.mounted) return;
    final name = await showInputDialog(
      ctx,
      title: listStyle ? 'New list' : 'New project',
      hintText: 'Name',
      confirmLabel: 'Create',
      capitalization: TextCapitalization.words,
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final project = await ProjectStorageService.createProject(
      vault,
      trimmed,
      listStyle: listStyle,
    );
    if (project == null || !ctx.mounted) return;
    await _reload();
    if (!ctx.mounted) return;
    await _openProject(ctx, project);
    await _reload();
  }

  Future<void> _openProject(BuildContext ctx, ProjectFile proj) async {
    if (proj.isListStyle) {
      await Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => ProjectListDetailScreen(
            filePath: proj.filePath,
            title: proj.name,
            onRenamed: _reload,
          ),
        ),
      );
    } else {
      await Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => TaskFileScreen(
            filePath: proj.filePath,
            title: proj.name,
            onRenamed: (_, _) => _reload(),
          ),
        ),
      );
    }
  }

  void _showProjectOptions(BuildContext ctx, ProjectFile project) {
    showBottomSheetMenu(ctx, items: [
      BottomSheetMenuItem(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
        onTap: () => _showRenameProject(project),
      ),
      BottomSheetMenuItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        isDestructive: true,
        onTap: () => _showDeleteProject(project),
      ),
    ]);
  }

  Future<void> _showRenameProject(ProjectFile project) async {
    final vault = await VaultService.getVaultPath();
    if (vault == null || !mounted) return;
    final name = await showInputDialog(
      context,
      title: 'Rename project',
      initialValue: project.name,
      confirmLabel: 'Rename',
      capitalization: TextCapitalization.words,
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == project.name) return;
    final result = await ProjectStorageService.renameProject(vault, project, trimmed);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rename failed — name already in use.')),
      );
      return;
    }
    await _reload();
  }

  Future<void> _showDeleteProject(ProjectFile project) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete project?',
      message: 'Delete "${project.name}"? This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    final vault = await VaultService.getVaultPath();
    if (vault == null) return;
    await ProjectStorageService.deleteProject(vault, project);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_projects.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_outlined,
        message: 'No projects yet.\nTap + to create one.',
      );
    }
    return SafeArea(
      top: false,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: kFabListBottomPad),
        itemCount: _projects.length,
        itemBuilder: (ctx, i) {
          final proj = _projects[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: Icon(
                proj.isListStyle ? Icons.format_list_bulleted : Icons.folder_outlined,
                color: Colors.grey.shade400,
              ),
              title: Text(proj.name),
              subtitle: proj.totalTasks == 0
                  ? const Text('Empty', style: TextStyle(fontSize: 12))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: proj.progress,
                          minHeight: 5,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${proj.completedTasks} / ${proj.totalTasks} done',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
              onTap: () async {
                await _openProject(ctx, proj);
                await _reload();
              },
              onLongPress: () => _showProjectOptions(ctx, proj),
            ),
          );
        },
      ),
    );
  }
}
