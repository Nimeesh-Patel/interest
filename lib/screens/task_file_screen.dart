import 'package:flutter/material.dart';

import '../services/task_storage_service.dart';

class TaskFileScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const TaskFileScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<TaskFileScreen> createState() => _TaskFileScreenState();
}

class _TaskFileScreenState extends State<TaskFileScreen> {
  static final _taskRegex = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.+)$');
  static final _wikilinkRegex = RegExp(r'\[\[([^\]]+)\]\]');

  List<String> _lines = [];
  bool _isLoading = true;
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final lines = await TaskStorageService.loadLines(widget.filePath);
    if (mounted) {
      setState(() {
        _lines = lines;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggle(int i) async {
    await TaskStorageService.toggleTask(widget.filePath, i);
    await _reload();
  }

  Future<void> _addTask() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    _addController.clear();
    await TaskStorageService.addTask(widget.filePath, text);
    await _reload();
  }

  Future<void> _deleteTask(int i) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(_taskText(_lines[i])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await TaskStorageService.deleteTask(widget.filePath, i);
      await _reload();
    }
  }

  Future<void> _editTask(int i) async {
    final currentText = _taskText(_lines[i]);
    final ctrl = TextEditingController(text: currentText);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit task'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved != null && saved.isNotEmpty) {
      await TaskStorageService.updateTaskText(widget.filePath, i, saved);
      await _reload();
    }
  }

  String _taskText(String line) {
    final m = _taskRegex.firstMatch(line);
    return m != null ? m.group(2)! : line;
  }

  Widget _buildTaskText(String text) {
    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final m in _wikilinkRegex.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: const TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }

  Widget _buildTaskTile(int i, String line) {
    final m = _taskRegex.firstMatch(line)!;
    final isDone = m.group(1)!.toLowerCase() == 'x';
    final text = m.group(2)!;
    return CheckboxListTile(
      value: isDone,
      onChanged: (_) => _toggle(i),
      title: GestureDetector(
        onTap: () => _editTask(i),
        onLongPress: () => _deleteTask(i),
        child: _buildTaskText(text),
      ),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
    );
  }

  Widget _buildLineWidget(int i, String line) {
    if (line.startsWith('# ') && !line.startsWith('## ')) {
      return const SizedBox.shrink();
    }
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          line.substring(4).trim(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      );
    }
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          line.substring(3).trim(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      );
    }
    if (_taskRegex.hasMatch(line)) {
      return _buildTaskTile(i, line);
    }
    if (line.trim().isEmpty) {
      return const SizedBox(height: 6);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Text(line, style: const TextStyle(color: Colors.black87)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _lines.isEmpty
                      ? const Center(
                          child: Text(
                            'No content yet.\nAdd a task below.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _lines.length,
                          itemBuilder: (ctx, i) =>
                              _buildLineWidget(i, _lines[i]),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 12,
                    right: 4,
                    top: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addController,
                          focusNode: _addFocus,
                          decoration: const InputDecoration(
                            hintText: 'Add task…',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _addTask(),
                          textInputAction: TextInputAction.send,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _addTask,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
