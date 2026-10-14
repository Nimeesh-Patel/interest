import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/shared/markdown/md_io.dart';
import 'package:people_tracker/shared/markdown/markdown_file.dart';
import 'package:people_tracker/features/entities/services/markdown_storage_service.dart';
import 'package:people_tracker/features/entities/models/entity.dart';

class _FailInstallation extends GuardedTaskFileOperations {
  int renames = 0;
  @override
  Future<void> rename(String from, String to) async {
    if (++renames == 2) {
      throw FileSystemException('Injected install failure', from);
    }
    return super.rename(from, to);
  }
}

void main() {
  test(
    'an existing entity with a deleted source cannot be resurrected as an empty note',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'missing_entity_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = MarkdownStorageService();
      await service.loadData(vaultPathOverride: directory.path);
      final path = '${directory.path}${Platform.pathSeparator}Original.md';
      final entity = Entity(
        id: 'original',
        name: 'Original',
        collection: 'People',
        createdAt: 0,
        sourcePath: path,
      );
      expect(await service.saveEntity(entity), isNull);
      expect(await File(path).exists(), isFalse);
    },
  );

  test(
    'invalid entity metadata is reported instead of silently hiding the note',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'invalid_entity_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}Original.md',
      );
      await file.writeAsString(
        '---\ncollection: People\nbroken: [\n---\nSource',
      );
      final data = await MarkdownStorageService().loadData(
        vaultPathOverride: directory.path,
      );
      expect(data.errors, isNotEmpty);
      expect(await file.readAsString(), contains('broken: ['));
    },
  );
  test(
    'metadata patch restores exact authored bytes when staged installation fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'metadata_transaction_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}note.md');
      const source =
          '\uFEFF---\r\ncollection: People\r\nanki_note_id: 42\r\ncustom: untouched\r\n---\r\n\r\n  Authored content.\r\n***\r\nConjecture.\r\n';
      await file.writeAsString(source);
      final patch = await prepareFrontmatterField(
        file.path,
        'anki_note_id',
        null,
      );
      final result = await patch.apply(operations: _FailInstallation());
      expect(result.applied, isFalse);
      expect(await file.readAsBytes(), utf8.encode(source));
      expect(result.error, contains('restored'));
    },
  );

  test(
    'metadata rollback cannot erase progress made after the patch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'metadata_rollback_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}note.md');
      await file.writeAsString('Question\n***\nAnswer');
      final patch = await patchFrontmatterField(
        file.path,
        'anki_note_id',
        '42',
      );
      expect(patch.applied, isTrue);
      final later = '${await file.readAsString()}\nNew idea.';
      await file.writeAsString(later);
      expect(await patch.rollback(), isFalse);
      expect(await file.readAsString(), later);
    },
  );
}
