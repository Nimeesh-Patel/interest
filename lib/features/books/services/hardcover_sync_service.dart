import '../../../core/vault_service.dart';
import '../models/book.dart';
import '../models/hardcover_book.dart';
import '../models/hardcover_sync_result.dart';
import 'book_storage_service.dart';
import 'hardcover_service.dart';

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

      // 1. Fetch from Hardcover
      final (hcBooks, fetchError) = await HardcoverService.fetchUserBooks(token);
      if (hcBooks == null) {
        return HardcoverSyncResult(
            error: fetchError ?? 'Could not reach Hardcover API. Check token in Settings.');
      }

      // 2. Load local books
      final localBooks = await BookStorageService.loadBooks(vaultPath);

      // 3. Build local lookup by hardcover_id for fast access
      final localByHcId = <int, Book>{
        for (final b in localBooks.where((b) => b.hardcoverId != null))
          b.hardcoverId!: b
      };

      int importedFromHardcover = 0;
      int updatedFromHardcover = 0;
      int pushedToHardcover = 0;
      int linkedToHardcover = 0;
      int skipped = 0;

      // ── Pass 1: Hardcover → Markdown ────────────────────────────────────
      for (final hc in hcBooks) {
        try {
          Book? local = localByHcId[hc.bookId];

          // Not found by hardcover_id — try ISBN / title reconciliation
          local ??= await BookStorageService.reconcile(
            vaultPath,
            title: hc.title,
          );

          if (local == null) {
            // New book: create canonical file
            final existingAliases =
                localBooks.map((b) => b.alias).toSet();
            final alias = BookStorageService.generateAlias(
              hc.title,
              hc.authors,
              existing: existingAliases,
            );
            final book = Book(
              alias: alias,
              title: hc.title,
              authors: hc.authors,
              hardcoverId: hc.bookId,
              status: hc.statusSlug,
              rating: hc.rating,
              startedAt: hc.firstStartedReadingDate,
              finishedAt: hc.lastReadDate,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
            await BookStorageService.createBook(vaultPath, book);
            importedFromHardcover++;
          } else {
            // Patch Hardcover-owned fields only
            final wasLinked = local.hardcoverId == null;
            final patches = <String, dynamic>{
              'hardcover_id': hc.bookId,
              'status': hc.statusSlug,
              if (hc.rating != null) 'rating': hc.rating,
              if (hc.firstStartedReadingDate != null)
                'started_at': hc.firstStartedReadingDate,
              if (hc.lastReadDate != null) 'finished_at': hc.lastReadDate,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            };
            await BookStorageService.patchFields(local.filePath!, patches);
            if (wasLinked) {
              linkedToHardcover++;
            } else {
              updatedFromHardcover++;
            }
          }
        } catch (_) {
          continue;
        }
      }

      // ── Pass 2: Markdown → Hardcover ────────────────────────────────────
      // Reload to pick up hardcover_ids written in pass 1
      final updatedLocalBooks = await BookStorageService.loadBooks(vaultPath);
      final hcByBookId = <int, HardcoverBook>{
        for (final hc in hcBooks) hc.bookId: hc
      };

      for (final local in updatedLocalBooks
          .where((b) => b.hardcoverId != null && b.filePath != null)) {
        try {
          final hc = hcByBookId[local.hardcoverId];
          if (hc == null) continue;

          final localStatusId = _statusToId(local.status);
          final statusChanged =
              localStatusId != null && localStatusId != hc.statusId;
          final ratingChanged =
              local.rating != null && local.rating != hc.rating;

          if (!statusChanged && !ratingChanged) {
            skipped++;
            continue;
          }

          final ok = await HardcoverService.updateUserBook(
            token,
            hc.userBookId,
            statusId: localStatusId ?? hc.statusId,
            rating: local.rating,
          );
          if (ok) pushedToHardcover++;
        } catch (_) {
          continue;
        }
      }

      return HardcoverSyncResult(
        importedFromHardcover: importedFromHardcover,
        updatedFromHardcover: updatedFromHardcover,
        pushedToHardcover: pushedToHardcover,
        linkedToHardcover: linkedToHardcover,
        skipped: skipped,
      );
    } catch (e) {
      return HardcoverSyncResult(error: e.toString());
    }
  }

  static int? _statusToId(String? status) => const {
        'want_to_read': 1,
        'reading': 2,
        'read': 3,
        'paused': 4,
        'dnf': 5,
      }[status];
}
