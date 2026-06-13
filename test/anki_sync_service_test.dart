import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/resurface/models/resurface_note.dart';
import 'package:people_tracker/features/resurface/services/anki_sync_service.dart';
import 'package:people_tracker/features/resurface/services/anki_transport.dart';

// Locks the transport-agnostic sync core across the AnkiDroid/AnkiConnect
// split: add vs update vs re-add decisions, the anki_note_id write-back, the
// deck move on a category change, the obsidian:// wikilink rewrite, and the
// single-newline → hard-break conversion must behave identically for any
// AnkiTransport implementation.

class FakeTransport implements AnkiTransport {
  int _nextId;
  final Set<int> existingIds = {};
  final List<(String deck, String front, String back, List<String> tags)>
      addCalls = [];
  final List<(int id, String front, String back)> updateCalls = [];

  /// Current deck per note id; seeded by tests and updated by [moveToDeck].
  final Map<int, String> deckByNote = {};
  final List<(int id, String deck)> moveCalls = [];

  /// When set, addNote throws this instead of adding.
  Exception? addThrows;

  FakeTransport({int firstId = 1000}) : _nextId = firstId;

  @override
  String get displayName => 'Fake';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<int> addNote(
      String deckName, String front, String back, List<String> tags) async {
    if (addThrows != null) throw addThrows!;
    addCalls.add((deckName, front, back, tags));
    final id = _nextId++;
    existingIds.add(id);
    deckByNote[id] = deckName;
    return id;
  }

  @override
  Future<bool> updateNote(
      int noteId, String front, String back, List<String> tags) async {
    updateCalls.add((noteId, front, back));
    return true;
  }

  @override
  Future<bool> noteExists(int noteId) async => existingIds.contains(noteId);

  @override
  Future<String?> currentDeck(int noteId) async => deckByNote[noteId];

  @override
  Future<void> moveToDeck(int noteId, String deckName) async {
    moveCalls.add((noteId, deckName));
    deckByNote[noteId] = deckName;
  }
}

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('anki_sync_test');
  });

  tearDown(() => vault.delete(recursive: true));

  /// Writes a problem-note file and returns the matching ResurfaceNote
  /// projection (the shape ResurfaceService would produce).
  Future<ResurfaceNote> problemNote(
    String name, {
    String front = 'Question?',
    String back = 'Answer.',
    String? category,
    String? ankiNoteId,
    List<String> tags = const [],
  }) async {
    final path = p.join(vault.path, '$name.md');
    final fm = StringBuffer('---\n');
    if (category != null) fm.writeln('category: $category');
    if (ankiNoteId != null) fm.writeln('anki_note_id: $ankiNoteId');
    fm.writeln('---');
    await File(path)
        .writeAsString('$fm$front\n\n***\n\n$back\n');
    return ResurfaceNote(
      sourcePath: path,
      sourceFile: '$name.md',
      body: '$front\n\n***\n\n$back',
      isProblemNote: true,
      front: front,
      back: back,
      category: category,
      tags: tags,
      ankiNoteId: ankiNoteId,
    );
  }

  Future<String> fileContent(ResurfaceNote note) =>
      File(note.sourcePath).readAsString();

  group('add / update / re-add decision', () {
    test('note without anki_note_id is added and the id written back',
        () async {
      final transport = FakeTransport();
      final note = await problemNote('Zeno', category: 'Philosophy');

      final result =
          await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(result.added, 1);
      expect(result.failed, 0);
      expect(transport.addCalls.single.$1, 'Philosophy');
      expect(await fileContent(note), contains('anki_note_id: 1000'));
    });

    test('missing category maps to the Default deck', () async {
      final transport = FakeTransport();
      final note = await problemNote('Uncategorized');

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(transport.addCalls.single.$1, 'Default');
    });

    test('existing note is updated, file untouched', () async {
      final transport = FakeTransport()..existingIds.add(555);
      final note = await problemNote('Known', ankiNoteId: '555');
      final before = await fileContent(note);

      final result =
          await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(result.updated, 1);
      expect(transport.addCalls, isEmpty);
      expect(transport.updateCalls.single.$1, 555);
      expect(await fileContent(note), before);
    });

    test('note deleted from Anki is re-added and the id overwritten',
        () async {
      final transport = FakeTransport(firstId: 2000);
      final note = await problemNote('Gone', ankiNoteId: '555');

      final result =
          await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(result.added, 1);
      final content = await fileContent(note);
      expect(content, contains('anki_note_id: 2000'));
      expect(content, isNot(contains('anki_note_id: 555')));
    });

    test('AnkiSyncAbort stops the sync and records the message', () async {
      final transport = FakeTransport()
        ..addThrows = const AnkiSyncAbort('Basic note type not found');
      final a = await problemNote('First');
      final b = await problemNote('Second');

      final result =
          await AnkiSyncService.syncVault(transport, [a, b], vault.path);

      expect(result.errors, ['Basic note type not found']);
      expect(result.added, 0);
      // The abort on the first note prevented any attempt on the second.
      expect(await fileContent(b), isNot(contains('anki_note_id')));
    });

    test('AnkiNoteFailure fails that note and continues', () async {
      final transport = FakeTransport()
        ..addThrows = const AnkiNoteFailure('deck was not found: X');
      final a = await problemNote('Bad');

      final result =
          await AnkiSyncService.syncVault(transport, [a], vault.path);

      expect(result.failed, 1);
      expect(result.errors.single, 'Bad.md: deck was not found: X');
    });
  });

  group('card body rendering', () {
    test('wikilinks become obsidian:// links to the target note', () async {
      final transport = FakeTransport();
      final linker = await problemNote('Linker', front: 'See [[Target]]');

      await AnkiSyncService.syncVault(transport, [linker], vault.path);

      final front = transport.addCalls.single.$2;
      expect(front, contains('obsidian://open?vault='));
      expect(front, contains('file=Target'));
      expect(front, isNot(contains('interest://')));
      expect(front, isNot(contains('anki://')));
    });

    test('a single newline within a block becomes a hard break', () async {
      final transport = FakeTransport();
      final note = await problemNote('Corollaries',
          front:
              'Corollary #1\nInherently insoluble problems are inherently boring.');

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      // Without the hard-break promotion the two lines collapse into one run.
      expect(transport.addCalls.single.$2, contains('<br'));
    });
  });

  group('deck move on category change', () {
    test('card is moved when its deck no longer matches category', () async {
      final transport = FakeTransport()
        ..existingIds.add(555)
        ..deckByNote[555] = 'Old';
      final note =
          await problemNote('Known', ankiNoteId: '555', category: 'New');

      final result =
          await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(result.updated, 1);
      expect(transport.moveCalls.single, (555, 'New'));
    });

    test('no move when the deck already matches the category', () async {
      final transport = FakeTransport()
        ..existingIds.add(555)
        ..deckByNote[555] = 'Philosophy';
      final note = await problemNote('Known',
          ankiNoteId: '555', category: 'Philosophy');

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(transport.moveCalls, isEmpty);
    });

    test('no move when the transport cannot report the current deck', () async {
      // deckByNote unseeded ⇒ currentDeck returns null ⇒ check is skipped.
      final transport = FakeTransport()..existingIds.add(555);
      final note =
          await problemNote('Known', ankiNoteId: '555', category: 'New');

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(transport.moveCalls, isEmpty);
    });
  });
}
