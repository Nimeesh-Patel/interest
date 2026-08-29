import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/anki/models/anki_problem_note.dart';
import 'package:people_tracker/features/anki/services/anki_sync_service.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';

// Locks the transport-agnostic sync core across the AnkiDroid/AnkiConnect
// split: add vs update vs re-add decisions, the anki_note_id write-back, the
// deck move on a category change, the obsidian:// wikilink rewrite, and the
// single-newline → hard-break conversion must behave identically for any
// AnkiTransport implementation.

class FakeTransport extends AnkiTransport {
  int _nextId;
  final Set<int> existingIds = {};
  final List<(String deck, String front, String back, List<String> tags)>
  addCalls = [];
  final List<(int id, String front, String back)> updateCalls = [];

  final List<(int id, String deck)> moveCalls = [];
  bool noteExistsUnavailable = false;
  bool moveSucceeds = true;

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
    String deckName,
    String front,
    String back,
    List<String> tags,
  ) async {
    if (addThrows != null) throw addThrows!;
    addCalls.add((deckName, front, back, tags));
    final id = _nextId++;
    existingIds.add(id);
    return id;
  }

  @override
  Future<bool> updateNote(
    int noteId,
    String front,
    String back,
    List<String> tags,
  ) async {
    updateCalls.add((noteId, front, back));
    return true;
  }

  @override
  Future<bool?> noteExists(int noteId) async =>
      noteExistsUnavailable ? null : existingIds.contains(noteId);

  @override
  Future<bool> moveToDeck(int noteId, String deckName) async {
    moveCalls.add((noteId, deckName));
    return moveSucceeds;
  }
}

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('anki_sync_test');
  });

  tearDown(() => vault.delete(recursive: true));

  /// Writes a problem-note file and returns the matching AnkiProblemNote
  /// projection (the shape AnkiProblemNoteScanner would produce).
  Future<AnkiProblemNote> problemNote(
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
    await File(path).writeAsString('$fm$front\n\n***\n\n$back\n');
    return AnkiProblemNote(
      sourcePath: path,
      sourceFile: '$name.md',
      front: front,
      back: back,
      category: category,
      tags: tags,
      ankiNoteId: ankiNoteId,
    );
  }

  Future<String> fileContent(AnkiProblemNote note) =>
      File(note.sourcePath).readAsString();

  test('Anki declares projection capabilities and correction limits', () {
    final capabilities = FakeTransport().projectionCapabilities;
    expect(capabilities.supports('read'), isTrue);
    expect(capabilities.supports('verify'), isTrue);
    expect(capabilities.supports('retire'), isFalse);
    expect(capabilities.limitation('retire'), contains('no guarded delete'));
  });

  group('add / update / re-add decision', () {
    test(
      'note without anki_note_id is added and the id written back',
      () async {
        final transport = FakeTransport();
        final note = await problemNote('Zeno', category: 'Philosophy');

        final result = await AnkiSyncService.syncVault(transport, [
          note,
        ], vault.path);

        expect(result.added, 1);
        expect(result.failed, 0);
        expect(transport.addCalls.single.$1, 'Philosophy');
        expect(await fileContent(note), contains('anki_note_id: 1000'));
      },
    );

    test('missing category maps to the Default deck', () async {
      final transport = FakeTransport();
      final note = await problemNote('Uncategorized');

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(transport.addCalls.single.$1, 'Default');
    });

    test(
      'external create plus failed local id patch is reported partial',
      () async {
        final transport = FakeTransport(firstId: 2100);
        final note = await problemNote('Vanished');
        await File(note.sourcePath).delete();

        final result = await AnkiSyncService.syncVault(transport, [
          note,
        ], vault.path);

        expect(result.added, 0);
        expect(result.failed, 1);
        expect(result.errors.single, contains('Anki note 2100 was created'));
        expect(result.errors.single, contains('local identity patch failed'));
      },
    );

    test('existing note is updated, file untouched', () async {
      final transport = FakeTransport()..existingIds.add(555);
      final note = await problemNote('Known', ankiNoteId: '555');
      final before = await fileContent(note);

      final result = await AnkiSyncService.syncVault(transport, [
        note,
      ], vault.path);

      expect(result.updated, 1);
      expect(transport.addCalls, isEmpty);
      expect(transport.updateCalls.single.$1, 555);
      expect(await fileContent(note), before);
    });

    test('note deleted from Anki is re-added and the id overwritten', () async {
      final transport = FakeTransport(firstId: 2000);
      final note = await problemNote('Gone', ankiNoteId: '555');

      final result = await AnkiSyncService.syncVault(transport, [
        note,
      ], vault.path);

      expect(result.added, 1);
      final content = await fileContent(note);
      expect(content, contains('anki_note_id: 2000'));
      expect(content, isNot(contains('anki_note_id: 555')));
    });

    test('AnkiSyncAbort stops the sync and records the message', () async {
      final transport =
          FakeTransport()
            ..addThrows = const AnkiSyncAbort('Basic note type not found');
      final a = await problemNote('First');
      final b = await problemNote('Second');

      final result = await AnkiSyncService.syncVault(transport, [
        a,
        b,
      ], vault.path);

      expect(result.errors, ['First.md: Basic note type not found']);
      expect(result.added, 0);
      expect(result.failed, 1);
      expect(result.skipped, 1);
      expect(result.completed, isFalse);
      // The abort on the first note prevented any attempt on the second.
      expect(await fileContent(b), isNot(contains('anki_note_id')));
    });

    test('AnkiNoteFailure fails that note and continues', () async {
      final transport =
          FakeTransport()
            ..addThrows = const AnkiNoteFailure('deck was not found: X');
      final a = await problemNote('Bad');

      final result = await AnkiSyncService.syncVault(transport, [
        a,
      ], vault.path);

      expect(result.failed, 1);
      expect(result.errors.single, 'Bad.md: deck was not found: X');
    });

    test('unavailable identity observation does not re-add the note', () async {
      final transport = FakeTransport()..noteExistsUnavailable = true;
      final note = await problemNote('Unknown', ankiNoteId: '555');

      final result = await AnkiSyncService.syncVault(transport, [
        note,
      ], vault.path);

      expect(result.failed, 1);
      expect(result.errors.single, contains('could not verify whether'));
      expect(transport.addCalls, isEmpty);
      expect(transport.updateCalls, isEmpty);
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

    test('a wikilink to an alias resolves to the canonical note', () async {
      // Equivalent of the retired anki_sync.py alias test: [[speed of
      // progress]] must reach the note that declares the alias, not a
      // non-existent note of that name.
      File(
        p.join(vault.path, 'rapid explanatory progress.md'),
      ).writeAsStringSync(
        '---\naliases:\n  - speed of progress\n---\nq\n***\na\n',
      );
      final transport = FakeTransport();
      final note = await problemNote(
        'Cites',
        front: 'See [[speed of progress]]',
      );

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      final front = transport.addCalls.single.$2;
      expect(front, contains('file=rapid%20explanatory%20progress'));
      expect(front, isNot(contains('file=speed%20of%20progress')));
    });

    test('a single newline within a block becomes a hard break', () async {
      final transport = FakeTransport();
      final note = await problemNote(
        'Corollaries',
        front:
            'Corollary #1\nInherently insoluble problems are inherently boring.',
      );

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      // Without the hard-break promotion the two lines collapse into one run.
      expect(transport.addCalls.single.$2, contains('<br'));
    });
  });

  group('deck move on category change', () {
    test('category deck is projected for every existing note', () async {
      final transport = FakeTransport()..existingIds.add(555);
      final note = await problemNote(
        'Known',
        ankiNoteId: '555',
        category: 'New',
      );

      final result = await AnkiSyncService.syncVault(transport, [
        note,
      ], vault.path);

      expect(result.updated, 1);
      expect(transport.moveCalls.single, (555, 'New'));
    });

    test('default deck is projected when category is absent', () async {
      final transport = FakeTransport()..existingIds.add(555);
      final note = await problemNote('Known', ankiNoteId: '555');

      await AnkiSyncService.syncVault(transport, [note], vault.path);

      expect(transport.moveCalls.single, (555, 'Default'));
    });

    test('a failed requested deck move is not counted as an update', () async {
      final transport =
          FakeTransport()
            ..existingIds.add(555)
            ..moveSucceeds = false;
      final note = await problemNote(
        'Known',
        ankiNoteId: '555',
        category: 'New',
      );

      final result = await AnkiSyncService.syncVault(transport, [
        note,
      ], vault.path);

      expect(result.updated, 0);
      expect(result.failed, 1);
      expect(
        result.errors.single,
        'Known.md: content updated, but deck projection to "New" failed',
      );
    });
  });
}
