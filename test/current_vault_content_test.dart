import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/anki/services/anki_problem_note_scanner.dart';
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

  const problem = 'A current problem?\n***\nA conjecture.\n';

  test('root notes and authored subfolders are current', () async {
    for (final path in ['Root.md', p.join('Clippings', 'Excerpt.md')]) {
      final file = await write(path, problem);
      expect(CurrentVaultContent.isEligible(vault.path, file.path), isTrue);
    }
  });

  test(
    'templates, history, trash, attachments, memory and .interest are never current',
    () async {
      for (final path in [
        p.join('Templates', 'Problem Note.md'),
        p.join('Archive', 'templates', 'Old.md'),
        p.join('.perspirator', 'history', 'Note.md'),
        p.join('.trash', 'Gone.md'),
        p.join('Attachments', 'Note.md'),
        p.join('memory', 'Thales', 'Interest.md'),
        p.join('.interest', 'note.md'),
      ]) {
        final file = await write(path, problem);
        expect(
          CurrentVaultContent.isEligible(vault.path, file.path),
          isFalse,
          reason: path,
        );
      }
    },
  );

  test('a blank Problem Note template never becomes a card', () async {
    await write(
      p.join('Templates', 'Problem Note.md'),
      '---\nup: null\ncategory: Default\n---\n\n***',
    );
    final scan = await AnkiProblemNoteScanner.scan(vault.path);
    expect(scan.isComplete, isTrue);
    expect(scan.notes, isEmpty);
  });

  test('paths outside the vault are refused', () async {
    final outside = await Directory.systemTemp.createTemp('outside_vault');
    addTearDown(() => outside.delete(recursive: true));
    final file = File(p.join(outside.path, 'Note.md'));
    await file.writeAsString(problem);
    expect(CurrentVaultContent.isEligible(vault.path, file.path), isFalse);
  });
}
