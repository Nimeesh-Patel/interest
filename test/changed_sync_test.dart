import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/core/vault_paths.dart';
import 'package:people_tracker/core/vault_service.dart';
import 'package:people_tracker/features/anki/services/anki_sync_controller.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anki_sync_service_test.dart' show FakeTransport;

// The Obsidian button syncs everything changed since Anki last received the
// vault, whoever changed it. These lock that it never syncs less than that,
// and falls back to the whole vault whenever the shortcut could be wrong.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory vault;
  late FakeTransport transport;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('changed_sync_test');
    SharedPreferences.setMockInitialValues({});
    await VaultService.setVaultPath(vault.path);
    transport = FakeTransport();
  });

  tearDown(() => vault.delete(recursive: true));

  File note(String name) => File(p.join(vault.path, '$name.md'));

  Future<void> write(String name, String body, {String front = ''}) =>
      note(name).writeAsString(
        front.isEmpty ? body : '---\n$front---\n$body',
      );

  Future<String?> idOf(String name) async =>
      RegExp(r'anki_note_id: (\d+)')
          .firstMatch(await note(name).readAsString())
          ?.group(1);

  Future<void> edit(String name, String from, String to) async {
    final text = await note(name).readAsString();
    await note(name).writeAsString(text.replaceFirst(from, to));
  }

  /// Three linked notes, synced, with the manifest settled.
  Future<void> settled() async {
    await write('Alpha', 'Alpha?\n\n***\n\nA.\n');
    await write('Beta', 'Beta?\n\n***\n\nB.\n');
    await write('Gamma', 'See [[Alpha]]?\n\n***\n\nG.\n');
    expect((await AnkiSyncController.syncChanged(transport))!.added, 3);
    // Age the files, as notes are between real syncs: a file touched within
    // seconds of a sync is never trusted as settled.
    final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
    for (final name in ['Alpha', 'Beta', 'Gamma']) {
      await note(name).setLastModified(hourAgo);
    }
    final settle = (await AnkiSyncController.syncChanged(transport))!;
    expect(settle.isSuccessful, isTrue);
    transport.updateCalls.clear();
  }

  test('a note untouched since a settled sync is not read again', () async {
    await settled();
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.unchanged + result.updated + result.added, 0);
  });

  test('an edit older than the last sync still counts (Obsidian Sync '
      'delivers other devices\' timestamps)', () async {
    await settled();
    await edit('Beta', 'B.', 'B, edited on the laptop.');
    await note('Beta').setLastModified(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.updated, 1);
  });

  test('with no record yet, the first sync is the whole vault', () async {
    await write('Alpha', 'Alpha?\n\n***\n\nA.\n');
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.added, 1);
    expect(await File(VaultPaths.syncManifest(vault.path)).exists(), isTrue);
  });

  test('every edited note reaches Anki, not only one', () async {
    await settled();
    await edit('Alpha', 'A.', 'A, revised.');
    await edit('Gamma', 'G.', 'G, revised by Perspirator.');
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.isSuccessful, isTrue);
    expect(result.updated, 2);
    expect(result.unchanged, 0, reason: 'unchanged notes are not re-read');
    final updated = transport.updateCalls.map((c) => c.$1).toSet();
    expect(updated, {int.parse((await idOf('Alpha'))!), int.parse((await idOf('Gamma'))!)});
  });

  test('a new note in the vault is created', () async {
    await settled();
    await write('Delta', 'Delta?\n\n***\n\nD.\n');
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.added, 1);
    expect(await idOf('Delta'), isNotNull);
  });

  test('a deleted linked note falls back to the whole vault', () async {
    await settled();
    final beta = int.parse((await idOf('Beta'))!);
    await note('Beta').delete();
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.orphans.map((o) => o.ankiNoteId), [beta]);
  });

  test('a changed alias re-renders the notes that link it', () async {
    await settled();
    await write('Epsilon', 'See [[first letter]]?\n\n***\n\nE.\n');
    await AnkiSyncController.syncChanged(transport);
    await AnkiSyncController.syncChanged(transport);
    transport.updateCalls.clear();
    final text = await note('Alpha').readAsString();
    await note('Alpha').writeAsString(
      text.replaceFirst('---\n', '---\naliases: [first letter]\n'),
    );
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.isSuccessful, isTrue);
    final epsilon = int.parse((await idOf('Epsilon'))!);
    final front = transport.updateCalls.firstWhere((c) => c.$1 == epsilon).$2;
    expect(front, contains('file=Alpha'));
  });

  test('a duplicate identity against an unchanged note is refused', () async {
    await settled();
    final alpha = await idOf('Alpha');
    final gamma = await idOf('Gamma');
    await edit('Gamma', 'anki_note_id: $gamma', 'anki_note_id: $alpha');
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.completed, isFalse);
    expect(result.errors.join(), contains('Duplicate active anki_note_id'));
    expect(transport.updateCalls, isEmpty);
  });

  test('a note that lost its anki_note_id is refused, not re-carded', () async {
    await settled();
    final beta = await idOf('Beta');
    await edit('Beta', 'anki_note_id: $beta\n', '');
    final changed = (await AnkiSyncController.syncChanged(transport))!;
    expect(changed.completed, isFalse);
    expect(changed.errors.single, contains('anki_note_id: $beta'));
    final whole = (await AnkiSyncController.sync(transport))!;
    expect(whole.completed, isFalse, reason: 'the whole-vault sync guards too');
    expect(transport.addCalls, hasLength(3), reason: 'no fresh card was made');
    expect(transport.retireCalls, isEmpty);
  });

  test('an extra card with more history than the linked one is not '
      'removed automatically', () async {
    await settled();
    final beta = int.parse((await idOf('Beta'))!);
    // An older card for Beta, studied 12 times, that the note no longer links.
    final old = transport.stored[beta]!;
    transport.existingIds.add(7);
    transport.stored[7] = AnkiNoteState(
      id: 7,
      front: old.front,
      back: old.back,
      tags: old.tags,
      decks: old.decks,
      reviews: 12,
    );
    final result = (await AnkiSyncController.sync(transport))!;
    expect(result.duplicatesRetired, 0);
    expect(result.orphans.map((o) => o.ankiNoteId), [7]);
    expect(transport.retireCalls, isEmpty);
  });

  test('an unclean run records nothing, so the edit is retried', () async {
    await settled();
    await edit('Beta', 'B.', 'B, revised.');
    transport.snapshotUnavailable = true;
    expect((await AnkiSyncController.syncChanged(transport))!.completed, isFalse);
    transport.snapshotUnavailable = false;
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.updated, 1);
  });
}
