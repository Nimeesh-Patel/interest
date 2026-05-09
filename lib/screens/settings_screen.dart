import 'package:flutter/material.dart';

import '../services/letterboxd_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _isSyncing = false;
  String? _syncResult;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUrl() async {
    final url = await LetterboxdService.getRssUrl();
    if (mounted) setState(() => _urlController.text = url ?? '');
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
        ],
      ),
    );
  }
}
