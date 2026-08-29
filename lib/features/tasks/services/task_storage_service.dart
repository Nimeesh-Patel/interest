import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/markdown/vault_scanner.dart';
import '../models/task_block.dart';

class TaskFileSnapshot {
  final List<int> bytes;
  final List<String> lines;

  const TaskFileSnapshot({
    required this.bytes,
    required this.lines,
  });
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

class TaskStorageService {
  static final _taskRegex = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.+)$');

  static Future<List<String>> loadLines(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];
      return await file.readAsLines();
    } catch (_) {
      return [];
    }
  }

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
          error: 'The Inbox directory could not be inspected for an '
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
            error: 'Ambiguous interrupted Inbox creation markers were found. '
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
            error: 'The Inbox creation marker is not a regular file. The '
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
            error: 'An interrupted Inbox creation marker exists but the '
                'canonical Inbox is absent. An empty Inbox was not created. '
                'Inspect: ${inspectionPaths.join(', ')}',
          );
        }
        if (await FileSystemEntity.type(filePath, followLinks: false) !=
            FileSystemEntityType.file) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error: 'The canonical Inbox beside its creation marker is not a '
                'regular file. It was not accepted or replaced. Inspect: '
                '${inspectionPaths.join(', ')}',
          );
        }
        final canonicalBytes = await canonical.readAsBytes();
        if (!_bytesEqual(canonicalBytes, markerBytes)) {
          return TaskFileRecoveryProbeResult(
            TaskFileRecoveryProbeStatus.blocked,
            artifactPaths: inspectionPaths,
            error: 'The canonical Inbox does not match its verified creation '
                'marker. It may be empty or partial and was not accepted or '
                'replaced. Inspect: ${inspectionPaths.join(', ')}',
          );
        }
        await _deleteOwnedFile(
          markerPath,
          const GuardedTaskFileOperations(),
        );
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
          error: 'Ambiguous interrupted Inbox transaction artifacts were '
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
            error: 'An interrupted Inbox transaction artifact is not a '
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
        error: 'A recoverable interrupted Inbox write was found. Interest '
            'refused to create an empty Inbox because this platform cannot '
            'restore without a cross-process replace race. Inspect: '
            '${observedArtifactPaths.join(', ')}',
      );
    } catch (_) {
      return TaskFileRecoveryProbeResult(
        TaskFileRecoveryProbeStatus.blocked,
        artifactPaths: observedArtifactPaths,
        error: 'Interrupted Inbox transaction artifacts could not be read. '
            'An empty Inbox was not created.'
            '${observedArtifactPaths.isEmpty ? '' : ' Inspect: ${observedArtifactPaths.join(', ')}'}',
      );
    }
  }

  // ── Exact-snapshot mutations (Inbox) ─────────────────────────────────────

  static Future<GuardedTaskMutationResult> guardedAddTask(
    String filePath,
    TaskFileSnapshot expected,
    String text, {
    GuardedTaskFileOperations operations = const GuardedTaskFileOperations(),
  }) => _guardedMutate(filePath, expected, (lines) {
    lines.add('- [ ] $text');
    return true;
  }, operations: operations);

  static Future<GuardedTaskMutationResult> guardedToggleBlock(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock block,
  ) => _guardedMutate(filePath, expected, (lines) {
    if (block.startLine < 0 || block.startLine >= lines.length) return false;
    final line = lines[block.startLine];
    if (_taskRegex.firstMatch(line) == null) return false;
    lines[block.startLine] =
        block.completed
            ? line.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]')
            : line.replaceFirst('[ ]', '[x]');
    return lines[block.startLine] != line;
  });

  static Future<GuardedTaskMutationResult> guardedUpdateBlockText(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock block,
    String newText,
  ) => _guardedMutate(filePath, expected, (lines) {
    return _updateTaskTextInLines(lines, block.startLine, newText);
  });

  static Future<GuardedTaskMutationResult> guardedDeleteBlock(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock block,
  ) => _guardedMutate(filePath, expected, (lines) {
    if (block.startLine < 0 || block.endLine >= lines.length) return false;
    lines.removeRange(block.startLine, block.endLine + 1);
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedAddNote(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock parent,
    String noteText,
  ) => _guardedMutate(filePath, expected, (lines) {
    if (parent.startLine < 0 || parent.startLine >= lines.length) return false;
    final indent = ' ' * (parent.indentSpaces + 2);
    final noteLines =
        noteText
            .split('\n')
            .map((line) => line.isEmpty ? '' : '$indent$line')
            .toList();
    lines.insertAll(parent.startLine + 1, noteLines);
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedAddSubtask(
    String filePath,
    TaskFileSnapshot expected,
    TaskBlock parent,
    String text,
  ) => _guardedMutate(filePath, expected, (lines) {
    if (parent.endLine < 0 || parent.endLine >= lines.length) return false;
    final indent = ' ' * (parent.indentSpaces + 2);
    lines.insert(parent.endLine + 1, '$indent- [ ] $text');
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedUpdateLine(
    String filePath,
    TaskFileSnapshot expected,
    int lineIndex,
    String newText,
  ) => _guardedMutate(filePath, expected, (lines) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    lines[lineIndex] = newText;
    return true;
  });

  static Future<GuardedTaskMutationResult> guardedDeleteLine(
    String filePath,
    TaskFileSnapshot expected,
    int lineIndex,
  ) => _guardedMutate(filePath, expected, (lines) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    lines.removeAt(lineIndex);
    return true;
  });

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
          'The requested item no longer matches the loaded Inbox.',
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
        'The Inbox could not be written. It was reloaded without retrying.',
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
          'The Inbox replacement could not be staged and verified. The '
          'original file was not replaced.',
        );
      }
    } catch (_) {
      try {
        await _deleteOwnedFile(stagePath, operations);
      } catch (_) {}
      return const GuardedTaskMutationResult(
        GuardedTaskMutationStatus.unavailable,
        'The Inbox replacement could not be staged and verified. The '
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
        'The Inbox could not be checked immediately before replacement. The '
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
          'The Inbox replacement failed, but the previous contents were '
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
            'The Inbox replacement could not be verified, so the previous '
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
                'The Inbox replacement failed, but the previous contents '
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
              'The Inbox replacement could not begin. The previous '
              'contents remain in place.',
            )
            : _staleResult;
      }
    } catch (_) {}
    return const GuardedTaskMutationResult(
      GuardedTaskMutationStatus.indeterminate,
      'The Inbox replacement outcome is indeterminate. Reload and inspect the '
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
    'The Inbox replacement outcome is indeterminate. Interest did not '
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

  static bool _updateTaskTextInLines(
    List<String> lines,
    int lineIndex,
    String newText,
  ) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    final match = _taskRegex.firstMatch(lines[lineIndex]);
    if (match == null) return false;
    final checkState = match.group(1)!;
    final dashIndex = lines[lineIndex].indexOf('-');
    final indent =
        dashIndex > 0 ? lines[lineIndex].substring(0, dashIndex) : '';
    lines[lineIndex] = '$indent- [$checkState] $newText';
    return true;
  }

  static Future<void> toggleTask(String filePath, int lineIndex) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      final line = lines[lineIndex];
      final m = _taskRegex.firstMatch(line);
      if (m == null) return;
      final isDone = m.group(1)!.toLowerCase() == 'x';
      if (isDone) {
        lines[lineIndex] = line.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
      } else {
        lines[lineIndex] = line.replaceFirst('[ ]', '[x]');
      }
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  static Future<void> addTask(String filePath, String text) async {
    try {
      final file = File(filePath);
      final lines = await file.readAsLines();
      final newLine = '- [ ] $text';
      final completedRoot = RegExp(r'^- \[[xX]\]');
      final insertIdx = lines.indexWhere((l) => completedRoot.hasMatch(l));
      if (insertIdx == -1) {
        final content = lines.join('\n');
        final updated = content.endsWith('\n')
            ? '$content$newLine\n'
            : '$content\n$newLine\n';
        await file.writeAsString(updated);
      } else {
        lines.insert(insertIdx, newLine);
        await file.writeAsString('${lines.join('\n')}\n');
      }
    } catch (_) {}
  }

  static Future<void> deleteTask(String filePath, int lineIndex) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      lines.removeAt(lineIndex);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  static Future<void> updateTaskText(
      String filePath, int lineIndex, String newText) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      final m = _taskRegex.firstMatch(lines[lineIndex]);
      if (m == null) return;
      final checkState = m.group(1)!;
      final dashIdx = lines[lineIndex].indexOf('-');
      final indent = dashIdx > 0 ? lines[lineIndex].substring(0, dashIdx) : '';
      lines[lineIndex] = '$indent- [$checkState] $newText';
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // ── Hierarchical block parser ──────────────────────────────────────────────

  // Parse a flat list of file lines into a tree of TaskNodes.
  // Pure function — no I/O. Call after loadLines().
  static List<TaskNode> parseNodes(List<String> lines) {
    final nodes = <TaskNode>[];
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Skip H1 (file title — shown in AppBar)
      if (line.startsWith('# ') && !line.startsWith('## ')) {
        i++;
        continue;
      }

      if (line.startsWith('### ')) {
        nodes.add(TaskHeaderNode(lineIndex: i, headingLevel: 3, text: line.substring(4).trim()));
        i++;
        continue;
      }

      if (line.startsWith('## ')) {
        nodes.add(TaskHeaderNode(lineIndex: i, headingLevel: 2, text: line.substring(3).trim()));
        i++;
        continue;
      }

      final m = _taskRegex.firstMatch(line);
      if (m != null) {
        final indentSpaces = line.indexOf('-');
        final block = TaskBlock(
          text: m.group(2)!,
          completed: m.group(1)!.toLowerCase() == 'x',
          indentSpaces: indentSpaces < 0 ? 0 : indentSpaces,
          startLine: i,
          noteLineIndices: [],
          children: [],
        );
        i = _collectBlockContent(lines, i + 1, block);
        nodes.add(block);
        continue;
      }

      nodes.add(TaskProseNode(lineIndex: i, raw: line));
      i++;
    }
    return nodes;
  }

  // Collect notes and children for [parent], starting at line [start].
  // Returns the next unconsumed line index.
  static int _collectBlockContent(List<String> lines, int start, TaskBlock parent) {
    int i = start;
    while (i < lines.length) {
      final line = lines[i];

      // Headers always terminate the block
      if (line.startsWith('#')) break;

      final trimmed = line.trimLeft();

      if (trimmed.isEmpty) {
        // Blank line: look ahead to decide if it belongs to this block
        final next = _nextNonBlankLine(lines, i + 1);
        if (next == null || next.startsWith('#')) break;
        final nextIndent = next.length - next.trimLeft().length;
        if (nextIndent <= parent.indentSpaces) break;
        parent.noteLineIndices.add(i);
        i++;
        continue;
      }

      final indent = line.length - trimmed.length;
      if (indent <= parent.indentSpaces) break;

      final m = _taskRegex.firstMatch(line);
      if (m != null) {
        final child = TaskBlock(
          text: m.group(2)!,
          completed: m.group(1)!.toLowerCase() == 'x',
          indentSpaces: indent,
          startLine: i,
          noteLineIndices: [],
          children: [],
        );
        i = _collectBlockContent(lines, i + 1, child);
        parent.children.add(child);
      } else {
        parent.noteLineIndices.add(i);
        i++;
      }
    }
    return i;
  }

  static String? _nextNonBlankLine(List<String> lines, int from) {
    for (int i = from; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) return lines[i];
    }
    return null;
  }

  // ── Block-level mutations ──────────────────────────────────────────────────

  // Insert a note immediately after the task's own line (before children).
  // Multiline noteText is split on '\n'; each piece is indented at
  // parent.indentSpaces + 2 to satisfy _collectBlockContent's indent check.
  static Future<void> addNote(
      String filePath, TaskBlock parent, String noteText) async {
    try {
      final lines = await File(filePath).readAsLines();
      final indent = ' ' * (parent.indentSpaces + 2);
      final noteLines = noteText
          .split('\n')
          .map((l) => l.isEmpty ? '' : '$indent$l')
          .toList();
      lines.insertAll(parent.startLine + 1, noteLines);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Insert a subtask as the last child of [parent].
  static Future<void> addSubtask(
      String filePath, TaskBlock parent, String text) async {
    try {
      final lines = await File(filePath).readAsLines();
      final indent = ' ' * (parent.indentSpaces + 2);
      lines.insert(parent.endLine + 1, '$indent- [ ] $text');
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Delete a block and its entire subtree (notes + children).
  static Future<void> deleteBlock(String filePath, TaskBlock block) async {
    try {
      final lines = await File(filePath).readAsLines();
      final end = block.endLine;
      if (block.startLine < 0 || end >= lines.length) return;
      lines.removeRange(block.startLine, end + 1);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Update the text of a task block (thin wrapper over updateTaskText).
  static Future<void> updateBlockText(
      String filePath, TaskBlock block, String newText) async {
    await updateTaskText(filePath, block.startLine, newText);
  }

  // Replace a single arbitrary line (used for inline note editing).
  static Future<void> updateLine(
      String filePath, int lineIndex, String newText) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (lineIndex < 0 || lineIndex >= lines.length) return;
      lines[lineIndex] = newText;
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Toggle a block's completion state and move it to maintain semantic order:
  // completing moves the block to the bottom; uncompleting moves it before the
  // first complete root-level block.
  static Future<void> toggleBlockAndReorder(
      String filePath, TaskBlock block) async {
    try {
      final lines = await File(filePath).readAsLines();
      if (block.startLine < 0 || block.endLine >= lines.length) return;

      final wasComplete = block.completed;
      if (wasComplete) {
        lines[block.startLine] =
            lines[block.startLine].replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
      } else {
        lines[block.startLine] =
            lines[block.startLine].replaceFirst('[ ]', '[x]');
      }

      // A nested block belongs to its parent by indentation. Moving it to a
      // root-level ordering position would silently detach the entire subtree.
      if (block.indentSpaces > 0) {
        await File(filePath).writeAsString(lines.join('\n'));
        return;
      }

      final blockLines = lines.sublist(block.startLine, block.endLine + 1);
      lines.removeRange(block.startLine, block.endLine + 1);

      int insertLine;
      if (!wasComplete) {
        // Newly complete → move to bottom
        insertLine = lines.length;
      } else {
        // Newly incomplete → insert before the first complete root-level block
        final firstComplete = lines.indexWhere(
          (l) => _taskRegex.hasMatch(l) && l.indexOf('-') == 0 &&
              RegExp(r'^\s*-\s+\[[xX]\]').hasMatch(l),
        );
        insertLine = firstComplete == -1 ? lines.length : firstComplete;
      }

      lines.insertAll(insertLine.clamp(0, lines.length), blockLines);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Reorder root-level task blocks in the file.
  // [nodes] is the current parsed node list; [newIndex] addresses the sequence
  // after removing [oldIndex], matching ReorderableListView.onReorderItem.
  static Future<void> reorderRootBlocks(
      String filePath, List<TaskNode> nodes, int oldIndex, int newIndex) async {
    try {
      if (oldIndex == newIndex) return;
      if (oldIndex < 0 || oldIndex >= nodes.length) return;
      final movedNode = nodes[oldIndex];
      if (movedNode is! TaskBlock || movedNode.indentSpaces != 0) return;

      final lines = await File(filePath).readAsLines();
      final start = movedNode.startLine;
      final end = movedNode.endLine;
      if (start < 0 || end >= lines.length) return;

      final removedCount = end - start + 1;
      final blockLines = lines.sublist(start, end + 1);
      lines.removeRange(start, end + 1);

      final remaining = List<TaskNode>.from(nodes)..removeAt(oldIndex);

      int insertLine;
      if (newIndex >= remaining.length) {
        insertLine = lines.length;
      } else {
        final refNode = remaining[newIndex];
        int refLine;
        if (refNode is TaskBlock) {
          refLine = refNode.startLine;
        } else if (refNode is TaskHeaderNode) {
          refLine = refNode.lineIndex;
        } else if (refNode is TaskProseNode) {
          refLine = refNode.lineIndex;
        } else {
          insertLine = lines.length;
          lines.insertAll(insertLine, blockLines);
          await File(filePath).writeAsString(lines.join('\n'));
          return;
        }
        if (refLine > start) refLine -= removedCount;
        insertLine = refLine.clamp(0, lines.length);
      }

      lines.insertAll(insertLine, blockLines);
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  // Rename a task file: update the # heading and rename the file on disk.
  // Returns the new file path, or null on failure / name collision.
  static Future<String?> renameTaskFile(
      String filePath, String newName) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('# ') && !lines[i].startsWith('## ')) {
          lines[i] = '# $newName';
          break;
        }
      }
      await file.writeAsString(lines.join('\n'));
      final dir = p.dirname(filePath);
      final safeName = newName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final newPath = p.join(dir, '$safeName.md');
      if (newPath == filePath) return filePath;
      if (await File(newPath).exists()) return null;
      final renamed = await file.rename(newPath);
      return renamed.path;
    } catch (_) {
      return null;
    }
  }
}
