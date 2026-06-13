import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/book_note.dart';
import '../models/hardcover_sync_result.dart';
import 'book_note_storage.dart';
import 'hardcover_service.dart';

/// One-way pull: Hardcover library → book-note entities (`collection: Books`).
/// Each Hardcover book becomes an ordinary vault-root note; re-syncs patch only
/// Hardcover-owned frontmatter (status, rating, hardcover_id) and never touch
/// the body. Dedup is by `hardcover_id`, falling back to a title-slug match so
/// a manually created book note can be linked.
class HardcoverSyncService {
  static Future<HardcoverSyncResult> sync() async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) {
        return const HardcoverSyncResult(error: 'No vault path set.');
      }
      final token = await HardcoverService.getToken(vaultPath);
      if (token == null || token.isEmpty) {
        return const HardcoverSyncResult(
            error: 'No Hardcover token. Configure in Settings.');
      }

      final (hcBooks, fetchError) = await HardcoverService.fetchUserBooks(token);
      if (hcBooks == null) {
        return HardcoverSyncResult(
            error: fetchError ??
                'Could not reach Hardcover API. Check token in Settings.');
      }

      final local = await BookNoteStorage.loadBooks(vaultPath);
      final byHcId = <int, BookNote>{
        for (final b in local.where((b) => b.hardcoverId != null))
          b.hardcoverId!: b
      };
      final bySlug = <String, BookNote>{
        for (final b in local) slugify(b.title): b
      };

      int imported = 0;
      int updated = 0;
      int linked = 0;

      for (final hc in hcBooks) {
        try {
          final existing = byHcId[hc.bookId] ?? bySlug[slugify(hc.title)];
          if (existing == null) {
            await BookNoteStorage.createBookNote(
              vaultPath,
              title: hc.title,
              authors: hc.authors,
              hardcoverId: hc.bookId,
              status: hc.statusSlug,
              rating: hc.rating,
            );
            imported++;
          } else {
            final wasLinked = existing.hardcoverId == null;
            await BookNoteStorage.patchFields(
              existing.filePath,
              hardcoverId: hc.bookId,
              status: hc.statusSlug,
              rating: hc.rating,
            );
            if (wasLinked) {
              linked++;
            } else {
              updated++;
            }
          }
        } catch (_) {
          continue;
        }
      }

      return HardcoverSyncResult(
        importedFromHardcover: imported,
        updatedFromHardcover: updated,
        linkedToHardcover: linked,
      );
    } catch (e) {
      return HardcoverSyncResult(error: e.toString());
    }
  }
}
