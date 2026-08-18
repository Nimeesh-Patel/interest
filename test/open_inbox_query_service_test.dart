import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/tasks/services/inbox_storage_service.dart';
import 'package:people_tracker/features/tasks/services/open_inbox_query_service.dart';

void main() {
  late Directory vault;

  setUp(() {
    vault = Directory.systemTemp.createTempSync('interest_inbox_');
  });

  tearDown(() {
    vault.deleteSync(recursive: true);
  });

  test(
    'ensureInbox creates one empty persistent file and preserves it',
    () async {
      final first = await InboxStorageService.ensureInbox(vault.path);
      final path = first.path;
      expect(path, p.join(vault.path, 'Interesting', 'Inbox.md'));
      expect(File(path!).readAsStringSync(), '# Inbox\n\n');

      File(path).writeAsStringSync('# Inbox\n\n- [ ] Existing\n');
      final second = await InboxStorageService.ensureInbox(vault.path);
      expect(second.path, path);
      expect(File(path).readAsStringSync(), '# Inbox\n\n- [ ] Existing\n');
    },
  );

  test('recoverable interrupted transaction refuses empty restart creation',
      () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final backup = File(
      p.join(directory.path, '.Inbox.md.interest_restart_1.backup'),
    )..writeAsStringSync('# Inbox\n\n- [ ] Preserved\n');
    final stage = File(
      p.join(directory.path, '.Inbox.md.interest_restart_1.stage'),
    )..writeAsStringSync('# Inbox\n\n- [ ] Proposed\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, isNull);
    expect(result.error, contains('recoverable interrupted Inbox write'));
    expect(result.error, contains(backup.path));
    expect(result.error, contains(stage.path));
    expect(File(p.join(directory.path, 'Inbox.md')).existsSync(), isFalse);
    expect(backup.readAsStringSync(), '# Inbox\n\n- [ ] Preserved\n');
    expect(stage.readAsStringSync(), '# Inbox\n\n- [ ] Proposed\n');
  });

  test('ambiguous interrupted transactions refuse empty restart creation',
      () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final firstBackup = File(
      p.join(directory.path, '.Inbox.md.interest_restart_1.backup'),
    )..writeAsStringSync('# Inbox\n\n- [ ] First\n');
    final secondBackup = File(
      p.join(directory.path, '.Inbox.md.interest_restart_2.backup'),
    )..writeAsStringSync('# Inbox\n\n- [ ] Second\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, isNull);
    expect(result.error, contains('Ambiguous'));
    expect(result.error, contains(firstBackup.path));
    expect(result.error, contains(secondBackup.path));
    expect(File(p.join(directory.path, 'Inbox.md')).existsSync(), isFalse);
  });

  test('existing canonical Inbox is never replaced during startup', () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final inbox = File(p.join(directory.path, 'Inbox.md'))
      ..writeAsStringSync('# Inbox\n\n- [ ] Canonical\n');
    final backup = File(
      p.join(directory.path, '.Inbox.md.interest_restart_1.backup'),
    )..writeAsStringSync('# Inbox\n\n- [ ] Old\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, inbox.path);
    expect(inbox.readAsStringSync(), '# Inbox\n\n- [ ] Canonical\n');
    expect(backup.readAsStringSync(), '# Inbox\n\n- [ ] Old\n');
  });

  test('empty canonical plus creation marker blocks restart acceptance',
      () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final inbox = File(p.join(directory.path, 'Inbox.md'))..createSync();
    final marker = File(
      p.join(
        directory.path,
        '.Inbox.md.interest_create_restart_1.marker',
      ),
    )..writeAsStringSync('# Inbox\n\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, isNull);
    expect(result.error, contains('empty or partial'));
    expect(result.error, contains(inbox.path));
    expect(result.error, contains(marker.path));
    expect(inbox.readAsBytesSync(), isEmpty);
    expect(marker.readAsStringSync(), '# Inbox\n\n');
  });

  test('partial canonical plus creation marker blocks restart acceptance',
      () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final inbox = File(p.join(directory.path, 'Inbox.md'))
      ..writeAsStringSync('# Inbox\n');
    final marker = File(
      p.join(
        directory.path,
        '.Inbox.md.interest_create_restart_1.marker',
      ),
    )..writeAsStringSync('# Inbox\n\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, isNull);
    expect(result.error, contains(inbox.path));
    expect(result.error, contains(marker.path));
    expect(inbox.readAsStringSync(), '# Inbox\n');
    expect(marker.readAsStringSync(), '# Inbox\n\n');
  });

  test('absent canonical plus creation marker refuses empty recreation',
      () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final inboxPath = p.join(directory.path, 'Inbox.md');
    final marker = File(
      p.join(
        directory.path,
        '.Inbox.md.interest_create_restart_1.marker',
      ),
    )..writeAsStringSync('# Inbox\n\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, isNull);
    expect(result.error, contains(inboxPath));
    expect(result.error, contains(marker.path));
    expect(File(inboxPath).existsSync(), isFalse);
    expect(marker.readAsStringSync(), '# Inbox\n\n');
  });

  test('complete canonical plus creation marker is accepted and cleaned',
      () async {
    final directory = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    final inbox = File(p.join(directory.path, 'Inbox.md'))
      ..writeAsStringSync('# Inbox\n\n');
    final marker = File(
      p.join(
        directory.path,
        '.Inbox.md.interest_create_restart_1.marker',
      ),
    )..writeAsStringSync('# Inbox\n\n');

    final result = await InboxStorageService.ensureInbox(vault.path);

    expect(result.path, inbox.path);
    expect(inbox.readAsStringSync(), '# Inbox\n\n');
    expect(marker.existsSync(), isFalse);
  });

  test(
    'query returns only unchecked Inbox items with authored context',
    () async {
      final inbox =
          File(p.join(vault.path, 'Interesting', 'Inbox.md'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('''# Inbox

## Reading
- [ ] Read Wheeler
  Manhattan Project and scientific culture.
  - [x] Find an edition
  - [ ] Start chapter one
- [x] Read another book
  - [ ] Still unchecked below a completed parent
''');

      final result = await OpenInboxQueryService.query(vault.path);

      expect(result.status, 'complete');
      expect(result.completeness, 'complete');
      expect(result.sourceModifiedAt, isNotNull);
      expect(result.records.map((item) => item.text), [
        'Read Wheeler',
        'Start chapter one',
        'Still unchecked below a completed parent',
      ]);

      final first = result.records.first;
      expect(first.line, 4);
      expect(first.headings, ['Reading']);
      expect(first.parentItems, isEmpty);
      expect(
        first.attachedProse.single.text,
        'Manhattan Project and scientific culture.',
      );

      final nested = result.records[1];
      expect(nested.parentItems, ['Read Wheeler']);
      expect(nested.hasCompletedAncestor, isFalse);
      expect(result.records.last.hasCompletedAncestor, isTrue);

      final json = result.toJson();
      expect(json['provider'], 'interest');
      expect(json['capability'], 'query_open_inbox');
      expect((json['scope'] as Map)['included'], ['Interesting/Inbox.md']);
      expect(
        ((json['scope'] as Map)['outside_scope'] as Map)['handling'],
        'not_scanned',
      );
      expect(json['freshness'], isA<Map>());
      expect(json['records'], isA<List>());
      expect(json['errors'], isEmpty);
      expect(json['limitations'], isNotEmpty);
      expect(
        json.keys,
        containsAll([
          'provider',
          'status',
          'scope',
          'freshness',
          'records',
          'errors',
          'limitations',
        ]),
      );
      expect(inbox.existsSync(), isTrue);
    },
  );

  test('query does not scan or nominate checkboxes outside Inbox', () async {
    final interesting = Directory(p.join(vault.path, 'Interesting'))
      ..createSync(recursive: true);
    File(
      p.join(interesting.path, 'Inbox.md'),
    ).writeAsStringSync('# Inbox\n\n- [ ] Inbox item\n');
    File(p.join(interesting.path, 'Projects', 'Project.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('# Project\n\n- [ ] Project item\n');
    File(
      p.join(vault.path, 'Grexa Logs.md'),
    ).writeAsStringSync('- [ ] Root checkbox\n');

    final result = await OpenInboxQueryService.query(vault.path);

    expect(result.records.map((item) => item.text), ['Inbox item']);
  });

  test('missing Inbox is explicit and query remains read-only', () async {
    final result = await OpenInboxQueryService.query(vault.path);

    expect(result.status, 'unavailable');
    expect(result.completeness, 'unavailable');
    expect(result.records, isEmpty);
    expect(result.errors.single, contains('does not exist'));
    expect(
      File(p.join(vault.path, 'Interesting', 'Inbox.md')).existsSync(),
      isFalse,
    );
  });

  test(
    'mid-read changes return a bounded contract-valid indeterminate result',
    () async {
      final access = _AlternatingInboxFileAccess(
        utf8.encode('# Inbox\n\n- [ ] Alpha\n'),
        utf8.encode('# Inbox\n\n- [ ] Bravo\n'),
      );

      final result = await OpenInboxQueryService.query(
        vault.path,
        fileAccess: access,
      );

      expect(result.status, 'indeterminate');
      expect(result.completeness, 'indeterminate');
      expect(result.sourceModifiedAt, isNull);
      expect(result.records, isEmpty);
      expect(result.errors.single, contains('changed during'));
      expect(access.readCount, 4);
      expect(access.stampCount, 6);

      final json = result.toJson();
      expect(
        json.keys,
        containsAll([
          'provider',
          'capability',
          'status',
          'scope',
          'freshness',
          'records',
          'errors',
        ]),
      );
      expect((json['freshness'] as Map)['source_modified_at'], isNull);
      expect(
        (json['freshness'] as Map)['basis'],
        'no coherent source timestamp was observed',
      );
    },
  );

  test('standalone Dart CLI emits the provider result', () async {
    final ensured = await InboxStorageService.ensureInbox(vault.path);
    File(ensured.path!).writeAsStringSync('# Inbox\n\n- [ ] CLI item\n');

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final dart =
        flutterRoot == null
            ? (Platform.isWindows ? 'dart.bat' : 'dart')
            : p.join(
              flutterRoot,
              'bin',
              Platform.isWindows ? 'dart.bat' : 'dart',
            );
    final process = await Process.run(dart, [
      'run',
      'tool/query_open_inbox.dart',
      '--vault',
      vault.path,
      '--pretty',
    ], workingDirectory: Directory.current.path);

    expect(process.exitCode, 0, reason: process.stderr.toString());
    final json = jsonDecode(process.stdout.toString()) as Map<String, dynamic>;
    expect(json['status'], 'complete');
    expect((json['records'] as List).single['text'], 'CLI item');
  });
}

class _AlternatingInboxFileAccess extends OpenInboxFileAccess {
  final List<int> firstBytes;
  final List<int> secondBytes;
  final DateTime modifiedAt = DateTime.utc(2026, 8, 18, 12);
  var readCount = 0;
  var stampCount = 0;

  _AlternatingInboxFileAccess(this.firstBytes, this.secondBytes)
    : assert(firstBytes.length == secondBytes.length);

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<OpenInboxFileStamp> stamp(String path) async {
    stampCount++;
    return OpenInboxFileStamp(modifiedAt: modifiedAt, size: firstBytes.length);
  }

  @override
  Future<List<int>> readBytes(String path) async {
    readCount++;
    return readCount.isOdd ? List.of(firstBytes) : List.of(secondBytes);
  }
}
