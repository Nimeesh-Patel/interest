import 'package:flutter/material.dart';

import '../features/books/screens/hardcover_screen.dart';
import '../features/readwise/screens/readwise_screen.dart';
import '../features/rss/screens/rss_screen.dart';
import '../shared/constants/app_theme.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

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
              label: 'Hardcover',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _HardcoverPage()),
              ),
            ),
            _SourceRow(
              icon: Icons.rss_feed,
              label: 'Articles',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RssScreen()),
              ),
            ),
            _SourceRow(
              icon: Icons.bookmark_outline,
              label: 'Readwise',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReadwiseScreen()),
              ),
            ),
            const _SourceRow(
              icon: Icons.link,
              label: 'Bookmarks',
              subtitle: 'via share sheet',
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SourceRow({
    required this.icon,
    required this.label,
    this.subtitle,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: tappable ? AppColors.textSecondary : AppColors.textTertiary, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      color: tappable ? AppColors.textPrimary : AppColors.textTertiary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (tappable)
              const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
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
