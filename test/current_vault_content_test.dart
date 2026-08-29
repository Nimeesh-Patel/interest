import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/anki/services/anki_problem_note_scanner.dart';
import 'package:people_tracker/features/entities/services/markdown_storage_service.dart';
import 'package:people_tracker/shared/markdown/current_vault_content.dart';

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('current_vault_content_test');
  });

  tearDown(() => vault.delete(recursive: true));

  Future<File> write(String relativePath, String content) async {
    final file = File(p.join(vault.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  const entityProblem =
      '---\ncollection: People\n---\nA current problem?\n***\nA conjecture.\n';

  test(
    'root and Clippings remain explicit current authored surfaces',
    () async {
      final root = await write('Root.md', entityProblem);
      final clipping = await write(
        p.join('Clippings', 'Excerpt.md'),
        entityProblem,
      );

      for (final file in [root, clipping]) {
        expect(
          CurrentVaultContent.isEligible(
            vault.path,
            file.path,
            use: CurrentVaultUse.entity,
          ),
          isTrue,
        );
        expect(
          CurrentVaultContent.isEligible(
            vault.path,
            file.path,
            use: CurrentVaultUse.ankiProblemNote,
          ),
          isTrue,
        );
      }

      final entities = await MarkdownStorageService().loadData(
        vaultPathOverride: vault.path,
      );
      expect(entities.entities.map((entity) => entity.name), {
        'Root',
        'Excerpt',
      });
      expect(entities.errors, isEmpty);

      final cards = await AnkiProblemNoteScanner.scan(vault.path);
      expect(cards.notes.map((note) => note.sourceFile), {
        'Root.md',
        'Excerpt.md',
      });
      expect(cards.errors, isEmpty);
    },
  );

  test(
    'rollback Samay entity and transaction Problem Note are excluded',
    () async {
      await write('Samay Raina.md', entityProblem);
      await write(
        p.join(
          '.perspirator',
          'transactions',
          'rollback-example',
          'originals',
          'Samay Raina.md',
        ),
        '---\ncollection: People\nanki_note_id: 42\n---\nStale?\n***\nStale.\n',
      );

      final entities = await MarkdownStorageService().loadData(
        vaultPathOverride: vault.path,
      );
      expect(entities.entities.map((entity) => entity.name), ['Samay Raina']);
      expect(entities.errors, isEmpty);

      final cards = await AnkiProblemNoteScanner.scan(vault.path);
      expect(cards.notes.map((note) => note.sourceFile), ['Samay Raina.md']);
      expect(cards.errors, isEmpty);
    },
  );

  test(
    'trash templates attachments and system material cannot become current',
    () async {
      final excluded = [
        p.join('.trash', 'Trash.md'),
        p.join('Templates', 'Template.md'),
        p.join('Attachments', 'Embedded.md'),
        p.join('memory', 'Runtime.md'),
        p.join('Interesting', 'System', 'Config.md'),
      ];
      for (final path in excluded) {
        await write(path, entityProblem);
      }

      final entities = await MarkdownStorageService().loadData(
        vaultPathOverride: vault.path,
      );
      expect(entities.entities, isEmpty);
      expect(entities.errors, isEmpty);

      final cards = await AnkiProblemNoteScanner.scan(vault.path);
      expect(cards.notes, isEmpty);
      expect(cards.errors, isEmpty);
    },
  );

  test('duplicate active entity ids are withheld and reported', () async {
    await write(
      'First.md',
      '---\ncollection: People\nalias: shared-person\n---\nFirst.\n',
    );
    await write(
      p.join('Clippings', 'Second.md'),
      '---\ncollection: People\nalias: shared-person\n---\nSecond.\n',
    );

    final result = await MarkdownStorageService().loadData(
      vaultPathOverride: vault.path,
    );

    expect(result.entities, isEmpty);
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('Duplicate active entity id'));
    expect(result.errors.single, contains('First.md'));
    expect(result.errors.single, contains(p.join('Clippings', 'Second.md')));
  });

  test('duplicate active Anki ids stop discovery before mutation', () async {
    await write(
      'First.md',
      '---\nanki_note_id: 123\n---\nFirst?\n***\nFirst.\n',
    );
    await write(
      p.join('Clippings', 'Second.md'),
      '---\nanki_note_id: 123\n---\nSecond?\n***\nSecond.\n',
    );

    final result = await AnkiProblemNoteScanner.scan(vault.path);

    expect(result.isComplete, isFalse);
    expect(result.candidateCount, 2);
    expect(result.conflictedRecords, 2);
    expect(result.notes, isEmpty);
    expect(result.errors.single, contains('Duplicate active anki_note_id'));
  });
}
