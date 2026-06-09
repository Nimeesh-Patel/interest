import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/markdown/md_utils.dart';
import '../../../shared/widgets/bottom_sheet_menu.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/note_markdown.dart';

enum _EditMode { structured, plain, fullEdit }

class NoteEditScreen extends StatefulWidget {
  final String filePath;
  const NoteEditScreen({super.key, required this.filePath});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  bool _loading = true;
  bool _previewMode = false;

  late _EditMode _mode;
  String? _frontmatter;

  // Structured mode
  late TextEditingController _problemController;
  late TextEditingController _ideaController;
  late String _initialProblem;
  late String _initialIdea;
  bool _problemCollapsed = false;
  bool _ideaCollapsed = false;
  final _problemFocus = FocusNode();
  final _ideaFocus = FocusNode();

  // Plain mode
  late TextEditingController _bodyController;
  late String _initialBody;

  // Full edit
  late TextEditingController _fullEditController;
  late String _initialFullEdit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _problemFocus.dispose();
    _ideaFocus.dispose();
    if (!_loading) {
      _problemController.dispose();
      _ideaController.dispose();
      _bodyController.dispose();
      _fullEditController.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await File(widget.filePath).readAsString();
      final split = splitFrontmatter(raw);
      final fb = splitFrontBack(split.body);

      _frontmatter = split.frontmatter;
      _fullEditController = TextEditingController(text: raw);
      _initialFullEdit = raw;

      if (fb != null) {
        _mode = _EditMode.structured;
        _initialProblem = fb.front;
        _initialIdea = fb.back;
        _problemController = TextEditingController(text: fb.front);
        _ideaController = TextEditingController(text: fb.back);
        // Plain controller lazily initialised in case of mode switch — initialise now
        _bodyController = TextEditingController(text: split.body);
        _initialBody = split.body;
      } else {
        _mode = _EditMode.plain;
        _initialBody = split.body;
        _bodyController = TextEditingController(text: split.body);
        _problemController = TextEditingController();
        _ideaController = TextEditingController();
        _initialProblem = '';
        _initialIdea = '';
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Dirty detection ───────────────────────────────────────────────────────

  bool get _isDirty => switch (_mode) {
        _EditMode.structured =>
          _problemController.text != _initialProblem || _ideaController.text != _initialIdea,
        _EditMode.plain => _bodyController.text != _initialBody,
        _EditMode.fullEdit => _fullEditController.text != _initialFullEdit,
      };

  // ── Active controller (routes toolbar actions) ────────────────────────────

  TextEditingController get _activeController {
    if (_mode == _EditMode.plain) return _bodyController;
    if (_ideaFocus.hasFocus) return _ideaController;
    return _problemController;
  }

  // ── Build current content for save / mode switch ──────────────────────────

  String _buildCurrentContent() {
    final fm =
        (_frontmatter != null && _frontmatter!.isNotEmpty) ? '---\n$_frontmatter\n---\n\n' : '';
    return switch (_mode) {
      _EditMode.structured =>
        '$fm${_problemController.text.trim()}\n\n***\n\n${_ideaController.text.trim()}',
      _EditMode.plain => '$fm${_bodyController.text}',
      _EditMode.fullEdit => _fullEditController.text,
    };
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final content = _buildCurrentContent();
    try {
      await File(widget.filePath).writeAsString(content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  // ── Back / discard ────────────────────────────────────────────────────────

  Future<void> _handleBack() async {
    if (!_isDirty) {
      Navigator.pop(context, false);
      return;
    }
    final discard = await showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your edits will be lost.',
      confirmLabel: 'Discard',
      isDestructive: true,
    );
    if (discard && mounted) Navigator.pop(context, false);
  }

  // ── Text manipulation ─────────────────────────────────────────────────────

  void _wrapOrInsert(String prefix, String suffix) {
    final c = _activeController;
    final sel = c.selection;
    if (!sel.isValid || !sel.isNormalized) return;
    final text = c.text;
    final s = sel.start;
    final e = sel.end;
    final newText =
        '${text.substring(0, s)}$prefix${text.substring(s, e)}$suffix${text.substring(e)}';
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: s + prefix.length + (e - s) + suffix.length),
    );
  }

  void _insertAtCursor(String insertion) {
    final c = _activeController;
    final pos = c.selection.isValid ? c.selection.end : c.text.length;
    final newText = '${c.text.substring(0, pos)}$insertion${c.text.substring(pos)}';
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + insertion.length),
    );
  }

  void _insertHeading(int level) {
    final c = _activeController;
    final sel = c.selection;
    final text = c.text;
    final lineStart = sel.isValid
        ? (text.lastIndexOf('\n', (sel.start - 1).clamp(0, text.length)) + 1)
        : text.length;
    final prefix = '${'#' * level} ';
    final newText = '${text.substring(0, lineStart)}$prefix${text.substring(lineStart)}';
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (sel.isValid ? sel.start : lineStart) + prefix.length,
      ),
    );
  }

  // ── Bottom sheets ─────────────────────────────────────────────────────────

  void _showHeadingSheet() {
    showBottomSheetMenu(context, items: [
      for (int i = 1; i <= 5; i++)
        BottomSheetMenuItem(
          icon: Icons.title,
          label: 'Heading $i',
          onTap: () => _insertHeading(i),
        ),
    ]);
  }

  void _showInsertSheet() {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.format_list_bulleted,
        label: 'Bullet list item',
        onTap: () => _insertAtCursor('\n- '),
      ),
      BottomSheetMenuItem(
        icon: Icons.format_list_numbered,
        label: 'Numbered list item',
        onTap: () => _insertAtCursor('\n1. '),
      ),
      BottomSheetMenuItem(
        icon: Icons.link,
        label: 'Wikilink',
        onTap: () => _wrapOrInsert('[[', ']]'),
      ),
    ]);
  }

  // ── UI builders ───────────────────────────────────────────────────────────

  Widget _buildSection(
    String label,
    TextEditingController c,
    FocusNode fn,
    bool collapsed,
    VoidCallback toggle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 12),
            child: Row(
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: TextField(
              controller: c,
              focusNode: fn,
              maxLines: null,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              textInputAction: TextInputAction.newline,
            ),
          ),
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }

  Widget _buildContent() {
    if (_previewMode) {
      final previewText = _mode == _EditMode.structured
          ? '${_problemController.text}\n\n***\n\n${_ideaController.text}'
          : _bodyController.text;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(kScreenHPad),
        child: MarkdownBody(
            data: previewText, styleSheet: noteMarkdownStyle(context)),
      );
    }

    switch (_mode) {
      case _EditMode.structured:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildSection(
                'Problem',
                _problemController,
                _problemFocus,
                _problemCollapsed,
                () => setState(() => _problemCollapsed = !_problemCollapsed),
              ),
              _buildSection(
                'Idea',
                _ideaController,
                _ideaFocus,
                _ideaCollapsed,
                () => setState(() => _ideaCollapsed = !_ideaCollapsed),
              ),
            ],
          ),
        );
      case _EditMode.plain:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 8),
          child: TextField(
            controller: _bodyController,
            maxLines: null,
            expands: false,
            decoration: const InputDecoration(border: InputBorder.none),
            textInputAction: TextInputAction.newline,
          ),
        );
      case _EditMode.fullEdit:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 8),
          child: TextField(
            controller: _fullEditController,
            maxLines: null,
            expands: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(border: InputBorder.none),
            textInputAction: TextInputAction.newline,
          ),
        );
    }
  }

  Widget _buildToolbar() {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: AppColors.background,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _ToolbarBtn(label: 'B', bold: true, onTap: () => _wrapOrInsert('**', '**')),
            _ToolbarBtn(label: 'I', italic: true, onTap: () => _wrapOrInsert('*', '*')),
            _ToolbarBtn(
                label: 'U',
                underline: true,
                onTap: () => _wrapOrInsert('<u>', '</u>')),
            _ToolbarBtn(label: '—', onTap: () => _insertAtCursor('\n---\n')),
            _ToolbarBtn(label: 'T', onTap: _showHeadingSheet),
            _ToolbarBtn(label: '+', onTap: _showInsertSheet),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('Edit note'),
          leading: BackButton(onPressed: _handleBack),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _save,
            ),
            if (_mode != _EditMode.fullEdit)
              IconButton(
                icon: Icon(_previewMode ? Icons.edit_outlined : Icons.visibility_outlined),
                tooltip: _previewMode ? 'Edit' : 'Preview',
                onPressed: () => setState(() => _previewMode = !_previewMode),
              ),
            if (_mode != _EditMode.fullEdit)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'full') {
                    setState(() {
                      _fullEditController.text = _buildCurrentContent();
                      _initialFullEdit = _fullEditController.text;
                      _mode = _EditMode.fullEdit;
                      _previewMode = false;
                    });
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'full', child: Text('Full note edit')),
                ],
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(child: _buildContent()),
              if (_mode != _EditMode.fullEdit && !_previewMode) _buildToolbar(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Toolbar button ────────────────────────────────────────────────────────────

class _ToolbarBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool bold;
  final bool italic;
  final bool underline;

  const _ToolbarBtn({
    required this.label,
    required this.onTap,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline ? TextDecoration.underline : null,
              color: onTap == null ? AppColors.textTertiary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
