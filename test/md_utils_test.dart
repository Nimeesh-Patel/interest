import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/shared/markdown/md_utils.dart';

void main() {
  // ── splitFrontmatter ────────────────────────────────────────────────────────

  group('splitFrontmatter', () {
    test('extracts frontmatter and body', () {
      const input = '---\nalias: foo\n---\n# Title\n\nBody here.';
      final r = splitFrontmatter(input);
      expect(r.frontmatter, 'alias: foo');
      expect(r.body, '# Title\n\nBody here.');
    });

    test('returns null frontmatter when no opening delimiter', () {
      const input = '# Title\n\nNo frontmatter.';
      final r = splitFrontmatter(input);
      expect(r.frontmatter, isNull);
      expect(r.body, input);
    });

    test('returns null frontmatter when no closing delimiter', () {
      const input = '---\nalias: foo\n# Title';
      final r = splitFrontmatter(input);
      expect(r.frontmatter, isNull);
    });

    test('body --- delimiters are not confused with frontmatter close', () {
      const input = '---\nalias: foo\n---\n# Title\n\n---\n\nHr above.';
      final r = splitFrontmatter(input);
      expect(r.frontmatter, 'alias: foo');
      expect(r.body, contains('---'));
    });

    test('empty frontmatter block is valid', () {
      const input = '---\n---\n# Body';
      final r = splitFrontmatter(input);
      expect(r.frontmatter, '');
      expect(r.body, '# Body');
    });
  });

  // ── splitFrontBack ──────────────────────────────────────────────────────────

  group('splitFrontBack', () {
    test('splits on *** separator', () {
      const body = 'Front text.\n\n***\n\nBack text.';
      final r = splitFrontBack(body);
      expect(r, isNotNull);
      expect(r!.front, 'Front text.');
      expect(r.back, 'Back text.');
    });

    test('returns null when no separator', () {
      expect(splitFrontBack('No separator here.'), isNull);
    });

    test('returns null when front is empty after trim', () {
      expect(splitFrontBack('\n\n***\n\nBack only.'), isNull);
    });

    test('returns null when back is empty after trim', () {
      expect(splitFrontBack('Front only.\n\n***\n\n'), isNull);
    });

    test('ignores *** inside code fence', () {
      const body = '```\n***\n```\n\nNot split.';
      expect(splitFrontBack(body), isNull);
    });

    test('splits on first *** outside code fences when multiple exist', () {
      const body = 'Front.\n\n***\n\nMiddle.\n\n***\n\nLast.';
      final r = splitFrontBack(body);
      expect(r!.front, 'Front.');
      expect(r.back, 'Middle.\n\n***\n\nLast.');
    });
  });

  // ── extractWikilinks ────────────────────────────────────────────────────────

  group('extractWikilinks', () {
    test('extracts bare wikilinks', () {
      expect(extractWikilinks('See [[Alpha]] and [[Beta]].'), ['Alpha', 'Beta']);
    });

    test('extracts piped wikilinks — returns full [[target|display]] group 1', () {
      // extractWikilinks uses _wikilinkRegex which captures everything inside [[ ]]
      // including the pipe and display: "Target|Display"
      final links = extractWikilinks('[[Note|Alias]]');
      expect(links, ['Note|Alias']);
    });

    test('returns empty list when no wikilinks', () {
      expect(extractWikilinks('Plain text.'), isEmpty);
    });

    test('handles wikilinks inside prose', () {
      final links = extractWikilinks('A [[Thing]] B [[Other]] C');
      expect(links, ['Thing', 'Other']);
    });
  });

  // ── plainTextWikilinks ──────────────────────────────────────────────────────

  group('plainTextWikilinks', () {
    test('strips bare wikilink to target', () {
      expect(plainTextWikilinks('See [[Alpha]].'), 'See Alpha.');
    });

    test('strips piped wikilink to display text', () {
      expect(plainTextWikilinks('[[Note|Alias]]'), 'Alias');
    });

    test('handles multiple wikilinks in one string', () {
      expect(
        plainTextWikilinks('[[A|First]] and [[B]].'),
        'First and B.',
      );
    });

    test('no-op on plain text', () {
      const t = 'No wikilinks here.';
      expect(plainTextWikilinks(t), t);
    });
  });

  // ── buildFrontmatterBlock ───────────────────────────────────────────────────

  group('buildFrontmatterBlock', () {
    test('writes known-order fields first', () {
      final fields = {'b': 'second', 'a': 'first'};
      final result = buildFrontmatterBlock(fields, ['a', 'b']);
      final lines = result.split('\n');
      expect(lines[1], 'a: first');
      expect(lines[2], 'b: second');
    });

    test('unknown keys appear after known keys', () {
      final fields = {'z': 'extra', 'a': 'known'};
      final result = buildFrontmatterBlock(fields, ['a']);
      expect(result, contains('a: known'));
      expect(result.indexOf('a: known'), lessThan(result.indexOf('z: extra')));
    });

    test('null values are skipped', () {
      final fields = <String, dynamic>{'alias': 'foo', 'score': null};
      final result = buildFrontmatterBlock(fields, ['alias', 'score']);
      expect(result, isNot(contains('score')));
    });

    test('empty string values are skipped', () {
      final fields = <String, dynamic>{'alias': 'foo', 'empty': ''};
      final result = buildFrontmatterBlock(fields, ['alias', 'empty']);
      expect(result, isNot(contains('empty')));
    });

    test('list values produce YAML block sequence', () {
      final fields = <String, dynamic>{'tags': ['a', 'b']};
      final result = buildFrontmatterBlock(fields, ['tags']);
      expect(result, contains('tags:\n'));
      expect(result, contains('  - a'));
      expect(result, contains('  - b'));
    });

    test('empty list is skipped', () {
      final fields = <String, dynamic>{'tags': <String>[]};
      final result = buildFrontmatterBlock(fields, ['tags']);
      expect(result, isNot(contains('tags')));
    });

    test('values containing colon are quoted', () {
      final fields = {'url': 'https://example.com'};
      final result = buildFrontmatterBlock(fields, ['url']);
      expect(result, contains('url: "https://example.com"'));
    });

    test('wraps in --- delimiters', () {
      final result = buildFrontmatterBlock({'alias': 'x'}, ['alias']);
      expect(result, startsWith('---\n'));
      expect(result, endsWith('---'));
    });
  });

  // ── slugify ─────────────────────────────────────────────────────────────────

  group('slugify', () {
    test('lowercases and replaces spaces with hyphens', () {
      expect(slugify('Hello World'), 'hello-world');
    });

    test('strips non-alphanumeric characters', () {
      expect(slugify('Hello, World!'), 'hello-world');
    });

    test('collapses multiple spaces to single hyphen', () {
      expect(slugify('a  b'), 'a-b');
    });

    test('returns empty string for whitespace-only input', () {
      expect(slugify('   '), '');
    });

    test('returns empty string for empty input', () {
      expect(slugify(''), '');
    });
  });

  // ── generateUniqueId ────────────────────────────────────────────────────────

  group('generateUniqueId', () {
    test('returns base slug when not in existing set', () {
      expect(generateUniqueId('Foo Bar', {}, fallback: 'fb'), 'foo-bar');
    });

    test('appends -2 on first collision', () {
      expect(generateUniqueId('Foo', {'foo'}, fallback: 'fb'), 'foo-2');
    });

    test('increments until unique', () {
      expect(
        generateUniqueId('Foo', {'foo', 'foo-2', 'foo-3'}, fallback: 'fb'),
        'foo-4',
      );
    });

    test('falls back to fallback when slug is empty', () {
      expect(generateUniqueId('!!!', {}, fallback: 'untitled'), 'untitled');
    });

    test('appends -2 to fallback on collision', () {
      expect(
        generateUniqueId('!!!', {'untitled'}, fallback: 'untitled'),
        'untitled-2',
      );
    });
  });
}
