import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import 'task_storage_service.dart';

class InboxEnsureResult {
  final String? path;
  final String? error;

  const InboxEnsureResult._({this.path, this.error});

  const InboxEnsureResult.ready(String value) : this._(path: value);

  const InboxEnsureResult.failed(String message) : this._(error: message);
}

/// Owns the one persistent low-structure Inbox file.
class InboxStorageService {
  static final _initialBytes = utf8.encode('# Inbox\n\n');

  /// Creates an empty Inbox only when it does not already exist.
  ///
  /// Existing content is never rebuilt or migrated. Interrupted owned writes
  /// block empty creation and surface their recovery artifacts.
  static Future<InboxEnsureResult> ensureInbox(String vaultPath) async {
    final path = VaultService.inboxPath(vaultPath);
    final file = File(path);
    try {
      final probe = await TaskStorageService.probeRecovery(path);
      if (probe.status == TaskFileRecoveryProbeStatus.canonicalPresent) {
        return InboxEnsureResult.ready(path);
      }
      if (!probe.mayCreate) {
        return InboxEnsureResult.failed(
          probe.error ?? 'Inbox recovery state could not be established.',
        );
      }

      await file.parent.create(recursive: true);
      final recheck = await TaskStorageService.probeRecovery(path);
      if (recheck.status == TaskFileRecoveryProbeStatus.canonicalPresent) {
        return InboxEnsureResult.ready(path);
      }
      if (!recheck.mayCreate) {
        return InboxEnsureResult.failed(
          recheck.error ?? 'Inbox recovery state could not be established.',
        );
      }

      final markerPath = await _unusedCreationMarker(path);
      final marker = File(markerPath);
      await marker.writeAsBytes(_initialBytes, flush: true);
      if (!_bytesEqual(await marker.readAsBytes(), _initialBytes)) {
        return InboxEnsureResult.failed(
          'The Inbox creation marker could not be verified. Inspect: '
          '$path, $markerPath',
        );
      }

      await file.create(exclusive: true);
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.writeFrom(_initialBytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (!_bytesEqual(await file.readAsBytes(), _initialBytes)) {
        return const InboxEnsureResult.failed(
          'The new Inbox could not be verified. Its creation marker was '
          'retained for restart inspection.',
        );
      }
      try {
        await marker.delete();
      } catch (_) {}
      return InboxEnsureResult.ready(path);
    } catch (_) {
      return const InboxEnsureResult.failed('Inbox could not be created.');
    }
  }

  static Future<String> _unusedCreationMarker(String filePath) async {
    final directory = p.dirname(filePath);
    final name = p.basename(filePath);
    final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    for (var suffix = 0; suffix < 100; suffix++) {
      final markerPath = p.join(
        directory,
        '.$name.interest_create_${nonce}_$suffix.marker',
      );
      if (!await File(markerPath).exists()) return markerPath;
    }
    throw const FileSystemException(
      'Could not allocate an Inbox creation marker.',
    );
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
