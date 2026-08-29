import 'package:flutter/material.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/busy_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _vaultPath;

  // Anki scan scope
  final _excludedController = TextEditingController();
  bool _excludedSaving = false;
  String? _excludedSaveStatus;
  bool _excludedSaveFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _excludedController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted || vaultPath == null) return;
    setState(() => _vaultPath = vaultPath);
    final config = await IntegrationsConfigService.load(vaultPath);
    if (mounted) {
      setState(
        () => _excludedController.text = config.excludedFolders.join(', '),
      );
    }
  }

  Future<void> _saveExcluded() async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    final folders =
        _excludedController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    setState(() {
      _excludedSaving = true;
      _excludedSaveStatus = null;
      _excludedSaveFailed = false;
    });
    final saved = await IntegrationsConfigService.setExcludedFolders(
      vaultPath,
      folders,
    );
    if (mounted) {
      setState(() {
        _excludedSaving = false;
        _excludedSaveFailed = !saved;
        _excludedSaveStatus = saved ? 'Saved.' : 'Save failed.';
      });
    }
  }

  InputDecoration _fieldDecoration(String label, String hint) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Anki sync scope ──────────────────────────────────────────────
            const _SettingsSection(
              title: 'Anki sync',
              description:
                  'Folders the Anki sync skips when scanning the vault for '
                  '*** problem notes (comma-separated).',
            ),
            TextField(
              controller: _excludedController,
              decoration: _fieldDecoration(
                'Excluded folders',
                'Interesting, .obsidian, Templates, Attachments',
              ),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveExcluded(),
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Save',
              busy: _excludedSaving,
              onPressed: _saveExcluded,
            ),
            _StatusLine(_excludedSaveStatus, isError: _excludedSaveFailed),
          ],
        ),
      ),
    );
  }
}

/// Divider + bold title + secondary description — opens every settings group.
class _SettingsSection extends StatelessWidget {
  final String title;
  final String description;

  const _SettingsSection({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Async action status line shown under a [BusyButton]; renders nothing
/// while the status is null.
class _StatusLine extends StatelessWidget {
  final String? status;
  final bool isError;

  const _StatusLine(this.status, {required this.isError});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        status!,
        style: TextStyle(
          color: isError ? AppColors.destructive : AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }
}
