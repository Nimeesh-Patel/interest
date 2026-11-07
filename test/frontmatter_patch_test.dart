import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/shared/markdown/frontmatter_patch.dart';
import 'package:people_tracker/shared/markdown/md_io.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('ID write preserves exact UTF-8 body and unrelated metadata', () async {
    final dir = await Directory.systemTemp.createTemp('identity-preservation-');
    addTearDown(() => dir.delete(recursive: true));
    for (final eol in ['\n', '\r\n']) {
      final body =
          '$eol    indented code$eol\tmore code$eol$eol***$eolα answer  $eol';
      final original =
          '\uFEFF---$eol# keep${eol}custom:$eol  nested: [true, 2]$eol---$eol$body';
      final file = File('${dir.path}/note.md');
      await file.writeAsBytes(utf8.encode(original));
      final result = await patchFrontmatterField(
        file.path,
        'anki_note_id',
        '123',
      );
      expect(result.applied, isTrue, reason: result.error);
      expect(
        await file.readAsBytes(),
        utf8.encode(
          original.replaceFirst(
            '---$eol$body',
            'anki_note_id: 123$eol---$eol$body',
          ),
        ),
      );
    }
  });

  test('file without metadata retains all leading body whitespace', () {
    const body = '\n    code\n***\nanswer\n';
    expect(
      patchFrontmatterText(body, {'anki_note_id': '123'}),
      '---\nanki_note_id: 123\n---\n$body',
    );
  });

  test('block sequence patch keeps following comments and unowned keys', () {
    const before =
        '---\ntags:\n  - old\n# keep for custom\ncustom: 2\n---\nbody';
    expect(
      patchFrontmatterText(before, {'tags': '[new]'}),
      '---\ntags: [new]\n# keep for custom\ncustom: 2\n---\nbody',
    );
  });

  test('quoted keys are patched rather than duplicated', () {
    expect(
      patchFrontmatterText('---\n"anki_note_id": 1 # keep\n---\nbody', {
        'anki_note_id': '2',
      }),
      '---\n"anki_note_id": 2 # keep\n---\nbody',
    );
  });

  test('null field removal leaves unowned comments and body', () {
    final after = patchFrontmatterText(
      '---\nscore:\ntags: []\n# keep\n---\nbody',
      {'score': null, 'tags': null},
    );
    expect(after, isNot(contains('score:')));
    expect(after, isNot(contains('tags:')));
    expect(after, endsWith('# keep\n---\nbody'));
  });

  test(
    'malformed metadata refuses an ID write without changing file',
    () async {
      final dir = await Directory.systemTemp.createTemp('invalid-metadata-');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/note.md');
      const original = '---\nanki_note_id: 1\ntags: [broken\n---\nbody';
      await f.writeAsString(original);
      expect(
        (await patchFrontmatterField(f.path, 'anki_note_id', '2')).applied,
        isFalse,
      );
      expect(await f.readAsString(), original);
    },
  );

  test('unsupported flow mapping and stranded aliases refuse patch', () {
    expect(
      () => patchFrontmatterText('---\n{score: 1}\n---\nbody', {'score': '2'}),
      throwsFormatException,
    );
    expect(
      () => patchFrontmatterText(
        '---\nscore: &shared 1\ncustom: *shared\n---\nbody',
        {'score': '2'},
      ),
      throwsA(isA<YamlException>()),
    );
  });
}
