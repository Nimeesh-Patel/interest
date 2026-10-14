import 'package:flutter/material.dart';
import 'package:people_tracker/features/projects/screens/project_list_detail_screen.dart';
import 'package:people_tracker/shared/markdown/markdown_file.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/features/projects/services/project_list_document.dart';
import 'package:people_tracker/features/projects/services/project_storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  late File file;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('project_source_');
    file = File(p.join(temporary.path, 'Original.md'));
  });
  tearDown(() => temporary.delete(recursive: true));
  Future<ProjectListDocument> load() async => ProjectListDocument.parse(
    (await MarkdownFile.loadSnapshot(file.path)).snapshot!,
    'Fallback',
  );

  testWidgets('rename followed by a UI edit uses the new file path', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await file.writeAsString('---\ntype: list\n---\n# Original\n\n- First\n');
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectListDetailScreen(filePath: file.path, title: 'Original'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(await file.exists(), isFalse);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edited');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(await file.exists(), isFalse);
      expect(
        await File(p.join(temporary.path, 'Renamed.md')).readAsString(),
        contains('- Edited'),
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  test(
    'editing preserves arbitrary metadata, prose, code examples, BOM and CRLF',
    () async {
      const source =
          '\uFEFF---\r\ntype: list\r\ncustom:\r\n  value: exact\r\n---\r\n# Original\r\n\r\nContext stays.\r\n\r\n```text\r\n- quoted example\r\n```\r\n\r\n- First\r\n- Second\r\n';
      await file.writeAsString(source);
      final document = await load();
      expect(document.items, ['First', 'Second']);
      expect((await document.edit(file.path, 0, 'Changed')).applied, isTrue);
      expect(
        await file.readAsBytes(),
        utf8.encode(source.replaceFirst('- First', '- Changed')),
      );
    },
  );

  test(
    'stale edits and ambiguous removals do not discard source content',
    () async {
      const source =
          '# Original\n\n- First\n  Attached explanation.\n- Second\n';
      await file.writeAsString(source);
      final document = await load();
      expect((await document.delete(file.path, 0)).applied, isFalse);
      expect((await document.reorder(file.path, 0, 1)).applied, isFalse);
      expect(await file.readAsString(), source);
      await file.writeAsString('$source\nA later idea.');
      expect((await document.edit(file.path, 1, 'Changed')).applied, isFalse);
      expect(await file.readAsString(), '$source\nA later idea.');
    },
  );

  test(
    'ordinary flat-list add, reorder and delete keep the source shell',
    () async {
      const source =
          '---\ntype: list\nextra: preserved\n---\n# Original\n\nContext\n\n- First\n- Second\n';
      await file.writeAsString(source);
      expect((await (await load()).reorder(file.path, 0, 1)).applied, isTrue);
      expect(
        await file.readAsString(),
        source.replaceFirst('- First\n- Second', '- Second\n- First'),
      );
      expect((await (await load()).add(file.path, 'Third')).applied, isTrue);
      expect((await (await load()).delete(file.path, 0)).applied, isTrue);
      expect(
        await file.readAsString(),
        contains('extra: preserved\n---\n# Original\n\nContext'),
      );
    },
  );

  test(
    'rename collision leaves source and destination bytes untouched',
    () async {
      const source =
          '\uFEFF---\r\ntype: list\r\n---\r\n# Original\r\n- First\r\n';
      await file.writeAsString(source);
      final target = File(p.join(temporary.path, 'Taken.md'))
        ..writeAsStringSync('Another project');
      expect(
        await ProjectStorageService.renameProject(file.path, 'Taken'),
        isNull,
      );
      expect(await file.readAsBytes(), utf8.encode(source));
      expect(await target.readAsString(), 'Another project');
    },
  );

  test(
    'renamed project keeps exact bytes except its title and saves to the new path',
    () async {
      const source = '\uFEFF# Original\r\n\r\n- First\r\n';
      await file.writeAsString(source);
      final renamed = await ProjectStorageService.renameProject(
        file.path,
        'Renamed',
      );
      expect(renamed, isNotNull);
      expect(await file.exists(), isFalse);
      final newFile = File(renamed!);
      expect(
        await newFile.readAsBytes(),
        utf8.encode(source.replaceFirst('# Original', '# Renamed')),
      );
      final document = ProjectListDocument.parse(
        (await MarkdownFile.loadSnapshot(renamed)).snapshot!,
        '',
      );
      expect((await document.edit(renamed, 0, 'Edited')).applied, isTrue);
      expect(await file.exists(), isFalse);
      expect(await newFile.readAsString(), contains('- Edited'));
    },
  );
}
