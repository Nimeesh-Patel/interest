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
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Readwise',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Import book highlights from Readwise into the vault as Markdown files. '
              'Find your access token at readwise.io/access_token.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _readwiseTokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Access Token',
                hintText: 'Paste your Readwise access token',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveReadwiseToken(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _readwiseSaving ? null : _saveReadwiseToken,
                child: _readwiseSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Token'),
              ),
            ),
            if (_readwiseSaveStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _readwiseSaveStatus!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
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
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Hardcover',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sync your Hardcover reading library with the vault. '
              'Find your API token at hardcover.app/account/api. '
              'Token expires annually on January 1st.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hardcoverTokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Token',
                hintText: 'Paste your Hardcover API token',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveHardcoverToken(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _hardcoverSaving ? null : _saveHardcoverToken,
                child: _hardcoverSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Token'),
              ),
            ),
            if (_hardcoverSaveStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _hardcoverSaveStatus!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _hardcoverTesting ? null : _testHardcoverConnection,
                child: _hardcoverTesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Test Connection'),
              ),
            ),
            if (_hardcoverTestStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _hardcoverTestStatus!,
                style: TextStyle(
                  color: _hardcoverTestOk
                      ? Colors.green.shade700
                      : AppColors.destructive,
                  fontSize: 13,
                ),
              ),
            ],

            // ── ReadEra ──────────────────────────────────────────────────────
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'ReadEra',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Import highlights from a ReadEra .bak backup file into your '
              'Books vault. Highlights are merged into existing book files '
              'without overwriting Readwise or Hardcover data.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _readeraImporting ? null : _importReadera,
                child: _readeraImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import from .bak'),
              ),
            ),
            if (_readeraStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _readeraStatus!,
                style: TextStyle(
                  color: (_readeraStatus!.startsWith('Error'))
                      ? AppColors.destructive
                      : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],

            // ── Resurface ────────────────────────────────────────────────────
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Resurface',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Vault-wide semantic resurfacing viewer. '
              'Scans notes for *** separators and surfaces them as front/back pairs. '
              'Enter folder names to exclude (comma-separated).',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _resurfaceExcludedController,
              decoration: const InputDecoration(
                labelText: 'Excluded folders',
                hintText: 'Interesting, .obsidian, Templates, Attachments',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveResurfaceExcluded(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _resurfaceSaving ? null : _saveResurfaceExcluded,
                child: _resurfaceSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
            if (_resurfaceSaveStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _resurfaceSaveStatus!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],

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
            Row(
              children: [
                const SizedBox(width: 8),
                const Text('Min degree', style: TextStyle(fontSize: 14)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: _minDegree > 1
                      ? () => setState(() {
                            _minDegree--;
                            if (_maxDegree < _minDegree) _maxDegree = _minDegree;
                          })
                      : null,
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$_minDegree',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _minDegree < 5 && _minDegree < _maxDegree
                      ? () => setState(() => _minDegree++)
                      : null,
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 8),
                const Text('Max degree', style: TextStyle(fontSize: 14)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: _maxDegree > _minDegree
                      ? () => setState(() => _maxDegree--)
                      : null,
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$_maxDegree',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _maxDegree < 5
                      ? () => setState(() => _maxDegree++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _degreeSaving ? null : _saveDegreeSettings,
                child: _degreeSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
            if (_degreeSaveStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _degreeSaveStatus!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
