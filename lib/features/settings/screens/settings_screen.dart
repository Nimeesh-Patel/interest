import 'package:flutter/material.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../hardcover/services/hardcover_service.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/busy_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _vaultPath;

  // Hardcover
  final _hardcoverTokenController = TextEditingController();
  bool _hardcoverSaving = false;
  String? _hardcoverSaveStatus;
  bool _hardcoverTesting = false;
  String? _hardcoverTestStatus;
  bool _hardcoverTestOk = false;

  // Anki scan scope
  final _excludedController = TextEditingController();
  bool _excludedSaving = false;
  String? _excludedSaveStatus;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _hardcoverTokenController.dispose();
    _excludedController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted || vaultPath == null) return;
    setState(() => _vaultPath = vaultPath);
    final hardcoverToken = await HardcoverService.getToken(vaultPath);
    if (mounted) {
      setState(() => _hardcoverTokenController.text = hardcoverToken ?? '');
    }
    final config = await IntegrationsConfigService.load(vaultPath);
    if (mounted) {
      setState(() =>
          _excludedController.text = config.resurfaceExcludedFolders.join(', '));
    }
  }

  Future<void> _saveExcluded() async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    final folders = _excludedController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      _excludedSaving = true;
      _excludedSaveStatus = null;
    });
    await IntegrationsConfigService.setResurfaceExcludedFolders(
        vaultPath, folders);
    if (mounted) {
      setState(() {
        _excludedSaving = false;
        _excludedSaveStatus = 'Saved.';
      });
    }
  }

  Future<void> _saveHardcoverToken() async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    final token = _hardcoverTokenController.text.trim();
    setState(() {
      _hardcoverSaving = true;
      _hardcoverSaveStatus = null;
    });
    await HardcoverService.setToken(vaultPath, token);
    if (mounted) {
      setState(() {
        _hardcoverSaving = false;
        _hardcoverSaveStatus = token.isEmpty ? 'Token cleared.' : 'Token saved.';
      });
    }
  }

  Future<void> _testHardcoverConnection() async {
    await _saveHardcoverToken();
    setState(() {
      _hardcoverTesting = true;
      _hardcoverTestStatus = null;
    });
    final token = _hardcoverTokenController.text.trim();
    final error = await HardcoverService.testConnection(token);
    if (mounted) {
      setState(() {
        _hardcoverTesting = false;
        _hardcoverTestOk = error == null;
        _hardcoverTestStatus = error == null ? 'Connected' : 'Failed — $error';
      });
    }
  }

  InputDecoration _tokenDecoration(String label, String hint) =>
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
            // ── Hardcover ────────────────────────────────────────────────────
            const _SettingsSection(
              title: 'Hardcover',
              description:
                  'Import your Hardcover reading library into the Books '
                  'collection. Find your API token at hardcover.app/account/api. '
                  'Token expires annually on January 1st.',
            ),
            TextField(
              controller: _hardcoverTokenController,
              obscureText: true,
              decoration: _tokenDecoration(
                  'API Token', 'Paste your Hardcover API token'),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveHardcoverToken(),
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Save Token',
              busy: _hardcoverSaving,
              onPressed: _saveHardcoverToken,
            ),
            _StatusLine(_hardcoverSaveStatus),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Test Connection',
              busy: _hardcoverTesting,
              onPressed: _testHardcoverConnection,
            ),
            _StatusLine(
              _hardcoverTestStatus,
              color: _hardcoverTestOk
                  ? Colors.green.shade700
                  : AppColors.destructive,
            ),

            // ── Anki sync scope ──────────────────────────────────────────────
            const _SettingsSection(
              title: 'Anki sync',
              description:
                  'Folders the Anki sync skips when scanning the vault for '
                  '*** problem notes (comma-separated).',
            ),
            TextField(
              controller: _excludedController,
              decoration: _tokenDecoration('Excluded folders',
                  'Interesting, .obsidian, Templates, Attachments'),
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
            _StatusLine(_excludedSaveStatus),
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
  final Color color;

  const _StatusLine(this.status, {this.color = AppColors.textSecondary});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(status!, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}
