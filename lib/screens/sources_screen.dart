import 'package:flutter/material.dart';

import '../shared/utils/obsidian_launcher.dart';

import '../features/books/screens/hardcover_screen.dart';
import '../features/readwise/screens/readwise_screen.dart';
import '../features/resurface/services/ankidroid_service.dart';
import '../features/resurface/services/ankidroid_sync_controller.dart';
import '../features/rss/screens/rss_screen.dart';
import '../shared/constants/app_text_styles.dart';
import '../shared/constants/app_theme.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  bool _syncingAnki = false;

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
            _AnkiDroidRow(
              syncing: _syncingAnki,
              onTap: _syncAnkiDroid,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncAnkiDroid() async {
    if (_syncingAnki) return;

    final available = await AnkiDroidService.isAvailable();
    if (!mounted) return;
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AnkiDroid not installed')),
      );
      return;
    }

    final granted = await AnkiDroidService.requestPermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission denied')),
      );
      return;
    }

    setState(() => _syncingAnki = true);

    final result = await AnkiDroidSyncController.sync();

    if (!mounted) return;
    setState(() => _syncingAnki = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vault configured')),
      );
      return;
    }

    final total = result.added + result.updated;

    if (result.failed > 0 && result.errors.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${result.failed} note${result.failed == 1 ? '' : 's'} failed'),
          content: SingleChildScrollView(
            child: Text(result.errors.join('\n\n'),
                style: AppTextStyles.bodySmall),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      final msg = result.failed == 0
          ? 'Synced $total problem notes to AnkiDroid (${result.added} added, ${result.updated} updated)'
          : '${result.failed} notes failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
    }
  }

  static void _syncAll(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Open each source to trigger sync.'),
        duration: Duration(seconds: 2),
      ),
    );
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

  const _SourceRow({
    required this.icon,
    required this.name,
    required this.description,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            if (tappable)
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _AnkiDroidRow extends StatelessWidget {
  final bool syncing;
  final VoidCallback onTap;

  const _AnkiDroidRow({required this.syncing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: syncing ? null : onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.style,
                size: 22,
                color: syncing
                    ? AppColors.textTertiary
                    : AppColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AnkiDroid',
                    style: AppTextStyles.entityName.copyWith(
                      color: syncing
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          syncing
                              ? 'Syncing problem notes…'
                              : 'Push problem notes to AnkiDroid',
                          style: AppTextStyles.bodySmall,
                        ),
                      ),
                      Text('Flashcard sync',
                          style: AppTextStyles.metaMuted),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (syncing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppColors.textTertiary),
          ],
        ),
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
