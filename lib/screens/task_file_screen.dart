import 'package:flutter/material.dart';

import '../models/task_block.dart';
import '../services/task_storage_service.dart';

class TaskFileScreen extends StatefulWidget {
  final String filePath;
  final String title;
  // Called when the file is renamed so HomeScreen can reload.
  final void Function(String newPath, String newTitle)? onRenamed;

  const TaskFileScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.onRenamed,
  });

  @override
  State<TaskFileScreen> createState() => _TaskFileScreenState();
}

class _TaskFileScreenState extends State<TaskFileScreen> {
  static final _wikilinkRegex = RegExp(r'\[\[([^\]]+)\]\]');

  List<String> _lines = [];
  List<TaskNode> _nodes = [];
  bool _isLoading = true;
  late String _currentTitle;
  late String _currentPath;

  // Bottom bar for quick root-task add
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  // Collapse state — keyed by block.startLine; session-only, not persisted
  final Set<int> _collapsed = {};

  // Inline task text editing
  int? _editingLine;
  final _editController = TextEditingController();

  // Inline note editing
  int? _editingNoteLine;
  final _editNoteController = TextEditingController();

  // Inline subtask add — value is parent.startLine; -1 means root add
  int? _addingChildOf;
  final _addChildController = TextEditingController();

  // Inline note add — value is parent.startLine
  int? _addingNoteOf;
  final _addNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _currentPath = widget.filePath;
    _reload();
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    _editController.dispose();
    _editNoteController.dispose();
    _addChildController.dispose();
    _addNoteController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final lines = await TaskStorageService.loadLines(_currentPath);
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _nodes = TaskStorageService.parseNodes(lines);
      _isLoading = false;
      // Clear transient edit state after reload
      _editingLine = null;
      _editingNoteLine = null;
      _addingChildOf = null;
      _addingNoteOf = null;
    });
  }

  // ── Root-level quick add ──────────────────────────────────────────────────

  Future<void> _addRootTask() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    _addController.clear();
    await TaskStorageService.addTask(_currentPath, text);
    await _reload();
  }

  // ── Block mutations ───────────────────────────────────────────────────────

  Future<void> _toggle(TaskBlock block) async {
    await TaskStorageService.toggleTask(_currentPath, block.startLine);
    await _reload();
  }

  Future<void> _saveBlockEdit(TaskBlock block) async {
    final text = _editController.text.trim();
    if (text.isNotEmpty) {
      await TaskStorageService.updateBlockText(_currentPath, block, text);
    }
    await _reload();
  }

  Future<void> _saveNoteEdit(int lineIndex) async {
    if (lineIndex >= _lines.length) return;
    final original = _lines[lineIndex];
    final trimStart = original.length - original.trimLeft().length;
    final indent = original.substring(0, trimStart);
    final newContent = '$indent${_editNoteController.text}';
    await TaskStorageService.updateLine(_currentPath, lineIndex, newContent);
    await _reload();
  }

  Future<void> _deleteBlock(TaskBlock block) async {
    await TaskStorageService.deleteBlock(_currentPath, block);
    await _reload();
  }

  Future<void> _addSubtask(TaskBlock parent) async {
    final text = _addChildController.text.trim();
    if (text.isNotEmpty) {
      await TaskStorageService.addSubtask(_currentPath, parent, text);
    }
    setState(() => _addingChildOf = null);
    await _reload();
  }

  Future<void> _addNote(TaskBlock parent) async {
    final text = _addNoteController.text.trim();
    if (text.isNotEmpty) {
      await TaskStorageService.addNote(_currentPath, parent, text);
    }
    setState(() => _addingNoteOf = null);
    await _reload();
  }

  // ── Rename ────────────────────────────────────────────────────────────────

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _currentTitle);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) {
            Navigator.pop(ctx);
            _doRename(v);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doRename(ctrl.text);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  Future<void> _doRename(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == _currentTitle) return;
    final newPath = await TaskStorageService.renameTaskFile(_currentPath, trimmed);
    if (!mounted) return;
    if (newPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rename failed — name already in use.')),
      );
      return;
    }
    setState(() {
      _currentTitle = trimmed;
      _currentPath = newPath;
    });
    widget.onRenamed?.call(newPath, trimmed);
    await _reload();
  }

  // ── Wikilink-aware text renderer ──────────────────────────────────────────

  Widget _buildRichText(String text, TextStyle base, {bool strikethrough = false}) {
    final style = strikethrough
        ? base.copyWith(
            color: Colors.grey.shade400,
            decoration: TextDecoration.lineThrough,
          )
        : base;
    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final m in _wikilinkRegex.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: style));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: style.copyWith(
          color: strikethrough ? Colors.grey.shade400 : Colors.blue,
          fontWeight: FontWeight.bold,
          decoration: strikethrough ? TextDecoration.lineThrough : null,
        ),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return RichText(text: TextSpan(children: spans));
  }

  // ── Node renderer dispatch ────────────────────────────────────────────────

  Widget _buildNodeWidget(TaskNode node) {
    if (node is TaskHeaderNode) return _buildHeaderWidget(node);
    if (node is TaskProseNode) return _buildProseWidget(node);
    if (node is TaskBlock) return _buildBlockWidget(node, 0);
    return const SizedBox.shrink();
  }

  Widget _buildHeaderWidget(TaskHeaderNode node) {
    final isH2 = node.headingLevel == 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isH2 ? 20 : 12, 16, 4),
      child: Text(
        node.text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isH2 ? 16 : 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildProseWidget(TaskProseNode node) {
    if (node.raw.trim().isEmpty) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Text(node.raw, style: const TextStyle(color: Colors.black54, fontSize: 14)),
    );
  }

  // ── Task block renderer ───────────────────────────────────────────────────

  Widget _buildBlockWidget(TaskBlock block, int depth) {
    final leftPad = depth * 20.0;
    final hasExpandable =
        block.children.isNotEmpty || block.noteLineIndices.isNotEmpty;
    final isCollapsed = _collapsed.contains(block.startLine);
    final isEditing = _editingLine == block.startLine;
    final isAddingChild = _addingChildOf == block.startLine;

    final taskTextStyle = TextStyle(
      fontSize: depth == 0 ? 15 : 14,
      fontWeight: depth == 0 ? FontWeight.w500 : FontWeight.normal,
      color: Theme.of(context).colorScheme.onSurface,
    );

    return Padding(
      padding: EdgeInsets.only(left: leftPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Task row ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Collapse chevron
              SizedBox(
                width: 24,
                child: hasExpandable
                    ? GestureDetector(
                        onTap: () => setState(() {
                          if (isCollapsed) {
                            _collapsed.remove(block.startLine);
                          } else {
                            _collapsed.add(block.startLine);
                          }
                        }),
                        child: Icon(
                          isCollapsed
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                      )
                    : null,
              ),
              // Checkbox
              SizedBox(
                width: 32,
                height: 32,
                child: Checkbox(
                  value: block.completed,
                  onChanged: (_) => _toggle(block),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // Task text / inline editor
              Expanded(
                child: isEditing
                    ? TextField(
                        controller: _editController,
                        autofocus: true,
                        style: taskTextStyle,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveBlockEdit(block),
                        onTapOutside: (_) => _saveBlockEdit(block),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            _editingLine = block.startLine;
                            _editController.text = block.text;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _buildRichText(
                            block.text,
                            taskTextStyle,
                            strikethrough: block.completed,
                          ),
                        ),
                      ),
              ),
              // Add note button
              if (!isEditing)
                IconButton(
                  icon: Icon(Icons.sticky_note_2_outlined, size: 16, color: Colors.grey.shade500),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                  tooltip: 'Add note',
                  onPressed: () => setState(() {
                    _addingNoteOf = block.startLine;
                    _addNoteController.clear();
                  }),
                ),
              // Add subtask button
              if (!isEditing)
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Add subtask',
                  color: Colors.grey.shade500,
                  onPressed: () => setState(() {
                    _addingChildOf = block.startLine;
                    _addChildController.clear();
                  }),
                ),
              // Delete button
              if (!isEditing)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.grey.shade400),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDeleteBlock(block),
                ),
            ],
          ),
          // ── Inline note add field ─────────────────────────────────────
          if (!isCollapsed && _addingNoteOf == block.startLine)
            _buildInlineNoteAddField(block, depth),
          // ── Notes (if not collapsed) ──────────────────────────────────
          if (!isCollapsed)
            for (final idx in block.noteLineIndices)
              _buildNoteLineWidget(idx, depth),
          // ── Inline subtask add field ──────────────────────────────────
          if (isAddingChild)
            _buildInlineAddField(block, depth),
          // ── Children (if not collapsed) ───────────────────────────────
          if (!isCollapsed)
            for (final child in block.children) _buildBlockWidget(child, depth + 1),
        ],
      ),
    );
  }

  Widget _buildNoteLineWidget(int lineIdx, int depth) {
    if (lineIdx >= _lines.length) return const SizedBox.shrink();
    final raw = _lines[lineIdx];
    if (raw.trim().isEmpty) return const SizedBox(height: 4);

    final isEditing = _editingNoteLine == lineIdx;

    return Padding(
      padding: EdgeInsets.only(left: 56.0 + (depth * 20.0), right: 8, top: 2, bottom: 2),
      child: isEditing
          ? TextField(
              controller: _editNoteController,
              autofocus: true,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 2),
              ),
              maxLines: null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveNoteEdit(lineIdx),
              onTapOutside: (_) => _saveNoteEdit(lineIdx),
            )
          : GestureDetector(
              onTap: () => setState(() {
                _editingNoteLine = lineIdx;
                _editNoteController.text = raw.trimLeft();
              }),
              child: _buildRichText(
                raw.trimLeft(),
                TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
    );
  }

  Widget _buildInlineAddField(TaskBlock parent, int depth) {
    return Padding(
      padding: EdgeInsets.only(left: 56.0 + ((depth + 1) * 20.0), right: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addChildController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Subtask…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              style: const TextStyle(fontSize: 14),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _addSubtask(parent),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _addSubtask(parent),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => setState(() => _addingChildOf = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineNoteAddField(TaskBlock parent, int depth) {
    return Padding(
      padding: EdgeInsets.only(left: 56.0 + (depth * 20.0), right: 8, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _addNoteController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Note…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700,
              ),
              maxLines: null,
              textInputAction: TextInputAction.newline,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _addNote(parent),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => setState(() => _addingNoteOf = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Delete confirmation ───────────────────────────────────────────────────

  Future<void> _confirmDeleteBlock(TaskBlock block) async {
    final hasChildren = block.children.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(hasChildren
            ? '"${block.text}" and all its subtasks will be removed.'
            : '"${block.text}"'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _deleteBlock(block);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTitle),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
            ],
            onSelected: (v) {
              if (v == 'rename') _showRenameDialog();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _nodes.isEmpty
                      ? const Center(
                          child: Text(
                            'No content yet.\nAdd a task below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          children: _nodes
                              .map(_buildNodeWidget)
                              .toList(),
                        ),
                ),
                const Divider(height: 1),
                // SafeArea handles Android gesture nav bar bottom inset;
                // Scaffold resizeToAvoidBottomInset handles keyboard.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
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
                            onSubmitted: (_) => _addRootTask(),
                            textInputAction: TextInputAction.send,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _addRootTask,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
