import 'dart:convert';
import 'dart:io';

import '../../../core/vault_paths.dart';
import '../models/open_inbox_item.dart';
import '../models/task_block.dart';
import 'task_storage_service.dart';

class OpenInboxFileStamp {
  final DateTime modifiedAt;
  final int size;

  const OpenInboxFileStamp({required this.modifiedAt, required this.size});

  bool sameAs(OpenInboxFileStamp other) =>
      modifiedAt == other.modifiedAt && size == other.size;
}

/// Injectable read-only filesystem boundary for coherent provider tests.
class OpenInboxFileAccess {
  const OpenInboxFileAccess();

  Future<bool> exists(String path) => File(path).exists();

  Future<OpenInboxFileStamp> stamp(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Inbox is not a regular file.', path);
    }
    return OpenInboxFileStamp(
      modifiedAt: stat.modified.toUtc(),
      size: stat.size,
    );
  }

  Future<List<int>> readBytes(String path) => File(path).readAsBytes();
}

class _StableInboxObservation {
  final List<int> bytes;
  final OpenInboxFileStamp stamp;
  final DateTime observedAt;

  const _StableInboxObservation({
    required this.bytes,
    required this.stamp,
    required this.observedAt,
  });
}

/// Read-only provider for the single canonical Inbox file.
///
/// It does not create the Inbox and it never scans Projects or other vault
/// files. UI creation belongs to `InboxStorageService`; querying a missing
/// source therefore produces an explicit unavailable result.
class OpenInboxQueryService {
  static Future<OpenInboxQueryResult> query(
    String vaultPath, {
    OpenInboxFileAccess fileAccess = const OpenInboxFileAccess(),
  }) async {
    try {
      final vault = Directory(vaultPath);
      if (!await vault.exists()) {
        return _unavailable(_now(), 'Vault does not exist.');
      }

      final filePath = VaultPaths.inbox(vaultPath);
      if (!await fileAccess.exists(filePath)) {
        return _unavailable(
          _now(),
          'Interesting/Inbox.md does not exist. The read-only provider did '
          'not create it.',
        );
      }

      final observation = await _observeStable(filePath, fileAccess);
      if (observation == null) {
        return _indeterminate(
          _now(),
          'Interesting/Inbox.md changed during the bounded observation. No '
          'records were emitted from an incoherent read.',
        );
      }
      final content = utf8.decode(observation.bytes, allowMalformed: false);
      final lines = const LineSplitter().convert(content);
      final items = parseOpenItems(lines);
      return OpenInboxQueryResult(
        status: 'complete',
        completeness: 'complete',
        observedAt: observation.observedAt.toIso8601String(),
        sourceModifiedAt: observation.stamp.modifiedAt.toIso8601String(),
        errors: const [],
        limitations: const [
          'Only Interesting/Inbox.md is queried; every other vault file is '
              'outside scope and was not scanned.',
        ],
        records: items,
      );
    } catch (error) {
      return _unavailable(
        _now(),
        'Interesting/Inbox.md could not be read: $error',
      );
    }
  }

  static Future<_StableInboxObservation?> _observeStable(
    String filePath,
    OpenInboxFileAccess fileAccess,
  ) async {
    Object? lastError;
    var sawInconsistentRead = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final before = await fileAccess.stamp(filePath);
        final firstBytes = await fileAccess.readBytes(filePath);
        final between = await fileAccess.stamp(filePath);
        final secondBytes = await fileAccess.readBytes(filePath);
        final after = await fileAccess.stamp(filePath);
        if (before.sameAs(between) &&
            between.sameAs(after) &&
            firstBytes.length == after.size &&
            _bytesEqual(firstBytes, secondBytes)) {
          return _StableInboxObservation(
            bytes: firstBytes,
            stamp: after,
            observedAt: DateTime.now().toUtc(),
          );
        }
        sawInconsistentRead = true;
      } catch (error) {
        lastError = error;
      }
    }
    if (!sawInconsistentRead && lastError != null) throw lastError;
    return null;
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// Pure query projection over the same parser used by the Inbox editor.
  static List<OpenInboxItem> parseOpenItems(List<String> lines) {
    final nodes = TaskStorageService.parseNodes(lines);
    final items = <OpenInboxItem>[];
    final headingStack = <int, String>{};

    for (final node in nodes) {
      if (node is TaskHeaderNode) {
        headingStack.removeWhere((level, _) => level >= node.headingLevel);
        headingStack[node.headingLevel] = node.text;
        continue;
      }
      if (node is TaskBlock) {
        _collect(
          block: node,
          lines: lines,
          headings: [
            for (final level in headingStack.keys.toList()..sort())
              headingStack[level]!,
          ],
          parents: const [],
          ancestorCompleted: false,
          output: items,
        );
      }
    }
    return items;
  }

  static void _collect({
    required TaskBlock block,
    required List<String> lines,
    required List<String> headings,
    required List<String> parents,
    required bool ancestorCompleted,
    required List<OpenInboxItem> output,
  }) {
    if (!block.completed) {
      output.add(
        OpenInboxItem(
          text: block.text,
          line: block.startLine + 1,
          indentSpaces: block.indentSpaces,
          headings: List.unmodifiable(headings),
          parentItems: List.unmodifiable(parents),
          hasCompletedAncestor: ancestorCompleted,
          attachedProse: [
            for (final index in block.noteLineIndices)
              if (index >= 0 &&
                  index < lines.length &&
                  lines[index].trim().isNotEmpty)
                OpenInboxProseLine(
                  line: index + 1,
                  text: lines[index].trimLeft(),
                ),
          ],
        ),
      );
    }

    for (final child in block.children) {
      _collect(
        block: child,
        lines: lines,
        headings: headings,
        parents: [...parents, block.text],
        ancestorCompleted: ancestorCompleted || block.completed,
        output: output,
      );
    }
  }

  static OpenInboxQueryResult _unavailable(
    String observedAt,
    String limitation,
  ) => OpenInboxQueryResult(
    status: 'unavailable',
    completeness: 'unavailable',
    observedAt: observedAt,
    sourceModifiedAt: null,
    errors: [limitation],
    limitations: const [
      'Only Interesting/Inbox.md is queried; every other vault file is '
          'outside scope and was not scanned.',
    ],
    records: const [],
  );

  static OpenInboxQueryResult _indeterminate(
    String observedAt,
    String error,
  ) => OpenInboxQueryResult(
    status: 'indeterminate',
    completeness: 'indeterminate',
    observedAt: observedAt,
    sourceModifiedAt: null,
    errors: [error],
    limitations: const [
      'Only Interesting/Inbox.md is queried; every other vault file is '
          'outside scope and was not scanned.',
      'The provider emits no records unless two bounded byte reads and their '
          'filesystem stamps describe one coherent observation.',
    ],
    records: const [],
  );
}
