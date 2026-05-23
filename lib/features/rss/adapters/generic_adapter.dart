import '../models/rss_entry.dart';
import '../models/rss_import_result.dart';
import 'rss_adapter.dart';
import 'substack_adapter.dart';

// Generic RSS feeds use the same article projection as Substack.
// Exists as a distinct type for explicit semantic classification and future divergence.
class GenericAdapter implements RssAdapter {
  final String feedId;

  const GenericAdapter({required this.feedId});

  @override
  Future<ImportResult> ingest(List<RssEntry> entries, String vaultPath) =>
      SubstackAdapter(feedId: feedId).ingest(entries, vaultPath);
}
