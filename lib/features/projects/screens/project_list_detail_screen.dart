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
  State<ProjectListDetailScreen> createState() => _ProjectListDetailScreenState();
}

class _ProjectListDetailScreenState extends State<ProjectListDetailScreen> {
  List<String> _items = [];
  String _title = '';
  bool _loading = true;
  int? _editingIndex;
  final _editController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _load();
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final meta = await ProjectStorageService.loadProjectMeta(widget.filePath);
    if (!mounted) return;
    if (meta == null) {
      setState(() => _loading = false);
      return;
    }
    final items = meta.body
        .split('\n')
        .where((l) => l.startsWith('- '))
        .map((l) => l.substring(2))
        .toList();
    setState(() {
      _title = meta.title;
      _items = items;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final h1 = _title.isNotEmpty ? '# $_title\n\n' : '';
    final itemLines = _items.map((i) => '- $i').join('\n');
    final content = '---\ntype: list\n---\n$h1$itemLines\n';
    await ProjectStorageService.saveProjectContent(widget.filePath, content);
  }

  void _saveEdit(int index) async {
    final text = _editController.text.trim();
    setState(() => _editingIndex = null);
    if (text.isEmpty) return;
    setState(() => _items[index] = text);
    await _save();
  }

  void _deleteItem(int index) async {
    setState(() => _items.removeAt(index));
    await _save();
  }

  void _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    await _save();
  }

  void _addItem() async {
    if (!mounted) return;
    final text = await showInputDialog(
      context,
      title: 'Add item',
      hintText: 'Item text',
      confirmLabel: 'Add',
    );
    if (text == null || text.trim().isEmpty) return;
    setState(() => _items.add(text.trim()));
    await _save();
  }

  void _showOptions() {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
        onTap: _showRename,
      ),
    ]);
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
    await ProjectStorageService.renameProjectByPath(widget.filePath, trimmed);
    if (!mounted) return;
    setState(() => _title = trimmed);
    widget.onRenamed?.call();
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
        child: _loading
            ? const LoadingState()
            : _items.isEmpty
                ? const EmptyState(message: 'No items yet.\nTap + to add one.')
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: kFabListBottomPad),
                    itemCount: _items.length,
                    onReorder: _onReorder,
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
                                onPressed: () => setState(() => _editingIndex = null),
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
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.textTertiary),
                              onPressed: () => _deleteItem(i),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle,
                                  size: 20, color: AppColors.textTertiary),
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
