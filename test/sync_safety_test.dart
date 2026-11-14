import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/core/vault_paths.dart';
import 'package:people_tracker/core/vault_service.dart';
import 'package:people_tracker/features/anki/services/anki_sync_controller.dart';
import 'package:people_tracker/features/anki/services/anki_sync_service.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';
import 'package:people_tracker/features/anki/services/sync_manifest.dart';
import 'package:people_tracker/features/sync/decision_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anki_sync_service_test.dart' show FakeTransport;

// Each test reproduces one way the sync could lose review history, or say
// more than it knows, and locks the guard that prevents it:
// 1. a note claiming a card made from another, existing note;
// 2. automatic removal of an extra card, regardless of its counter;
// 3. a quick sync missing work: a card number it just wrote, a card changed
//    on the Anki side, a link that now reaches a different note;
// and the two answers to a lost card number.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory vault;
  late FakeTransport transport;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('sync_safety_test');
    SharedPreferences.setMockInitialValues({});
    await VaultService.setVaultPath(vault.path);
    transport = FakeTransport();
  });

  tearDown(() => vault.delete(recursive: true));

  File note(String name) => File(p.join(vault.path, '$name.md'));

  Future<void> write(String name, String body) async {
    await note(name).parent.create(recursive: true);
    await note(name).writeAsString(body);
  }

  Future<String?> idOf(String name) async => RegExp(
    r'anki_note_id: (\d+)',
  ).firstMatch(await note(name).readAsString())?.group(1);

  Future<int> cardOf(String name) async => int.parse((await idOf(name))!);

  Future<void> edit(String name, String from, String to) async {
    final text = await note(name).readAsString();
    expect(text.contains(from), isTrue, reason: '$name should contain $from');
    await note(name).writeAsString(text.replaceFirst(from, to));
  }

  /// Ages every note, as notes are between real syncs, then syncs once so the
  /// manifest is settled.
  Future<void> settle() async {
    final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entity in vault.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.md')) {
        await entity.setLastModified(hourAgo);
      }
    }
    final result = (await AnkiSyncController.syncChanged(transport))!;
    expect(result.isSuccessful, isTrue, reason: result.errors.join('\n'));
    transport.updateCalls.clear();
    transport.addCalls.clear();
  }

  /// Three linked notes, synced, with the manifest settled.
  Future<void> settled() async {
    await write('Alpha', 'Alpha?\n\n***\n\nA.\n');
    await write('Beta', 'Beta?\n\n***\n\nB.\n');
    await write('Gamma', 'See [[Alpha]]?\n\n***\n\nG.\n');
    expect((await AnkiSyncController.syncChanged(transport))!.added, 3);
    await settle();
  }

  void setCard(int id, {String? front, int? reviews}) {
    final old = transport.stored[id]!;
    transport.stored[id] = AnkiNoteState(
      id: id,
      front: front ?? old.front,
      back: old.back,
      tags: old.tags,
      decks: old.decks,
      reviews: reviews ?? old.reviews,
    );
  }

  /// A second card made from [name], with [reviews], that the note does not
  /// link: what a crash between creating a card and writing its number into
  /// the note leaves behind.
  Future<int> extraCardFor(String name, {required int reviews}) async {
    final linked = transport.stored[await cardOf(name)]!;
    const id = 7;
    transport.existingIds.add(id);
    transport.stored[id] = AnkiNoteState(
      id: id,
      front: linked.front,
      back: linked.back,
      tags: linked.tags,
      decks: linked.decks,
      reviews: reviews,
    );
    return id;
  }

  group('1. a card made from another note', () {
    /// "Straw" claims Alpha's card while Alpha still exists. The manifest is
    /// forgotten, so the lost-identity guard cannot catch it first: this is
    /// the backstop.
    Future<(int, AnkiSyncResult)> claim() async {
      await settled();
      final card = await cardOf('Alpha');
      await edit('Alpha', 'anki_note_id: $card\n', '');
      await write(
        'Straw',
        '---\nanki_note_id: $card\n---\nStraw?\n\n***\n\nS.\n',
      );
      await SyncManifest.forget(vault.path);
      return (card, (await AnkiSyncController.sync(transport))!);
    }

    test('is not overwritten: the note claiming it is skipped', () async {
      final (card, result) = await claim();
      expect(result.completed, isTrue);
      expect(result.isSuccessful, isFalse);
      final issue = result.issues.single;
      expect(issue.kind, AnkiIssueKind.foreignCard);
      expect(issue.notes, ['Straw', 'Alpha']);
      expect(issue.cardId, card);
      expect(issue.cardSource, 'Alpha');
      expect(issue.cardProblem, contains('Alpha?'));
      expect(transport.updateCalls.map((c) => c.$1), isNot(contains(card)));
      expect(transport.stored[card]!.front, contains('Alpha?'));
    });

    test('moves to the note only when Nimeesh confirms it', () async {
      final (card, result) = await claim();
      final moved =
          (await AnkiSyncController.resolve(
            transport,
            reassign: [result.issues.single],
          ))!;
      expect(moved.isSuccessful, isTrue, reason: moved.errors.join('\n'));
      expect(transport.stored[card]!.front, contains('file=Straw'));
      expect(transport.stored[card]!.front, contains('Straw?'));
      final again = (await AnkiSyncController.sync(transport))!;
      expect(again.issues, isEmpty, reason: again.errors.join('\n'));
    });

    test('is not moved if the card changed since it was shown', () async {
      final (card, result) = await claim();
      setCard(
        card,
        front: transport.stored[card]!.front.replaceAll('Alpha', 'Beta'),
      );
      final moved =
          (await AnkiSyncController.resolve(
            transport,
            reassign: [result.issues.single],
          ))!;
      expect(moved.isSuccessful, isFalse);
      expect(transport.stored[card]!.front, isNot(contains('Straw?')));
    });

    test('a name with an apostrophe is read whole', () async {
      // Found on the phone: the card link of "The Pattern's cause" was read
      // up to the apostrophe, as "The Pattern", another existing note.
      await write('The Pattern', 'What is the Pattern?\n\n***\n\nP.\n');
      await write("The Pattern's cause", 'What causes it?\n\n***\n\nC.\n');
      expect((await AnkiSyncController.sync(transport))!.added, 2);
      final again = (await AnkiSyncController.sync(transport))!;
      expect(again.isSuccessful, isTrue, reason: again.errors.join('\n'));
      expect(again.issues, isEmpty);
      final card = await cardOf("The Pattern's cause");
      await note("The Pattern's cause").delete();
      final orphaned = (await AnkiSyncController.sync(transport))!;
      expect(orphaned.orphans.single.ankiNoteId, card);
      expect(orphaned.orphans.single.noteName, "The Pattern's cause");
    });

    test('a renamed note keeps its card', () async {
      await settled();
      final card = await cardOf('Alpha');
      await note('Alpha').rename(p.join(vault.path, 'Alpha renamed.md'));
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.isSuccessful, isTrue, reason: result.errors.join('\n'));
      expect(transport.stored[card]!.front, contains('file=Alpha%20renamed'));
    });

    test('a note renamed only in case keeps its card', () async {
      await settled();
      final card = await cardOf('Alpha');
      final temp = p.join(vault.path, 'tmp.md');
      await note('Alpha').rename(temp);
      await File(temp).rename(p.join(vault.path, 'alpha.md'));
      final result = (await AnkiSyncController.sync(transport))!;
      expect(result.isSuccessful, isTrue, reason: result.errors.join('\n'));
      expect(transport.stored[card]!.front, contains('file=alpha'));
    });
  });

  test(
    'duplicates always wait for confirmation, including a zero counter',
    () async {
      await settled();
      final linked = await cardOf('Beta');
      setCard(linked, reviews: 10);
      for (final counter in [0, 3]) {
        final extra = await extraCardFor('Beta', reviews: counter);
        final result = (await AnkiSyncController.sync(transport))!;
        expect(
          result.orphans.any(
            (card) => card.ankiNoteId == extra && card.noteLinks == linked,
          ),
          isTrue,
        );
        expect(transport.retireCalls, isEmpty);
      }
    },
  );

  group('3. the quick sync', () {
    test('protects a card number it has just written', () async {
      await settled();
      await write('Delta', 'Delta?\n\n***\n\nD.\n');
      expect((await AnkiSyncController.syncChanged(transport))!.added, 1);
      final card = await cardOf('Delta');
      await edit('Delta', 'anki_note_id: $card\n', '');
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.completed, isFalse);
      expect(result.issues.single.kind, AnkiIssueKind.lostIdentity);
      expect(result.issues.single.cardId, card);
      expect(transport.addCalls, hasLength(1), reason: 'no second card');
    });

    test('notices a card deleted in Anki', () async {
      await settled();
      final card = await cardOf('Beta');
      transport.existingIds.remove(card);
      transport.stored.remove(card);
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.missing.map((m) => m.ankiNoteId), [card]);
    });

    test('puts back a card edited in Anki', () async {
      await settled();
      final card = await cardOf('Alpha');
      setCard(card, front: 'Edited in AnkiDroid');
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.updated, 1);
      expect(transport.stored[card]!.front, contains('Alpha?'));
    });

    test('re-draws a card whose link now reaches a new note', () async {
      await write('Gamma', 'See [[Delta]]?\n\n***\n\nG.\n');
      expect((await AnkiSyncController.syncChanged(transport))!.added, 1);
      await settle();
      final gamma = await cardOf('Gamma');
      expect(transport.stored[gamma]!.front, contains('file=Delta"'));
      await write(p.join('sub', 'Delta'), 'Delta?\n\n***\n\nD.\n');
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.isSuccessful, isTrue, reason: result.errors.join('\n'));
      expect(transport.stored[gamma]!.front, contains('file=sub%2FDelta'));
    });

    test('re-draws a card whose link stops reaching a deleted note', () async {
      await write('Gamma', 'See [[Delta]]?\n\n***\n\nG.\n');
      await write(p.join('sub', 'Delta'), 'Just a note.\n');
      expect((await AnkiSyncController.syncChanged(transport))!.added, 1);
      await settle();
      final gamma = await cardOf('Gamma');
      expect(transport.stored[gamma]!.front, contains('file=sub%2FDelta'));
      await note(p.join('sub', 'Delta')).delete();
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.isSuccessful, isTrue, reason: result.errors.join('\n'));
      expect(transport.stored[gamma]!.front, contains('file=Delta"'));
    });

    test(
      'a moved criticism target redraws the answer with the existing card ID',
      () async {
        await write(
          'Gamma',
          '---\ncriticisms:\n  - "[[Objection]]"\n---\nQ\n***\nA\n',
        );
        await write('Objection', 'An objection without its own card.');
        expect((await AnkiSyncController.syncChanged(transport))!.added, 1);
        await settle();
        final card = await cardOf('Gamma');
        expect(transport.stored[card]!.back, contains('file=Objection"'));
        await note(p.join('Research', 'Objection')).parent.create();
        await note(
          'Objection',
        ).rename(note(p.join('Research', 'Objection')).path);
        final result = (await AnkiSyncController.syncChanged(transport))!;
        expect(result.updated, 1, reason: result.errors.join('\n'));
        expect(await cardOf('Gamma'), card);
        expect(
          transport.stored[card]!.back,
          contains('file=Research%2FObjection'),
        );
        expect(transport.addCalls, isEmpty);
      },
    );

    test(
      'an upgrade rescans without forgetting recorded card identity',
      () async {
        await settled();
        final card = await cardOf('Beta');
        final file = File(VaultPaths.syncManifest(vault.path));
        final raw = jsonDecode(await file.readAsString()) as Map;
        raw['v'] = 2;
        await file.writeAsString(jsonEncode(raw));
        await edit('Beta', 'anki_note_id: $card\n', '');
        final result = (await AnkiSyncController.syncChanged(transport))!;
        expect(result.issues.single.cardId, card);
        expect(transport.addCalls, isEmpty);
        expect((await SyncManifest.load(vault.path))!.quickReady, isFalse);
        expect(
          await AnkiSyncController.restoreIdentity(result.issues.single),
          isNull,
        );
        final rebuilt = (await AnkiSyncController.syncChanged(transport))!;
        expect(rebuilt.isSuccessful, isTrue);
        expect(rebuilt.checkedWholeVault, isTrue);
        expect((await SyncManifest.load(vault.path))!.quickReady, isTrue);
        expect(
          (await AnkiSyncController.syncChanged(transport))!.checkedWholeVault,
          isFalse,
        );
      },
    );
  });

  group('a lost card number', () {
    Future<(int, AnkiSyncIssue)> lose() async {
      await settled();
      final card = await cardOf('Beta');
      setCard(card, reviews: 5);
      await edit('Beta', 'anki_note_id: $card\n', '');
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.completed, isFalse);
      final issue = result.issues.single;
      expect(issue.kind, AnkiIssueKind.lostIdentity);
      expect(issue.cardReviews, 5, reason: 'the card at stake is shown');
      return (card, issue);
    }

    test(
      'an older decision cannot restore or release a replacement ID',
      () async {
        final (card, issue) = await lose();
        expect(await AnkiSyncController.releaseIdentity(issue), isNull);
        expect((await AnkiSyncController.syncChanged(transport))!.added, 1);
        final replacement = await cardOf('Beta');
        expect(replacement, isNot(card));
        await edit('Beta', 'anki_note_id: $replacement\n', '');
        expect(await AnkiSyncController.releaseIdentity(issue), isNotNull);
        expect(await AnkiSyncController.restoreIdentity(issue), isNotNull);
        final result = (await AnkiSyncController.syncChanged(transport))!;
        expect(result.issues.single.cardId, replacement);
      },
    );

    test('can be put back, keeping the card', () async {
      final (card, issue) = await lose();
      expect(await AnkiSyncController.restoreIdentity(issue), isNull);
      expect(await cardOf('Beta'), card);
      final result = (await AnkiSyncController.syncChanged(transport))!;
      expect(result.isSuccessful, isTrue, reason: result.errors.join('\n'));
      expect(transport.addCalls, isEmpty);
    });

    test(
      'can be released: a new card, and the old one is asked about',
      () async {
        final (card, issue) = await lose();
        expect(await AnkiSyncController.releaseIdentity(issue), isNull);
        final result = (await AnkiSyncController.syncChanged(transport))!;
        expect(result.added, 1, reason: result.errors.join('\n'));
        final fresh = await cardOf('Beta');
        final whole = (await AnkiSyncController.sync(transport))!;
        expect(whole.orphans.single.ankiNoteId, card);
        expect(whole.orphans.single.noteLinks, fresh);
        expect(transport.retireCalls, isEmpty, reason: '5 reviews are kept');
      },
    );
  });

  group('the cards that show a problem', () {
    test('two notes with one card number', () {
      final d = Decision.issue(
        const AnkiSyncIssue(
          kind: AnkiIssueKind.sharedCard,
          message: 'shared',
          notes: ['Ad Hominem', 'Logic/Ad Hominem 1'],
          cardId: 1700000000000,
          cardSource: 'Ad Hominem',
          cardProblem: 'What is ad hominem?',
          cardReviews: 9,
        ),
      );
      expect(d.reason, 'Two notes claim one card');
      expect(d.title, 'Ad Hominem');
      expect(d.explanation, contains('"Ad Hominem" and "Ad Hominem 1" both'));
      expect(d.explanation, contains('The card was made from "Ad Hominem"'));
      expect(d.history, 'Reviewed 9 times');
      expect(d.hasChoice, isFalse, reason: 'fixed in Obsidian');
      expect(d.notes, hasLength(2));
    });

    test('a note claiming another note\'s card', () {
      final d = Decision.issue(
        const AnkiSyncIssue(
          kind: AnkiIssueKind.foreignCard,
          message: 'foreign',
          notes: ['Straw Man', 'Ad Hominem'],
          cardId: 1700000000000,
          cardSource: 'Ad Hominem',
        ),
      );
      expect(d.reason, "This note claims another note's card");
      expect(d.title, 'Straw Man');
      expect(
        d.explanation,
        contains('made from "Ad Hominem", which still exists'),
      );
      expect(d.actLabel, 'Move card here');
      expect(d.keepLabel, 'Not now');
      expect(d.notes, ['Straw Man', 'Ad Hominem']);
    });
  });

  test('a fingerprint ignores tag order and deck case, nothing else', () {
    final a = cardFingerprint('F', 'B', ['x', 'y'], ['Logic']);
    expect(cardFingerprint('F', 'B', ['y', 'x'], ['logic']), a);
    expect(cardFingerprint('F', 'B!', ['x', 'y'], ['Logic']), isNot(a));
    expect(cardFingerprint('F', 'B', ['x'], ['Logic']), isNot(a));
    expect(cardFingerprint('F', 'B', ['x', 'y'], ['Other']), isNot(a));
    expect(a, hasLength(16));
  });
}
