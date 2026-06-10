import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../books/services/hardcover_service.dart';
import '../../readera/services/readera_ingestion_service.dart';
import '../../readwise/screens/readwise_screen.dart';
import '../../readwise/services/readwise_service.dart';
import '../../rss/screens/rss_screen.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/busy_button.dart';
import '../../resurface/services/traversal_log_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _vaultPath;

  // Readwise
  final _readwiseTokenController = TextEditingController();
  bool _readwiseSaving = false;
  String? _readwiseSaveStatus;

  // Hardcover
  final _hardcoverTokenController = TextEditingController();
  bool _hardcoverSaving = false;
  String? _hardcoverSaveStatus;
  bool _hardcoverTesting = false;
  String? _hardcoverTestStatus;
  bool _hardcoverTestOk = false;

  // ReadEra
  bool _readeraImporting = false;
  String? _readeraStatus;

  // Resurface
  final _resurfaceExcludedController = TextEditingController();
  bool _resurfaceSaving = false;
  String? _resurfaceSaveStatus;
  int _minDegree = 2;
  int _maxDegree = 3;
  bool _degreeSaving = false;
  String? _degreeSaveStatus;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _readwiseTokenController.dispose();
    _hardcoverTokenController.dispose();
    _resurfaceExcludedController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted || vaultPath == null) return;
    setState(() => _vaultPath = vaultPath);
    final readwiseToken = await ReadwiseService.getToken(vaultPath);
    if (mounted) setState(() => _readwiseTokenController.text = readwiseToken ?? '');
    final hardcoverToken = await HardcoverService.getToken(vaultPath);
    if (mounted) setState(() => _hardcoverTokenController.text = hardcoverToken ?? '');
    final config = await IntegrationsConfigService.load(vaultPath);
    if (mounted) {
      setState(() => _resurfaceExcludedController.text =
          config.resurfaceExcludedFolders.join(', '));
    }
    final degreeSettings = await TraversalLogService.loadSettings();
    if (mounted) {
      setState(() {
        _minDegree = degreeSettings.minDegree;
        _maxDegree = degreeSettings.maxDegree;
      });
    }
  }

  Future<void> _saveResurfaceExcluded() async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    final folders = _resurfaceExcludedController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() { _resurfaceSaving = true; _resurfaceSaveStatus = null; });
    await IntegrationsConfigService.setResurfaceExcludedFolders(vaultPath, folders);
    if (mounted) {
      setState(() { _resurfaceSaving = false; _resurfaceSaveStatus = 'Saved.'; });
    }
  }

  Future<void> _saveDegreeSettings() async {
    setState(() { _degreeSaving = true; _degreeSaveStatus = null; });
    await TraversalLogService.saveSettings(
      minDegree: _minDegree,
      maxDegree: _maxDegree,
    );
    if (mounted) {
      setState(() { _degreeSaving = false; _degreeSaveStatus = 'Saved.'; });
    }
  }

  Future<void> _saveReadwiseToken() async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    final token = _readwiseTokenController.text.trim();
    setState(() {
      _readwiseSaving = true;
      _readwiseSaveStatus = null;
    });
    await ReadwiseService.setToken(vaultPath, token);
    if (mounted) {
      setState(() {
        _readwiseSaving = false;
        _readwiseSaveStatus = token.isEmpty ? 'Token cleared.' : 'Token saved.';
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
        _hardcoverTestStatus =
            error == null ? 'Connected' : 'Failed — $error';
      });
    }
  }

  Future<void> _importReadera() async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bak'],
    );
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    setState(() {
      _readeraImporting = true;
      _readeraStatus = null;
    });
    final importResult = await ReaderaIngestionService.ingest(
        result.files.single.path!, vaultPath);
    if (!mounted) return;
    setState(() {
      _readeraImporting = false;
      _readeraStatus = importResult.error != null
          ? 'Error: ${importResult.error}'
          : importResult.summary;
    });
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
            // ── RSS Feeds ────────────────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.rss_feed),
              title: const Text('RSS Feeds'),
              subtitle: const Text(
                'Import content from Letterboxd, Substack, blogs, and other RSS sources.',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RssScreen()),
              ),
            ),

            // ── Readwise ─────────────────────────────────────────────────────
            const _SettingsSection(
              title: 'Readwise',
              description:
                  'Import book highlights from Readwise into the vault as Markdown files. '
                  'Find your access token at readwise.io/access_token.',
            ),
            TextField(
              controller: _readwiseTokenController,
              obscureText: true,
              decoration: _tokenDecoration(
                  'Access Token', 'Paste your Readwise access token'),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveReadwiseToken(),
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Save Token',
              busy: _readwiseSaving,
              onPressed: _saveReadwiseToken,
            ),
            _StatusLine(_readwiseSaveStatus),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.book_outlined),
              label: const Text('Open Import Screen'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReadwiseScreen()),
              ),
            ),

            // ── Hardcover ────────────────────────────────────────────────────
            const _SettingsSection(
              title: 'Hardcover',
              description:
                  'Sync your Hardcover reading library with the vault. '
                  'Find your API token at hardcover.app/account/api. '
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

            // ── ReadEra ──────────────────────────────────────────────────────
            const _SettingsSection(
              title: 'ReadEra',
              description:
                  'Import highlights from a ReadEra .bak backup file into your '
                  'Books vault. Highlights are merged into existing book files '
                  'without overwriting Readwise or Hardcover data.',
            ),
            BusyButton(
              label: 'Import from .bak',
              busy: _readeraImporting,
              onPressed: _importReadera,
            ),
            _StatusLine(
              _readeraStatus,
              color: (_readeraStatus?.startsWith('Error') ?? false)
                  ? AppColors.destructive
                  : AppColors.textSecondary,
            ),

            // ── Resurface ────────────────────────────────────────────────────
            const _SettingsSection(
              title: 'Resurface',
              description:
                  'Vault-wide semantic resurfacing viewer. '
                  'Scans notes for *** separators and surfaces them as front/back pairs. '
                  'Enter folder names to exclude (comma-separated).',
            ),
            TextField(
              controller: _resurfaceExcludedController,
              decoration: _tokenDecoration('Excluded folders',
                  'Interesting, .obsidian, Templates, Attachments'),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveResurfaceExcluded(),
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Save',
              busy: _resurfaceSaving,
              onPressed: _saveResurfaceExcluded,
            ),
            _StatusLine(_resurfaceSaveStatus),

            // ── Graph neighbour range ─────────────────────────────────────
            const SizedBox(height: 24),
            const Text(
              'Graph neighbour range',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              'Min/max hop distance for activating related notes into the review queue.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _DegreeStepper(
              label: 'Min degree',
              value: _minDegree,
              canDecrement: _minDegree > 1,
              canIncrement: _minDegree < 5 && _minDegree < _maxDegree,
              onDecrement: () => setState(() {
                _minDegree--;
                if (_maxDegree < _minDegree) _maxDegree = _minDegree;
              }),
              onIncrement: () => setState(() => _minDegree++),
            ),
            _DegreeStepper(
              label: 'Max degree',
              value: _maxDegree,
              canDecrement: _maxDegree > _minDegree,
              canIncrement: _maxDegree < 5,
              onDecrement: () => setState(() => _maxDegree--),
              onIncrement: () => setState(() => _maxDegree++),
            ),
            const SizedBox(height: 8),
            BusyButton(
              label: 'Save',
              busy: _degreeSaving,
              onPressed: _saveDegreeSettings,
            ),
            _StatusLine(_degreeSaveStatus),
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

/// Labelled −/+ integer stepper row for the graph degree settings.
class _DegreeStepper extends StatelessWidget {
  final String label;
  final int value;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _DegreeStepper({
    required this.label,
    required this.value,
    required this.canDecrement,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          onPressed: canDecrement ? onDecrement : null,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          onPressed: canIncrement ? onIncrement : null,
        ),
      ],
    );
  }
}
