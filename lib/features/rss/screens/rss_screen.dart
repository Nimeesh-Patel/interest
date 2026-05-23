import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/rss_feed.dart';
import '../services/rss_feed_storage_service.dart';
import '../services/rss_ingestion_service.dart';

class RssScreen extends StatefulWidget {
  const RssScreen({super.key});

  @override
  State<RssScreen> createState() => _RssScreenState();
}

class _RssScreenState extends State<RssScreen> {
  String? _vaultPath;
  List<RssFeed> _feeds = [];
  // Maps feed id → whether that feed is currently syncing.
  final Map<String, bool> _syncing = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted) return;
    setState(() => _vaultPath = vaultPath);
    if (vaultPath != null) _loadFeeds(vaultPath);
  }

  Future<void> _loadFeeds(String vaultPath) async {
    final feeds = await RssFeedStorageService.loadFeeds(vaultPath);
    if (mounted) setState(() => _feeds = feeds);
  }

  Future<void> _syncFeed(RssFeed feed) async {
    final vaultPath = _vaultPath;
    if (vaultPath == null) {
      _showSnack('No vault configured.');
      return;
    }
    setState(() => _syncing[feed.id] = true);
    final result = await RssIngestionService.ingestFeed(feed, vaultPath);
    if (!mounted) return;
    setState(() => _syncing[feed.id] = false);
    _showSnack(result.summary);
  }

  Future<void> _deleteFeed(RssFeed feed) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove feed',
      message: 'Remove "${feed.name}"? Imported content is not deleted.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    final vaultPath = _vaultPath;
    if (vaultPath == null) return;
    await RssFeedStorageService.removeFeed(vaultPath, feed.id);
    _loadFeeds(vaultPath);
  }

  void _showAddSheet() => _showFeedSheet(null);

  void _showEditSheet(RssFeed feed) => _showFeedSheet(feed);

  void _showFeedSheet(RssFeed? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    RssFeedType selectedType = existing?.type ?? RssFeedType.generic;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: kScreenHPad,
              right: kScreenHPad,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SizedBox(
              height: screenHeight * 0.55,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Add RSS Feed' : 'Edit Feed',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'My Feed',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'RSS URL',
                      hintText: 'https://example.com/feed',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RssFeedType>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: RssFeedType.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ))
                        .toList(),
                    onChanged: (t) {
                      if (t != null) setSheetState(() => selectedType = t);
                    },
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            final url = urlCtrl.text.trim();
                            if (name.isEmpty || url.isEmpty) return;
                            Navigator.pop(ctx);
                            final vp = _vaultPath;
                            if (vp == null) return;
                            if (existing == null) {
                              await RssFeedStorageService.addFeed(vp, RssFeed(
                                id: RssFeedStorageService.generateId(name),
                                name: name,
                                url: url,
                                type: selectedType,
                              ));
                            } else {
                              await RssFeedStorageService.updateFeed(vp, RssFeed(
                                id: existing.id,
                                name: name,
                                url: url,
                                type: selectedType,
                              ));
                            }
                            _loadFeeds(vp);
                          },
                          child: Text(existing == null ? 'Add' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RSS Feeds'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        child: _feeds.isEmpty
            ? const EmptyState(
                message:
                    'No RSS feeds configured.\nTap + to add a feed and import content into the vault.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(
                    bottom: kFabListBottomPad, top: 8),
                itemCount: _feeds.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final feed = _feeds[i];
                  final isSyncing = _syncing[feed.id] ?? false;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: kScreenHPad, vertical: 4),
                    leading: _TypeChip(type: feed.type),
                    title: Text(feed.name),
                    subtitle: Text(
                      feed.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.sync),
                            tooltip: 'Sync now',
                            onPressed: () => _syncFeed(feed),
                          ),
                    onTap: () => _showEditSheet(feed),
                    onLongPress: () => _deleteFeed(feed),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        tooltip: 'Add feed',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final RssFeedType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      RssFeedType.letterboxd => Colors.orange,
      RssFeedType.substack => Colors.teal,
      RssFeedType.generic => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type.label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
