import 'package:flutter/material.dart';

import '../services/anki_connect_service.dart';
import '../services/letterboxd_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Letterboxd
  final _urlController = TextEditingController();
  bool _isSyncing = false;
  String? _syncResult;
  bool _hasError = false;

  // AnkiConnect
  final _ankiUrlController = TextEditingController();
  bool _ankiTesting = false;
  String? _ankiStatus;
  bool _ankiStatusOk = false;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
    _loadAnkiUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _ankiUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUrl() async {
    final url = await LetterboxdService.getRssUrl();
    if (mounted) setState(() => _urlController.text = url ?? '');
  }

  Future<void> _loadAnkiUrl() async {
    final url = await AnkiConnectService.getUrl();
    if (mounted) setState(() => _ankiUrlController.text = url);
  }

  Future<void> _sync() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _syncResult = 'Enter a Letterboxd RSS URL first.';
        _hasError = true;
      });
      return;
    }

    await LetterboxdService.setRssUrl(url);
    setState(() {
      _isSyncing = true;
      _syncResult = null;
      _hasError = false;
    });

    final result = await LetterboxdService.fetchAndImport(url);

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _hasError = result.error != null;
        _syncResult = result.error != null
            ? 'Error: ${result.error}'
            : '${result.created} created, ${result.updated} updated, ${result.skipped} skipped';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Letterboxd ──────────────────────────────────────────────────
          const Text(
            'Letterboxd',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Import watched films from a Letterboxd RSS feed into the vault as Markdown movie entities.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'RSS URL',
              hintText: 'https://letterboxd.com/<username>/rss/',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _sync(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _isSyncing ? null : _sync,
              child: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sync Now'),
            ),
          ),
          if (_syncResult != null) ...[
            const SizedBox(height: 12),
            Text(
              _syncResult!,
              style: TextStyle(
                color: _hasError ? Colors.red.shade700 : Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ],

          // ── Anki ────────────────────────────────────────────────────────
          const SizedBox(height: 32),
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
        ],
      ),
    );
  }
}
