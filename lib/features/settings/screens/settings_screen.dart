import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../anki/services/anki_connect_service.dart';
import '../../books/services/hardcover_service.dart';
import '../../readera/services/readera_ingestion_service.dart';
import '../../readwise/screens/readwise_screen.dart';
import '../../readwise/services/readwise_service.dart';
import '../../rss/screens/rss_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _vaultPath;

  // AnkiConnect
  final _ankiUrlController = TextEditingController();
  bool _ankiTesting = false;
  String? _ankiStatus;
  bool _ankiStatusOk = false;

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

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _ankiUrlController.dispose();
    _readwiseTokenController.dispose();
    _hardcoverTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadAnkiUrl();
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted || vaultPath == null) return;
    setState(() => _vaultPath = vaultPath);
    final readwiseToken = await ReadwiseService.getToken(vaultPath);
    if (mounted) setState(() => _readwiseTokenController.text = readwiseToken ?? '');
    final hardcoverToken = await HardcoverService.getToken(vaultPath);
    if (mounted) setState(() => _hardcoverTokenController.text = hardcoverToken ?? '');
  }

  Future<void> _loadAnkiUrl() async {
    final url = await AnkiConnectService.getUrl();
    if (mounted) setState(() => _ankiUrlController.text = url);
  }

  Future<void> _saveAnkiUrl() async {
    await AnkiConnectService.setUrl(_ankiUrlController.text.trim());
  }

  Future<void> _testAnkiConnection() async {
    await _saveAnkiUrl();
    setState(() {
      _ankiTesting = true;
      _ankiStatus = null;
    });
    final ok = await AnkiConnectService.testConnection();
    if (mounted) {
      setState(() {
        _ankiTesting = false;
        _ankiStatusOk = ok;
        _ankiStatus = ok ? 'Connected' : 'Failed — check URL and that Anki is open';
      });
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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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

            // ── Anki ────────────────────────────────────────────────────────
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Anki',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Connect to AnkiConnect to sync Markdown cards with Anki. '
              'Anki must be open on the same network. '
              'Enter the desktop IP address (e.g. http://192.168.1.5:8765).',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ankiUrlController,
              decoration: const InputDecoration(
                labelText: 'AnkiConnect URL',
                hintText: 'http://192.168.1.x:8765',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _ankiStatus = null),
              onSubmitted: (_) => _testAnkiConnection(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _ankiTesting ? null : _testAnkiConnection,
                child: _ankiTesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Test Connection'),
              ),
            ),
            if (_ankiStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _ankiStatus!,
                style: TextStyle(
                  color: _ankiStatusOk
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontSize: 13,
                ),
              ),
            ],

            // ── Readwise ─────────────────────────────────────────────────────
            const SizedBox(height: 32),
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
              style: TextStyle(color: Colors.grey, fontSize: 13),
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
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
              style: TextStyle(color: Colors.grey, fontSize: 13),
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
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
                      : Colors.red.shade700,
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
              style: TextStyle(color: Colors.grey, fontSize: 13),
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
                      ? Colors.red.shade700
                      : Colors.grey.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
