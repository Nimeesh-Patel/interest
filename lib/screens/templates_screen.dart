import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../services/vault_service.dart';
import 'template_editor_screen.dart';

typedef _TemplateInfo = ({
  String filename,
  String displayName,
  String category,
  String filePath,
});

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<_TemplateInfo> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final tdir = Directory(VaultService.templatesPath(vaultPath));
      final templates = <_TemplateInfo>[];

      if (await tdir.exists()) {
        final all = await tdir.list().toList();
        for (final f in all.whereType<File>().where((f) => f.path.endsWith('.md'))) {
          try {
            final content = await f.readAsString();
            final category = _extractCategory(content);
            final filename = p.basename(f.path);
            final displayName = _toDisplayName(p.basenameWithoutExtension(f.path));
            templates.add((
              filename: filename,
              displayName: displayName,
              category: category,
              filePath: f.path,
            ));
          } catch (_) {}
        }
      }

      templates.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (mounted) setState(() { _templates = templates; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractCategory(String content) {
    try {
      final lines = content.split('\n');
      if (lines.isEmpty || lines[0].trim() != '---') return '';
      int closeIdx = -1;
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim() == '---') { closeIdx = i; break; }
      }
      if (closeIdx == -1) return '';
      final frontmatter = lines.sublist(1, closeIdx).join('\n');
      final yaml = loadYaml(frontmatter);
      if (yaml is YamlMap) return yaml['category']?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  String _toDisplayName(String slug) {
    return slug
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _slugify(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  Future<void> _showCreateDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Template'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) {
            Navigator.pop(ctx);
            _createTemplate(v);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _createTemplate(ctrl.text);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createTemplate(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final slug = _slugify(trimmed);
    if (slug.isEmpty) return;

    final vaultPath = await VaultService.getVaultPath();
    if (vaultPath == null) return;
    final tdir = VaultService.templatesPath(vaultPath);
    final filePath = p.join(tdir, '$slug.md');

    if (await File(filePath).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A template named "$slug" already exists.')),
        );
      }
      return;
    }

    const initialContent = '---\ncategory: \ntemplate: true\n---\n# {{title}}\n\n## Why Interesting\n\n## Related\n\n## Sources\n';
    await File(filePath).writeAsString(initialContent);

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TemplateEditorScreen(
            filePath: filePath,
            displayName: _toDisplayName(slug),
          ),
        ),
      );
      _loadTemplates();
    }
  }

  Future<void> _confirmDelete(_TemplateInfo item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${item.displayName}"?'),
        content: const Text('This will remove the template file from your vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try { await File(item.filePath).delete(); } catch (_) {}
      _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? const Center(
                  child: Text(
                    'No templates yet.\nTap + to create one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _templates.length,
                  itemBuilder: (ctx, i) {
                    final item = _templates[i];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(item.displayName),
                      subtitle: item.category.isEmpty ? null : Text(item.category),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(item),
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TemplateEditorScreen(
                              filePath: item.filePath,
                              displayName: item.displayName,
                            ),
                          ),
                        );
                        _loadTemplates();
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        tooltip: 'New template',
        child: const Icon(Icons.add),
      ),
    );
  }
}
