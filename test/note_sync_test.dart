import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/core/vault_paths.dart';
import 'package:people_tracker/features/anki/services/anki_problem_note_scanner.dart';
import 'package:people_tracker/features/anki/services/anki_sync_service.dart';
import 'package:people_tracker/shared/markdown/link_target_cache.dart';

import 'anki_sync_service_test.dart' show FakeTransport;

// The edit cycle: one note changed in Obsidian is synced on its own. These
// lock what that shortcut may and may not skip.

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('note_sync_test');
  });

  tearDown(() => vault.delete(recursive: true));

  Future<String> write(String relative, String content) async {
    final file = File(p.join(vault.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file.path;
  }

  test('scanPaths reads only the named note', () async {
    final edited = await write('Edited.md', 'Why?\n\n***\n\nBecause.\n');
    await write('Other.md', 'Other?\n\n***\n\nOther.\n');
    final scanned = await AnkiProblemNoteScanner.scanPaths(vault.path, [
      edited,
    ]);
    expect(scanned.isComplete, isTrue);
    expect(scanned.notes.map((n) => n.sourceFile), ['Edited.md']);
  });

  test('scanPaths refuses what is not a current note of the vault', () async {
    final memory = await write(
      p.join('memory', 'Agent.md'),
      'Why?\n\n***\n\nNo.\n',
    );
    final missing = p.join(vault.path, 'Not yet synced.md');
    final scanned = await AnkiProblemNoteScanner.scanPaths(vault.path, [
      memory,
      missing,
    ]);
    expect(scanned.isComplete, isFalse);
    expect(scanned.errors, hasLength(2));
    expect(scanned.notes, isEmpty);
  });

  test('a whole-vault sync caches link targets for one-note syncs', () async {
    await write(
      'Speed of progress is moral.md',
      '---\naliases: [speed of progress]\n---\nWhy?\n\n***\n\nBecause.\n',
    );
    final scanned = await AnkiProblemNoteScanner.scan(vault.path);
    await AnkiSyncService.syncVault(
      FakeTransport(),
      scanned.notes,
      vault.path,
      reconcileCollection: true,
    );
    expect(await File(VaultPaths.linkTargets(vault.path)).exists(), isTrue);

    final targets = await LinkTargetCache.forTexts(vault.path, [
      'See [[speed of progress]] and [[Unknown]].',
    ]);
    expect(targets, {'speed of progress': 'Speed of progress is moral'});
  });

  test('a cached target whose note is gone is not used', () async {
    final target = await write('Renamed later.md', 'A note.\n');
    await LinkTargetCache.save(vault.path, {'alias': 'Renamed later'});
    await File(target).delete();
    final targets = await LinkTargetCache.forTexts(vault.path, [
      'Links [[alias]].',
    ]);
    expect(targets, isEmpty);
  });

  test('a note without wikilinks reads no cache and no vault', () async {
    final targets = await LinkTargetCache.forTexts(vault.path, ['No links.']);
    expect(targets, isEmpty);
    expect(await File(VaultPaths.linkTargets(vault.path)).exists(), isFalse);
  });

  test(
    'a one-note sync renders supplied aliases and never judges other cards',
    () async {
      final edited = await write(
        'Edited.md',
        '---\nanki_note_id: 42\n---\nSee [[alias]]?\n\n***\n\nYes.\n',
      );
      final transport = FakeTransport()..existingIds.addAll({42, 77});
      final scanned = await AnkiProblemNoteScanner.scanPaths(vault.path, [
        edited,
      ]);
      final result = await AnkiSyncService.syncVault(
        transport,
        scanned.notes,
        vault.path,
        linkTargets: {'alias': 'Folder/Target'},
      );
      expect(result.isSuccessful, isTrue);
      expect(result.updated, 1);
      expect(result.orphans, isEmpty);
      expect(transport.retireCalls, isEmpty);
      expect(transport.updateCalls.single.$2, contains('Folder%2FTarget'));
    },
  );
}
