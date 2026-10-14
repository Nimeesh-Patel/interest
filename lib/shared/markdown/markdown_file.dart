// Exact-source Markdown I/O. Callers own semantics; this layer owns byte
// preservation, stale refusal, staging, recovery observation and guarded rename.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'md_utils.dart';
import 'vault_scanner.dart';

class TaskFileSnapshot {
  final List<int> bytes;
  final List<String> lines;

  const TaskFileSnapshot({required this.bytes, required this.lines});
}

class TaskFileSnapshotResult {
  final TaskFileSnapshot? snapshot;
  final String? error;

  const TaskFileSnapshotResult._({this.snapshot, this.error});

  const TaskFileSnapshotResult.ready(TaskFileSnapshot value)
    : this._(snapshot: value);

  const TaskFileSnapshotResult.failed(String message) : this._(error: message);
}

enum TaskFileRecoveryProbeStatus {
  canonicalPresent,
  clear,
  recoverable,
  blocked,
}

class TaskFileRecoveryProbeResult {
  final TaskFileRecoveryProbeStatus status;
  final List<String> artifactPaths;
  final String? error;

  const TaskFileRecoveryProbeResult(
    this.status, {
    this.artifactPaths = const [],
    this.error,
  });

  bool get mayCreate => status == TaskFileRecoveryProbeStatus.clear;
}

class _TaskFileTransactionPaths {
  final String stagePath;
  final String backupPath;

  const _TaskFileTransactionPaths(this.stagePath, this.backupPath);
}

enum GuardedTaskMutationStatus {
  applied,
  stale,
  refused,
  unavailable,
  indeterminate,
}

enum _BackupRestoreOutcome { restored, targetPresent, failed }

class GuardedTaskMutationResult {
  final GuardedTaskMutationStatus status;
  final String message;

  const GuardedTaskMutationResult(this.status, this.message);

  bool get applied => status == GuardedTaskMutationStatus.applied;
}

/// Injectable filesystem boundary for the guarded Inbox replacement.
///
/// Production uses these direct operations. Tests can fail one operation to
/// verify that the common transaction restores the previous Inbox bytes.
class GuardedTaskFileOperations {
  const GuardedTaskFileOperations();

  Future<bool> exists(String path) => File(path).exists();

  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  Future<void> writeBytesFlushed(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> rename(String sourcePath, String targetPath) async {
    await File(sourcePath).rename(targetPath);
  }

  Future<void> delete(String path) => File(path).delete();
}

class _TaskTextDocument {
  final List<String> lines;
  final List<String> _originalLines;
  final List<String> _originalLineEndings;
  final String _defaultNewline;
  final bool _hadUtf8Bom;

  _TaskTextDocument({
    required this.lines,
    required List<String> originalLines,
    required List<String> originalLineEndings,
    required String defaultNewline,
    required bool hadUtf8Bom,
  }) : _originalLines = originalLines,
       _originalLineEndings = originalLineEndings,
       _defaultNewline = defaultNewline,
       _hadUtf8Bom = hadUtf8Bom;

  factory _TaskTextDocument.parse(String content, {required bool hadUtf8Bom}) {
    final lines = <String>[];
    final lineEndings = <String>[];
    var start = 0;
    for (final match in RegExp(r'\r\n|\r|\n').allMatches(content)) {
      lines.add(content.substring(start, match.start));
      lineEndings.add(match.group(0)!);
      start = match.end;
    }
    if (start < content.length) {
      lines.add(content.substring(start));
      lineEndings.add('');
    }
    final defaultNewline = lineEndings.firstWhere(
      (ending) => ending.isNotEmpty,
      orElse: () => '\n',
    );
    return _TaskTextDocument(
      lines: List.of(lines),
      originalLines: List.unmodifiable(lines),
      originalLineEndings: List.unmodifiable(lineEndings),
      defaultNewline: defaultNewline,
      hadUtf8Bom: hadUtf8Bom,
    );
  }

  List<int> encodeBytes() {
    final lineEndings = _lineEndingsAfterMutation();
    final buffer = StringBuffer();
    for (var index = 0; index < lines.length; index++) {
      buffer
        ..write(lines[index])
        ..write(lineEndings[index]);
    }
    final encoded = utf8.encode(buffer.toString());
    return _hadUtf8Bom ? <int>[0xef, 0xbb, 0xbf, ...encoded] : encoded;
  }

  List<String> _lineEndingsAfterMutation() {
    if (lines.isEmpty) return const [];
    if (lines.length == _originalLines.length) {
      return List.of(_originalLineEndings);
    }

    final endings = List<String>.filled(lines.length, _defaultNewline);
    var prefix = 0;
    while (prefix < lines.length &&
        prefix < _originalLines.length &&
        lines[prefix] == _originalLines[prefix]) {
      endings[prefix] = _originalLineEndings[prefix];
      prefix++;
    }

    var suffix = 0;
    while (suffix < lines.length - prefix &&
        suffix < _originalLines.length - prefix &&
        lines[lines.length - 1 - suffix] ==
            _originalLines[_originalLines.length - 1 - suffix]) {
      endings[lines.length - 1 - suffix] =
          _originalLineEndings[_originalLines.length - 1 - suffix];
      suffix++;
    }

    final originallyTrailing =
        _originalLineEndings.isNotEmpty && _originalLineEndings.last.isNotEmpty;
    for (var index = 0; index < endings.length - 1; index++) {
      if (endings[index].isEmpty) endings[index] = _defaultNewline;
    }
    if (originallyTrailing) {
      if (endings.last.isEmpty) endings[endings.length - 1] = _defaultNewline;
    } else {
      endings[endings.length - 1] = '';
    }
    return endings;
  }
}

class MarkdownFile {
  /// Strict load used by the Inbox editor's exact-snapshot precondition.
  /// Invalid UTF-8 and read failures remain distinguishable from an empty file.
  static Future<TaskFileSnapshotResult> loadSnapshot(String filePath) async {
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        return const TaskFileSnapshotResult.failed('The file does not exist.');
      }
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: false);
      final document = _TaskTextDocument.parse(
        content,
        hadUtf8Bom: _hasUtf8Bom(bytes),
      );
      return TaskFileSnapshotResult.ready(
        TaskFileSnapshot(
          bytes: List.unmodifiable(bytes),
          lines: List.unmodifiable(document.lines),
        ),
      );
    } on FormatException {
      return const TaskFileSnapshotResult.failed(
        'The file is not valid UTF-8. Interest did not modify it.',
      );
    } catch (_) {
      return const TaskFileSnapshotResult.failed(
        'The file could not be read. Interest did not modify it.',
      );
    }
  }

  /// Detects interrupted owned creation/replacement transactions before Inbox
  /// startup creates or accepts a canonical file. The canonical path is never
  /// changed; an exact completed creation may only have its marker removed.
  static Future<TaskFileRecoveryProbeResult> probeRecovery(
    String filePath,
  ) async {
    final canonical = File(filePath);
    final observedArtifactPaths = <String>[];
    try {
      final directory = canonical.parent;
      if (!await directory.exists()) {
        return const TaskFileRecoveryProbeResult(
          TaskFileRecoveryProbeStatus.clear,
        );
      }
      final entries = await VaultScanner.listDirect(directory.path);
      if (entries == null) {
        return const TaskFileRecoveryProbeResult(
          TaskFileRecoveryProbeStatus.blocked,
          error:
              'The file directory could not be inspected for an '
              'interrupted write. An empty Inbox was not created.',
        );
      }

      final name = p.basename(filePath);
      final creationCandidatePattern = RegExp(
        '^\\.${RegExp.escape(name)}\\.interest_create_.*\\.marker\$',
      );
      final creationPattern = RegExp(
        '^\\.${RegExp.escape(name)}\\.interest_create_([A-Za-z0-9_]+)'
        '\\.marker\$',
      );
      final mutationCandidatePattern = RegExp(
        '^\\.${RegExp.escape(name)}\\.interest_.*\\.(stage|backup)\$',
      );
      final mutationPattern = RegExp(
        '^\\.${RegExp.escape(name)}\\.interest_([A-Za-z0-9_]+)'
        '\\.(stage|backup)\$',
      );
      final creationMarkers = <String>[];
      final owned = <String, Map<String, String>>{};
      var malformedCreationMarker = false;
      var malformedOwnedArtifact = false;
      for (final entry in entries) {
        final basename = p.basename(entry.path);
        if (creationCandidatePattern.hasMatch(basename)) {
          observedArtifactPaths.add(entry.path);
          creationMarkers.add(entry.path);
          if (creationPattern.firstMatch(basename) == null) {
            malformedCreationMarker = true;
          }
          continue;
        }
        if (!mutationCandidatePattern.hasMatch(basename)) continue;
        observedArtifactPaths.add(entry.path);
        final match = mutationPattern.firstMatch(basename);
        if (match == null) {
          malformedOwnedArtifact = true;
          continue;
        }
        final transaction = owned.putIfAbsent(match.group(1)!, () => {});
        transaction[match.group(2)!] = entry.path;
      }
      observedArtifactPaths.sort();

      if (creationMarkers.isNotEmpty) {
        creationMarkers.sort();
        final inspectionPaths = <String>[filePath, ...creationMarkers];
        if (malformedCreationMarker || creationMarkers.length != 1) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error:
                'Ambiguous interrupted Inbox creation markers were found. '
                'The canonical Inbox was not accepted or created. Inspect: '
                '${inspectionPaths.join(', ')}',
          );
        }

        final markerPath = creationMarkers.single;
        if (await FileSystemEntity.type(markerPath, followLinks: false) !=
            FileSystemEntityType.file) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error:
                'The file creation marker is not a regular file. The '
                'canonical Inbox was not accepted or created. Inspect: '
                '${inspectionPaths.join(', ')}',
          );
        }
        final markerBytes = await File(markerPath).readAsBytes();
        utf8.decode(markerBytes, allowMalformed: false);
        if (!await canonical.exists()) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error:
                'An interrupted Inbox creation marker exists but the '
                'canonical Inbox is absent. An empty Inbox was not created. '
                'Inspect: ${inspectionPaths.join(', ')}',
          );
        }
        if (await FileSystemEntity.type(filePath, followLinks: false) !=
            FileSystemEntityType.file) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error:
                'The canonical Inbox beside its creation marker is not a '
                'regular file. It was not accepted or replaced. Inspect: '
                '${inspectionPaths.join(', ')}',
          );
        }
        final canonicalBytes = await canonical.readAsBytes();
        if (!_bytesEqual(canonicalBytes, markerBytes)) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error:
                'The canonical Inbox does not match its verified creation '
                'marker. It may be empty or partial and was not accepted or '
                'replaced. Inspect: ${inspectionPaths.join(', ')}',
          );
        }
        await _deleteOwnedFile(markerPath, const GuardedTaskFileOperations());
        return const TaskFileRecoveryProbeResult(
          TaskFileRecoveryProbeStatus.canonicalPresent,
        );
      }

      if (await canonical.exists()) {
        return const TaskFileRecoveryProbeResult(
          TaskFileRecoveryProbeStatus.canonicalPresent,
        );
      }
      if (observedArtifactPaths.isEmpty) {
        return const TaskFileRecoveryProbeResult(
          TaskFileRecoveryProbeStatus.clear,
        );
      }

      if (malformedOwnedArtifact ||
          owned.length != 1 ||
          owned.values.single['backup'] == null) {
        return TaskFileRecoveryProbeResult(
          TaskFileRecoveryProbeStatus.blocked,
          artifactPaths: observedArtifactPaths,
          error:
              'Ambiguous interrupted Inbox transaction artifacts were '
              'found. An empty Inbox was not created. Inspect: '
              '${observedArtifactPaths.join(', ')}',
        );
      }

      for (final artifactPath in observedArtifactPaths) {
        final type = await FileSystemEntity.type(
          artifactPath,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: observedArtifactPaths,
            error:
                'An interrupted Inbox transaction artifact is not a '
                'regular file. An empty Inbox was not created. Inspect: '
                '${observedArtifactPaths.join(', ')}',
          );
        }
        final bytes = await File(artifactPath).readAsBytes();
        utf8.decode(bytes, allowMalformed: false);
      }

      return TaskFileRecoveryProbeResult(
        TaskFileRecoveryProbeStatus.recoverable,
        artifactPaths: observedArtifactPaths,
        error:
            'A recoverable interrupted Inbox write was found. Interest '
            'refused to create an empty Inbox because this platform cannot '
            'restore without a cross-process replace race. Inspect: '
            '${observedArtifactPaths.join(', ')}',
      );
    } catch (_) {
      return TaskFileRecoveryProbeResult(
        TaskFileRecoveryProbeStatus.blocked,
        artifactPaths: observedArtifactPaths,
        error:
            'Interrupted Inbox transaction artifacts could not be read. '
            'An empty Inbox was not created.'
            '${observedArtifactPaths.isEmpty ? '' : ' Inspect: ${observedArtifactPaths.join(', ')}'}',
      );
    }
  }

  /// Shared exact-source writer for other Markdown-owned editors. The caller
  /// owns the interpretation; this mechanism owns staging and stale refusal.
  static Future<GuardedTaskMutationResult> guardedEditLines(
    String filePath,
    TaskFileSnapshot expected,
    bool Function(List<String>) mutate, {
    GuardedTaskFileOperations operations = const GuardedTaskFileOperations(),
  }) => _guardedMutate(filePath, expected, mutate, operations: operations);

  static Future<GuardedTaskMutationResult> guardedReplaceBytes(
    String filePath,
    TaskFileSnapshot expected,
    List<int> replacement, {
    GuardedTaskFileOperations operations = const GuardedTaskFileOperations(),
  }) async {
    try {
      utf8.decode(replacement, allowMalformed: false);
      return await _replaceWithStagedFile(
        filePath,
        expected.bytes,
        replacement,
        operations,
      );
    } catch (error) {
      return GuardedTaskMutationResult(
        GuardedTaskMutationStatus.unavailable,
        'The file could not be written: $error',
      );
    }
  }

  static Future<GuardedTaskMutationResult> _guardedMutate(
    String filePath,
    TaskFileSnapshot expected,
    bool Function(List<String> lines) mutate, {
    GuardedTaskFileOperations operations = const GuardedTaskFileOperations(),
  }) async {
    try {
      if (!await operations.exists(filePath)) return _staleResult;
      final currentBytes = await operations.readBytes(filePath);
      if (!_bytesEqual(currentBytes, expected.bytes)) return _staleResult;
      final current = utf8.decode(currentBytes, allowMalformed: false);

      final document = _TaskTextDocument.parse(
        current,
        hadUtf8Bom: _hasUtf8Bom(currentBytes),
      );
      if (!mutate(document.lines)) {
        return const GuardedTaskMutationResult(
          GuardedTaskMutationStatus.refused,
          'The requested item no longer matches the loaded file.',
        );
      }

      // Recheck immediately before the write so an edit made while the
      // mutation was being prepared is not overwritten.
      if (!await operations.exists(filePath)) return _staleResult;
      final beforeWrite = await operations.readBytes(filePath);
      if (!_bytesEqual(beforeWrite, expected.bytes)) return _staleResult;

      return _replaceWithStagedFile(
        filePath,
        expected.bytes,
        document.encodeBytes(),
        operations,
      );
    } on FormatException {
      return _staleResult;
    } catch (_) {
      return const GuardedTaskMutationResult(
        GuardedTaskMutationStatus.unavailable,
        'The file could not be written. It was reloaded without retrying.',
      );
    }
  }

  static Future<GuardedTaskMutationResult> _replaceWithStagedFile(
    String filePath,
    List<int> expectedBytes,
    List<int> replacementBytes,
    GuardedTaskFileOperations operations,
  ) async {
    late final String stagePath;
    late final String backupPath;
    try {
      final transaction = await _unusedTransactionPaths(filePath, operations);
      stagePath = transaction.stagePath;
      backupPath = transaction.backupPath;
      await operations.writeBytesFlushed(stagePath, replacementBytes);
      final stagedBytes = await operations.readBytes(stagePath);
      if (!_bytesEqual(stagedBytes, replacementBytes)) {
        await _deleteOwnedFile(stagePath, operations);
        return const GuardedTaskMutationResult(
          GuardedTaskMutationStatus.unavailable,
          'The file replacement could not be staged and verified. The '
          'original file was not replaced.',
        );
      }
    } catch (_) {
      try {
        await _deleteOwnedFile(stagePath, operations);
      } catch (_) {}
      return const GuardedTaskMutationResult(
        GuardedTaskMutationStatus.unavailable,
        'The file replacement could not be staged and verified. The '
        'original file was not replaced.',
      );
    }

    try {
      if (!await operations.exists(filePath) ||
          !_bytesEqual(await operations.readBytes(filePath), expectedBytes)) {
        await _deleteOwnedFile(stagePath, operations);
        return _staleResult;
      }
    } catch (_) {
      await _deleteOwnedFile(stagePath, operations);
      return const GuardedTaskMutationResult(
        GuardedTaskMutationStatus.unavailable,
        'The file could not be checked immediately before replacement. The '
        'staged change was not applied.',
      );
    }

    try {
      await operations.rename(filePath, backupPath);
    } catch (_) {
      return _resolveFailedTargetMove(
        filePath: filePath,
        stagePath: stagePath,
        backupPath: backupPath,
        expectedBytes: expectedBytes,
        operations: operations,
      );
    }

    List<int> backupBytes;
    try {
      backupBytes = await operations.readBytes(backupPath);
    } catch (_) {
      await _deleteOwnedFile(stagePath, operations);
      return _indeterminateReplacement(backupPath);
    }

    // This catches an external edit in the final check -> target move gap:
    // the moved bytes are authoritative and must be restored, not replaced.
    if (!_bytesEqual(backupBytes, expectedBytes)) {
      await _deleteOwnedFile(stagePath, operations);
      final recovery = await _restoreBackupIfTargetAbsent(
        filePath,
        backupPath,
        backupBytes,
        operations,
      );
      if (recovery == _BackupRestoreOutcome.restored) return _staleResult;
      return _indeterminateReplacement(backupPath);
    }

    // A new canonical target means another process wrote after our move. Do
    // not restore or install over it; retain the verified backup for recovery.
    try {
      if (await operations.exists(filePath)) {
        await _deleteOwnedFile(stagePath, operations);
        return _indeterminateReplacement(backupPath);
      }
    } catch (_) {
      await _deleteOwnedFile(stagePath, operations);
      return _indeterminateReplacement(backupPath);
    }

    try {
      await operations.rename(stagePath, filePath);
    } catch (_) {
      await _deleteOwnedFile(stagePath, operations);
      final recovery = await _restoreBackupIfTargetAbsent(
        filePath,
        backupPath,
        expectedBytes,
        operations,
      );
      if (recovery == _BackupRestoreOutcome.restored) {
        return const GuardedTaskMutationResult(
          GuardedTaskMutationStatus.unavailable,
          'The file replacement failed, but the previous contents were '
          'restored and verified. It was reloaded without retrying.',
        );
      }
      return _indeterminateReplacement(backupPath);
    }

    try {
      if (await operations.exists(filePath) &&
          _bytesEqual(await operations.readBytes(filePath), replacementBytes)) {
        await _deleteOwnedFile(backupPath, operations);
        return const GuardedTaskMutationResult(
          GuardedTaskMutationStatus.applied,
          'Applied.',
        );
      }
    } catch (_) {
      // The replacement may have succeeded, but its canonical state is now
      // ambiguous. Keep the verified backup and never overwrite a target that
      // may have reappeared or changed externally.
    }

    try {
      if (!await operations.exists(filePath)) {
        final recovery = await _restoreBackupIfTargetAbsent(
          filePath,
          backupPath,
          expectedBytes,
          operations,
        );
        if (recovery == _BackupRestoreOutcome.restored) {
          return const GuardedTaskMutationResult(
            GuardedTaskMutationStatus.unavailable,
            'The file replacement could not be verified, so the previous '
            'contents were restored and verified.',
          );
        }
      }
    } catch (_) {}
    return _indeterminateReplacement(backupPath);
  }

  static Future<GuardedTaskMutationResult> _resolveFailedTargetMove({
    required String filePath,
    required String stagePath,
    required String backupPath,
    required List<int> expectedBytes,
    required GuardedTaskFileOperations operations,
  }) async {
    await _deleteOwnedFile(stagePath, operations);
    try {
      if (await operations.exists(backupPath)) {
        final backupBytes = await operations.readBytes(backupPath);
        if (await operations.exists(filePath)) {
          return _indeterminateReplacement(backupPath);
        }
        final recovery = await _restoreBackupIfTargetAbsent(
          filePath,
          backupPath,
          backupBytes,
          operations,
        );
        if (recovery == _BackupRestoreOutcome.restored) {
          return _bytesEqual(backupBytes, expectedBytes)
              ? const GuardedTaskMutationResult(
                GuardedTaskMutationStatus.unavailable,
                'The file replacement failed, but the previous contents '
                'were restored and verified.',
              )
              : _staleResult;
        }
        return _indeterminateReplacement(backupPath);
      }

      if (await operations.exists(filePath)) {
        final currentBytes = await operations.readBytes(filePath);
        return _bytesEqual(currentBytes, expectedBytes)
            ? const GuardedTaskMutationResult(
              GuardedTaskMutationStatus.unavailable,
              'The file replacement could not begin. The previous '
              'contents remain in place.',
            )
            : _staleResult;
      }
    } catch (_) {}
    return const GuardedTaskMutationResult(
      GuardedTaskMutationStatus.indeterminate,
      'The file replacement outcome is indeterminate. Reload and inspect the '
      'Inbox before editing again.',
    );
  }

  static Future<_BackupRestoreOutcome> _restoreBackupIfTargetAbsent(
    String filePath,
    String backupPath,
    List<int> backupBytes,
    GuardedTaskFileOperations operations,
  ) async {
    try {
      if (await operations.exists(filePath)) {
        return _BackupRestoreOutcome.targetPresent;
      }
      await operations.rename(backupPath, filePath);
      if (await operations.exists(filePath) &&
          _bytesEqual(await operations.readBytes(filePath), backupBytes)) {
        return _BackupRestoreOutcome.restored;
      }
    } catch (_) {
      try {
        if (await operations.exists(filePath)) {
          final targetBytes = await operations.readBytes(filePath);
          return _bytesEqual(targetBytes, backupBytes)
              ? _BackupRestoreOutcome.restored
              : _BackupRestoreOutcome.targetPresent;
        }
      } catch (_) {}
    }
    return _BackupRestoreOutcome.failed;
  }

  static GuardedTaskMutationResult _indeterminateReplacement(
    String backupPath,
  ) => GuardedTaskMutationResult(
    GuardedTaskMutationStatus.indeterminate,
    'The file replacement outcome is indeterminate. Interest did not '
    'overwrite a canonical file that may have changed externally. A '
    'verified recovery copy was retained at $backupPath.',
  );

  static Future<_TaskFileTransactionPaths> _unusedTransactionPaths(
    String filePath,
    GuardedTaskFileOperations operations,
  ) async {
    final directory = p.dirname(filePath);
    final name = p.basename(filePath);
    final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    for (var suffix = 0; suffix < 100; suffix++) {
      final transactionId = '${nonce}_$suffix';
      final stagePath = p.join(
        directory,
        '.$name.interest_$transactionId.stage',
      );
      final backupPath = p.join(
        directory,
        '.$name.interest_$transactionId.backup',
      );
      if (!await operations.exists(stagePath) &&
          !await operations.exists(backupPath)) {
        return _TaskFileTransactionPaths(stagePath, backupPath);
      }
    }
    throw const FileSystemException(
      'Could not allocate a same-directory Inbox transaction file.',
    );
  }

  static Future<void> _deleteOwnedFile(
    String path,
    GuardedTaskFileOperations operations,
  ) async {
    try {
      if (await operations.exists(path)) await operations.delete(path);
    } catch (_) {}
  }

  static bool _hasUtf8Bom(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static const _staleResult = GuardedTaskMutationResult(
    GuardedTaskMutationStatus.stale,
    'Inbox changed outside Interest. Your change was not applied.',
  );

  // One source-preserving title/filename rename for both project editors.
  static Future<String?> renameTaskFile(
    String filePath,
    String newName, {
    TaskFileSnapshot? expected,
  }) async {
    TaskFileSnapshot? before;
    TaskFileSnapshot? patched;
    try {
      if (newName.trim().isEmpty ||
          newName.contains('\n') ||
          newName.contains('\r')) {
        return null;
      }
      final safeName = newName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final newPath = p.join(p.dirname(filePath), '$safeName.md');
      final samePath = p.equals(p.absolute(newPath), p.absolute(filePath));
      if (!samePath && await File(newPath).exists()) return null;
      before = expected ?? (await loadSnapshot(filePath)).snapshot;
      if (before == null ||
          !_bytesEqual(await File(filePath).readAsBytes(), before.bytes)) {
        return null;
      }
      final titles = unfencedBodyLines(
        before.lines,
      ).where((i) => before!.lines[i].startsWith('# '));
      if (titles.isNotEmpty) {
        final document = _TaskTextDocument.parse(
          utf8.decode(before.bytes),
          hadUtf8Bom: _hasUtf8Bom(before.bytes),
        );
        document.lines[titles.first] = '# $newName';
        patched = TaskFileSnapshot(
          bytes: document.encodeBytes(),
          lines: List.unmodifiable(document.lines),
        );
        final result = await guardedReplaceBytes(
          filePath,
          before,
          patched.bytes,
        );
        if (!result.applied) return null;
      }
      if (!samePath) {
        if (await File(newPath).exists()) {
          throw const FileSystemException('Rename destination appeared');
        }
        if (!_bytesEqual(
          await File(filePath).readAsBytes(),
          (patched ?? before).bytes,
        )) {
          throw const FileSystemException('Source changed before rename');
        }
        await File(filePath).rename(newPath);
      }
      return newPath;
    } catch (_) {
      // Restore only the exact write owned by this rename; never erase a later
      // external edit. The guarded writer retains recovery artifacts on failure.
      if (before != null && patched != null) {
        await guardedReplaceBytes(filePath, patched, before.bytes);
      }
      return null;
    }
  }
}
