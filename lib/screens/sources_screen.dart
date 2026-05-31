import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/books/screens/hardcover_screen.dart';
import '../features/readwise/screens/readwise_screen.dart';
import '../features/rss/screens/rss_screen.dart';
import '../shared/constants/app_text_styles.dart';
import '../shared/constants/app_theme.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

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
              onTap: () => _openObsidian(context),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openObsidian(BuildContext context) async {
    final launched = await launchUrl(
      Uri.parse('obsidian://'),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obsidian is not installed')),
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
