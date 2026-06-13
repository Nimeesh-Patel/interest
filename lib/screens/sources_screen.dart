import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/integrations_config_service.dart';
import '../core/vault_service.dart';
import '../shared/utils/obsidian_launcher.dart';

import '../features/books/screens/hardcover_screen.dart';
import '../features/readwise/screens/readwise_screen.dart';
import '../features/resurface/services/anki_connect_transport.dart';
import '../features/resurface/services/anki_sync_controller.dart';
import '../features/resurface/services/anki_sync_runner.dart';
import '../features/resurface/services/anki_transport.dart';
import '../features/rss/screens/rss_screen.dart';
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
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          _SyncAllButton(onTap: () => _syncAll(context)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            _SourceRow(
              icon: Icons.auto_stories,
              name: 'Hardcover',
              description: 'Sync your reading list',
              meta: 'Books & highlights',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _HardcoverPage()),
              ),
            ),
            _SourceRow(
              icon: Icons.rss_feed,
              name: 'Articles',
              description: 'RSS feeds and articles',
              meta: 'Feed reader',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RssScreen()),
              ),
            ),
            _SourceRow(
              icon: Icons.bookmark_outline,
              name: 'Readwise',
              description: 'Highlights from your reading',
              meta: 'Highlight importer',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReadwiseScreen()),
              ),
            ),
            const _SourceRow(
              icon: Icons.link,
              name: 'Bookmarks',
              description: 'via share sheet',
              meta: 'X / Twitter links',
              onTap: null,
            ),
            _SourceRow(
              icon: Icons.folder_open,
              name: 'Obsidian',
              description: 'Open to sync vault',
              meta: 'external app',
              onTap: () => launchObsidianApp(context),
            ),
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

  static void _syncAll(BuildContext context) {
    showSnack(context, 'Open each source to trigger sync.',
        duration: const Duration(seconds: 2));
  }
}

class _SyncAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SyncAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Text('Sync all',
                    style: AppTextStyles.meta
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
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
