import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/shared/markdown/link_targets.dart';
import 'package:people_tracker/shared/markdown/md_utils.dart';

void main() {
  group('parseAliases', () {
    test('reads a block list', () {
      expect(parseAliases('up: null\naliases:\n  - gumption\n  - grit'), [
        'gumption',
        'grit',
      ]);
    });
    test('reads an inline list and strips quotes', () {
      expect(parseAliases("aliases: ['speed of progress', \"grit\"]"), [
        'speed of progress',
        'grit',
      ]);
    });
    test('reads a scalar and accepts the singular key', () {
      expect(parseAliases('alias: optimism'), ['optimism']);
    });
    test('stops collecting at the next top-level key', () {
      expect(parseAliases('aliases:\n  - a\ncategory: Default\n  - b'), ['a']);
    });
    test('returns empty for absent or empty frontmatter', () {
      expect(parseAliases(null), isEmpty);
      expect(parseAliases('up: null'), isEmpty);
    });
  });

  group('buildLinkTargets', () {
    late Directory vault;
    setUp(() => vault = Directory.systemTemp.createTempSync('lt'));
    tearDown(() => vault.deleteSync(recursive: true));

    void note(String name, String content) =>
        File(p.join(vault.path, name))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);

    test('an alias resolves to the note that declares it', () async {
      note(
        'rapid explanatory progress.md',
        '---\naliases:\n  - speed of progress\n---\nq\n***\na\n',
      );
      final result = await buildLinkTargets(vault.path);
      expect(result.errors, isEmpty);
      expect(
        resolveLinkTarget('speed of progress', result.targets),
        'rapid explanatory progress',
      );
      expect(
        resolveLinkTarget('Speed Of Progress', result.targets),
        'rapid explanatory progress',
      );
    });

    test('a real filename wins over someone else\'s alias', () async {
      note('progress.md', '---\nup: null\n---\nq\n***\na\n');
      note('other.md', '---\naliases:\n  - progress\n---\nq\n***\na\n');
      final result = await buildLinkTargets(vault.path);
      expect(resolveLinkTarget('progress', result.targets), 'progress');
    });

    test('an ambiguous alias is dropped, not guessed', () async {
      note('one.md', '---\naliases:\n  - shared\n---\nq\n***\na\n');
      note('two.md', '---\naliases:\n  - shared\n---\nq\n***\na\n');
      final result = await buildLinkTargets(vault.path);
      expect(resolveLinkTarget('shared', result.targets), 'shared');
    });

    test('an anchor survives resolution', () async {
      note('canonical name.md', '---\naliases:\n  - short\n---\nq\n***\na\n');
      final result = await buildLinkTargets(vault.path);
      expect(
        resolveLinkTarget('short#Section', result.targets),
        'canonical name#Section',
      );
    });

    test('an unknown target is returned unchanged', () async {
      final result = await buildLinkTargets(vault.path);
      expect(resolveLinkTarget('nothing here', result.targets), 'nothing here');
    });
  });
}
