import '../models/rss_entry.dart';
import '../models/rss_import_result.dart';

abstract class RssAdapter {
  Future<ImportResult> ingest(List<RssEntry> entries, String vaultPath);
}
