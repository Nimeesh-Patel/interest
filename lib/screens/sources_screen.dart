import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/integrations_config_service.dart';
import '../core/vault_service.dart';
import '../shared/utils/obsidian_launcher.dart';

import '../features/hardcover/screens/hardcover_screen.dart';
import '../features/anki/services/anki_connect_transport.dart';
import '../features/anki/services/anki_sync_controller.dart';
import '../features/anki/services/anki_sync_runner.dart';
import '../features/anki/services/anki_transport.dart';
import '../shared/constants/app_text_styles.dart';
import '../shared/constants/app_theme.dart';
import '../shared/widgets/list_row.dart';
import '../shared/widgets/progress.dart';
import '../shared/widgets/snack.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  // One flag per Anki row, but the two syncs are mutually exclusive: both
  // write anki_note_id back to the same vault files.
  bool _syncingAnkiDroid = false;
  bool _syncingAnkiConnect = false;

  bool get _ankiBusy => _syncingAnkiDroid || _syncingAnkiConnect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            _SourceRow(
              icon: Icons.auto_stories,
              name: 'Hardcover',
              description: 'Import your reading list into Books',
              meta: 'Books',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _HardcoverPage()),
              ),
            ),
            _SourceRow(
              icon: Icons.folder_open,
              name: 'Obsidian',
              description: 'Open the vault',
              meta: 'external app',
              onTap: () => launchObsidianApp(context),
            ),
            // AnkiDroid: the interest://sync-anki deep link triggers the same
            // sync, but this row is a no-plugin manual trigger. Android only.
            if (Platform.isAndroid)
              _SourceRow(
                icon: Icons.style,
                name: 'AnkiDroid',
                description: _syncingAnkiDroid
                    ? 'Syncing problem notes…'
                    : 'Push problem notes to AnkiDroid',
                meta: 'Flashcard sync',
                busy: _syncingAnkiDroid,
                onTap: _syncAnkiDroid,
              ),
            _SourceRow(
              icon: Icons.desktop_windows,
              name: 'Anki desktop',
              description: _syncingAnkiConnect
                  ? 'Syncing problem notes…'
                  : 'Push problem notes via AnkiConnect',
              meta: 'Flashcard sync',
              busy: _syncingAnkiConnect,
              onTap: _syncAnkiConnect,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncAnkiDroid() async {
    if (_ankiBusy) return;
    await runAnkiDroidSync(context,
        onBusy: (busy) => setState(() => _syncingAnkiDroid = busy));
  }

  Future<void> _syncAnkiConnect() async {
    if (_ankiBusy) return;

    final vaultPath = await VaultService.getVaultPath();
    if (!mounted) return;
    if (vaultPath == null) {
      showSnack(context, 'No vault configured');
      return;
    }

    final config = await IntegrationsConfigService.load(vaultPath);
    final transport = AnkiConnectTransport(url: config.ankiConnectUrl);
    final available = await transport.isAvailable();
    if (!mounted) return;
    if (!available) {
      showSnack(context,
          'Anki desktop not reachable — is Anki running with AnkiConnect installed?');
      return;
    }

    final granted = await transport.requestPermission();
    if (!mounted) return;
    if (!granted) {
      showSnack(context, 'AnkiConnect denied the connection');
      return;
    }

    await _runAnkiSync(
        transport, (busy) => setState(() => _syncingAnkiConnect = busy));
  }

  Future<void> _runAnkiSync(
      AnkiTransport transport, void Function(bool) setBusy) async {
    setBusy(true);
    final result = await AnkiSyncController.sync(transport);
    if (!mounted) return;
    setBusy(false);
    showAnkiSyncResult(context, transport, result);
  }

}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final String meta;
  final VoidCallback? onTap;

  /// While true the row is dimmed, untappable, and shows a spinner trailing.
  final bool busy;

  const _SourceRow({
    required this.icon,
    required this.name,
    required this.description,
    required this.meta,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null && !busy;
    return ListRow(
      onTap: tappable ? onTap : null,
      child: Row(
        children: [
          Icon(icon,
              size: 22,
              color: tappable
                  ? AppColors.textSecondary
                  : AppColors.textTertiary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTextStyles.entityName.copyWith(
                    color: tappable
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(description,
                          style: AppTextStyles.bodySmall),
                    ),
                    Text(meta,
                        style: AppTextStyles.metaMuted),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const InlineSpinner(size: 14)
          else if (tappable)
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

// Wraps HardcoverScreen (body-only) with a full Scaffold, AppBar, and actions.
class _HardcoverPage extends StatefulWidget {
  const _HardcoverPage();

  @override
  State<_HardcoverPage> createState() => _HardcoverPageState();
}

class _HardcoverPageState extends State<_HardcoverPage> {
  final _key = GlobalKey<HardcoverScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardcover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Hardcover',
            onPressed: () => _key.currentState?.openSearchSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync with Hardcover',
            onPressed: () => _key.currentState?.sync(),
          ),
        ],
      ),
      body: HardcoverScreen(key: _key),
    );
  }
}
