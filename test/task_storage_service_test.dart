import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/tasks/models/task_block.dart';
import 'package:people_tracker/features/tasks/services/task_storage_service.dart';

void main() {
  group('TaskStorageService.parseNodes', () {
    test('keeps headings, attached prose, and nested checkbox structure', () {
      final nodes = TaskStorageService.parseNodes(const [
        '# Inbox',
        '',
        '## Physics',
        '- [ ] Read Wheeler',
        '  Manhattan Project and scientific culture.',
        '  - [x] Find the edition',
        '  - [ ] Read chapter one',
        '- [x] Finished item',
      ]);

      expect(nodes.whereType<TaskHeaderNode>().single.text, 'Physics');
      final roots = nodes.whereType<TaskBlock>().toList();
      expect(roots, hasLength(2));

      final wheeler = roots.first;
      expect(wheeler.text, 'Read Wheeler');
      expect(wheeler.completed, isFalse);
      expect(wheeler.noteLineIndices, [4]);
      expect(wheeler.children, hasLength(2));
      expect(wheeler.children.first.completed, isTrue);
      expect(wheeler.children.last.text, 'Read chapter one');
      expect(wheeler.endLine, 6);
    });

    test('does not turn free prose or plain list items into tasks', () {
      final nodes = TaskStorageService.parseNodes(const [
        '# Inbox',
        'A half-formed thought',
        '- a plain list item',
        '- [ ] an open checkbox',
      ]);

      expect(nodes.whereType<TaskProseNode>(), hasLength(2));
      expect(nodes.whereType<TaskBlock>().single.text, 'an open checkbox');
    });
  });

  group('task mutation safety', () {
    late Directory temp;
    late File file;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('interest_tasks_');
      file = File(p.join(temp.path, 'Inbox.md'));
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test(
      'nested completion toggles in place without detaching the child',
      () async {
        file.writeAsStringSync('''# Project

- [ ] Parent
  - [ ] Child
- [ ] Sibling
''');
        final lines = await file.readAsLines();
        final parent =
            TaskStorageService.parseNodes(lines).whereType<TaskBlock>().first;
        final child = parent.children.single;

        await TaskStorageService.toggleBlockAndReorder(file.path, child);

        final after = await file.readAsLines();
        expect(after, [
          '# Project',
          '',
          '- [ ] Parent',
          '  - [x] Child',
          '- [ ] Sibling',
        ]);
      },
    );

    test(
      'root reorder uses indices after removal in both directions',
      () async {
        file.writeAsStringSync('''- [ ] First
  first context
- [ ] Second
- [ ] Third
''');
        var nodes = TaskStorageService.parseNodes(await file.readAsLines());

        await TaskStorageService.reorderRootBlocks(file.path, nodes, 0, 2);
        expect(await file.readAsLines(), [
          '- [ ] Second',
          '- [ ] Third',
          '- [ ] First',
          '  first context',
        ]);

        nodes = TaskStorageService.parseNodes(await file.readAsLines());
        await TaskStorageService.reorderRootBlocks(file.path, nodes, 2, 0);
        expect(await file.readAsLines(), [
          '- [ ] First',
          '  first context',
          '- [ ] Second',
          '- [ ] Third',
        ]);
      },
    );

    test(
      'guarded Inbox completion stays inside its authored section',
      () async {
        const before = '''# Inbox

## Reading
- [ ] Read Wheeler
## Watching
- [ ] Watch lecture
''';
        file.writeAsStringSync(before);
        final snapshot =
            (await TaskStorageService.loadSnapshot(file.path)).snapshot!;
        final block =
            TaskStorageService.parseNodes(
              snapshot.lines,
            ).whereType<TaskBlock>().first;

        final result = await TaskStorageService.guardedToggleBlock(
          file.path,
          snapshot,
          block,
        );

        expect(result.status, GuardedTaskMutationStatus.applied);
        final after = file.readAsStringSync();
        expect(
          after.indexOf('## Reading'),
          lessThan(after.indexOf('- [x] Read Wheeler')),
        );
        expect(
          after.indexOf('- [x] Read Wheeler'),
          lessThan(after.indexOf('## Watching')),
        );
        expect(
          after.indexOf('## Watching'),
          lessThan(after.indexOf('- [ ] Watch lecture')),
        );
      },
    );

    test('every guarded Inbox write refuses a stale exact snapshot', () async {
      const before = '''# Inbox

- [ ] Parent
  context
  - [ ] Child
''';

      final operations = <
        String,
        Future<GuardedTaskMutationResult> Function(
          TaskFileSnapshot expected,
          TaskBlock block,
        )
      >{
        'add task':
            (expected, block) =>
                TaskStorageService.guardedAddTask(file.path, expected, 'Added'),
        'toggle':
            (expected, block) => TaskStorageService.guardedToggleBlock(
              file.path,
              expected,
              block,
            ),
        'edit task':
            (expected, block) => TaskStorageService.guardedUpdateBlockText(
              file.path,
              expected,
              block,
              'Edited',
            ),
        'delete task':
            (expected, block) => TaskStorageService.guardedDeleteBlock(
              file.path,
              expected,
              block,
            ),
        'add note':
            (expected, block) => TaskStorageService.guardedAddNote(
              file.path,
              expected,
              block,
              'New context',
            ),
        'add subtask':
            (expected, block) => TaskStorageService.guardedAddSubtask(
              file.path,
              expected,
              block,
              'New child',
            ),
        'edit note':
            (expected, block) => TaskStorageService.guardedUpdateLine(
              file.path,
              expected,
              block.noteLineIndices.single,
              '  edited context',
            ),
        'delete note':
            (expected, block) => TaskStorageService.guardedDeleteLine(
              file.path,
              expected,
              block.noteLineIndices.single,
            ),
      };

      for (final operation in operations.entries) {
        file.writeAsStringSync(before);
        final snapshot =
            (await TaskStorageService.loadSnapshot(file.path)).snapshot!;
        final block =
            TaskStorageService.parseNodes(
              snapshot.lines,
            ).whereType<TaskBlock>().first;
        final external = '$before- [ ] External edit\n';
        file.writeAsStringSync(external);

        final result = await operation.value(snapshot, block);

        expect(
          result.status,
          GuardedTaskMutationStatus.stale,
          reason: operation.key,
        );
        expect(
          result.message,
          'Inbox changed outside Interest. Your change was not applied.',
          reason: operation.key,
        );
        expect(file.readAsStringSync(), external, reason: operation.key);
      }
    });

    test(
      'strict snapshot load reports invalid UTF-8 instead of empty',
      () async {
        file.writeAsBytesSync([0xff, 0xfe, 0xfd]);

        final result = await TaskStorageService.loadSnapshot(file.path);

        expect(result.snapshot, isNull);
        expect(result.error, contains('not valid UTF-8'));
      },
    );

    test(
      'staged install failure restores and verifies exact prior bytes',
      () async {
        final before = <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('# Inbox\r\n\r\n- [ ] Existing\r\n'),
        ];
        file.writeAsBytesSync(before);
        final snapshot =
            (await TaskStorageService.loadSnapshot(file.path)).snapshot!;

        final result = await TaskStorageService.guardedAddTask(
          file.path,
          snapshot,
          'Added',
          operations: _FailStageInstallOperations(),
        );

        expect(result.status, GuardedTaskMutationStatus.unavailable);
        expect(result.message, contains('restored and verified'));
        expect(file.readAsBytesSync(), before);
        expect(temp.listSync().whereType<File>().map((entry) => entry.path), [
          file.path,
        ]);
      },
    );

    test(
      'staged replacement preserves BOM and authored newline bytes',
      () async {
        final before = <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('# Inbox\r\n\r\n- [ ] Existing\n'),
        ];
        file.writeAsBytesSync(before);
        final snapshot =
            (await TaskStorageService.loadSnapshot(file.path)).snapshot!;

        final result = await TaskStorageService.guardedAddTask(
          file.path,
          snapshot,
          'Added',
        );

        expect(result.status, GuardedTaskMutationStatus.applied);
        expect(file.readAsBytesSync(), <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('# Inbox\r\n\r\n- [ ] Existing\n- [ ] Added\r\n'),
        ]);
      },
    );

    test(
      'recovery never overwrites a canonical target that reappeared',
      () async {
        final before = utf8.encode('# Inbox\n\n- [ ] Existing\n');
        final external = utf8.encode('# Inbox\n\n- [ ] External edit\n');
        file.writeAsBytesSync(before);
        final snapshot =
            (await TaskStorageService.loadSnapshot(file.path)).snapshot!;

        final result = await TaskStorageService.guardedAddTask(
          file.path,
          snapshot,
          'Added',
          operations: _ReappearingTargetOperations(external),
        );

        expect(result.status, GuardedTaskMutationStatus.indeterminate);
        expect(file.readAsBytesSync(), external);
        final backups =
            temp
                .listSync()
                .whereType<File>()
                .where((entry) => entry.path.endsWith('.backup'))
                .toList();
        expect(backups, hasLength(1));
        expect(backups.single.readAsBytesSync(), before);
        expect(result.message, contains(backups.single.path));
      },
    );
  });
}

class _FailStageInstallOperations extends GuardedTaskFileOperations {
  var _renameCount = 0;

  @override
  Future<void> rename(String sourcePath, String targetPath) async {
    _renameCount++;
    if (_renameCount == 2) {
      throw FileSystemException('Injected stage install failure', sourcePath);
    }
    await super.rename(sourcePath, targetPath);
  }
}

class _ReappearingTargetOperations extends GuardedTaskFileOperations {
  final List<int> externalBytes;
  var _renameCount = 0;

  _ReappearingTargetOperations(this.externalBytes);

  @override
  Future<void> rename(String sourcePath, String targetPath) async {
    _renameCount++;
    if (_renameCount == 2) {
      await File(targetPath).writeAsBytes(externalBytes, flush: true);
      throw FileSystemException('Injected concurrent replacement', sourcePath);
    }
    await super.rename(sourcePath, targetPath);
  }
}
