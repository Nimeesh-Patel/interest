import 'package:people_tracker/shared/markdown/markdown_file.dart';
import 'package:flutter/material.dart';

import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/app_fab.dart';
import '../../../shared/widgets/bottom_sheet_menu.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/progress.dart';
import '../../../shared/widgets/wikilink_text.dart';
import '../services/project_storage_service.dart';
import '../services/project_list_document.dart';
import '../../../shared/widgets/snack.dart';

class ProjectListDetailScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onRenamed;

  const ProjectListDetailScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.onRenamed,
  });

  @override
  State<ProjectListDetailScreen> createState() =>
      _ProjectListDetailScreenState();
}

class _ProjectListDetailScreenState extends State<ProjectListDetailScreen> {
  List<String> _items = [];
  ProjectListDocument? _document;
  late String _currentPath;
  bool _saving = false;
  String _title = '';
  bool _loading = true;
  int? _editingIndex;
  final _editController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentPath = widget.filePath;
    _title = widget.title;
    _load();
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await MarkdownFile.loadSnapshot(_currentPath);
    if (!mounted) return;
    try {
      if (loaded.snapshot == null) {
        throw FormatException(loaded.error ?? 'Could not read the project.');
      }
      final document = ProjectListDocument.parse(loaded.snapshot!, _title);
      setState(() {
        _document = document;
        _items = document.items;
        _title = document.title;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _document = null;
        _loading = false;
      });
      showSnack(context, '$error');
    }
  }

  Future<void> _mutate(
    Future<GuardedTaskMutationResult> Function(ProjectListDocument) operation,
  ) async {
    if (_saving || _document == null) return;
    _saving = true;
    try {
      final result = await operation(_document!);
      if (!mounted) return;
      if (!result.applied) showSnack(context, result.message);
      await _load();
    } finally {
      _saving = false;
    }
  }

  void _saveEdit(int index) async {
    final text = _editController.text.trim();
    if (text.isEmpty) return;
    await _mutate((document) => document.edit(_currentPath, index, text));
    if (mounted) setState(() => _editingIndex = null);
  }

  void _deleteItem(int index) =>
      _mutate((document) => document.delete(_currentPath, index));
  void _onReorderItem(int oldIndex, int newIndex) =>
      _mutate((document) => document.reorder(_currentPath, oldIndex, newIndex));

  void _addItem() async {
    if (!mounted || _saving) return;
    final text = await showInputDialog(
      context,
      title: 'Add item',
      hintText: 'Item text',
      confirmLabel: 'Add',
    );
    if (text == null || text.trim().isEmpty) return;
    await _mutate((document) => document.add(_currentPath, text.trim()));
  }

  void _showOptions() {
    showBottomSheetMenu(
      context,
      items: [
        BottomSheetMenuItem(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: _showRename,
        ),
      ],
    );
  }

  Future<void> _showRename() async {
    if (!mounted) return;
    final name = await showInputDialog(
      context,
      title: 'Rename',
      initialValue: _title,
      confirmLabel: 'Rename',
      capitalization: TextCapitalization.words,
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    if (_saving) return;
    final renamed = await ProjectStorageService.renameProject(
      _currentPath,
      trimmed,
      expected: _document?.snapshot,
    );
    if (!mounted) return;
    if (renamed == null) {
      showSnack(context, 'Rename failed; the project was not moved.');
      await _load();
      return;
    }
    _currentPath = renamed;
    if (!mounted) return;
    setState(() => _title = trimmed);
    widget.onRenamed?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showOptions,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child:
            _loading
                ? const LoadingState()
                : _items.isEmpty
                ? const EmptyState(message: 'No items yet.\nTap + to add one.')
                : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: kFabListBottomPad),
                  itemCount: _items.length,
                  onReorderItem: _onReorderItem,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    if (_editingIndex == i) {
                      return ListTile(
                        key: ValueKey('edit-$i'),
                        title: TextField(
                          controller: _editController,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(isDense: true),
                          onSubmitted: (_) => _saveEdit(i),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, size: 18),
                              onPressed: () => _saveEdit(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed:
                                  () => setState(() => _editingIndex = null),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListTile(
                      key: ValueKey('item-$i-$item'),
                      title: WikilinkText(
                        text: item,
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.textTertiary,
                            ),
                            onPressed: () => _deleteItem(i),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(
                              Icons.drag_handle,
                              size: 20,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        _editController.text = item;
                        setState(() => _editingIndex = i);
                      },
                    );
                  },
                ),
      ),
      floatingActionButton: AppFab(tooltip: 'Add item', onTap: _addItem),
    );
  }
}
