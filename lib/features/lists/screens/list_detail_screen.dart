import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/wikilink_text.dart';
import '../models/list_model.dart';
import '../services/list_storage_service.dart';

class ListDetailScreen extends StatefulWidget {
  final ListModel list;

  const ListDetailScreen({super.key, required this.list});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  late ListModel _list;
  int? _editingIndex;
  final _editController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _list = widget.list;
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<String?> get _vault => VaultService.getVaultPath();

  void _saveEdit(int index) async {
    final text = _editController.text.trim();
    // Clear editing state before any await so the TextField (and its controller
    // dependency) is removed from the tree before disposal can race with it.
    setState(() => _editingIndex = null);
    if (text.isEmpty) return;
    final vault = await _vault;
    if (vault == null) return;
    await ListStorageService.updateItem(vault, _list, index, text);
    if (mounted) setState(() {});
  }

  void _deleteItem(int index) async {
    final vault = await _vault;
    if (vault == null) return;
    await ListStorageService.removeItem(vault, _list, index);
    if (mounted) setState(() {});
  }

  void _addItem() async {
    final vault = await _vault;
    if (vault == null) return;
    if (!mounted) return;
    final text = await showInputDialog(context,
      title: 'Add item',
      hintText: 'Item text',
      confirmLabel: 'Add',
    );
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) return;
    await ListStorageService.addItem(vault, _list, text.trim());
    if (mounted) setState(() {});
  }

  void _onReorder(int oldIndex, int newIndex) async {
    final vault = await _vault;
    if (vault == null) return;
    await ListStorageService.reorderItems(vault, _list, oldIndex, newIndex);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_list.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        child: _list.items.isEmpty
            ? const Center(
                child: Text('No items yet.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: kFabListBottomPad),
                itemCount: _list.items.length,
                onReorder: _onReorder,
                itemBuilder: (ctx, i) {
                  final item = _list.items[i];
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
                              size: 18, color: Colors.grey),
                          onPressed: () => _deleteItem(i),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle,
                              size: 20, color: Colors.grey),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        tooltip: 'Add item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
