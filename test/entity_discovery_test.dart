import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:people_tracker/features/entities/models/entity.dart';
import 'package:people_tracker/features/entities/services/entity_file_parser.dart';
import 'package:people_tracker/features/entities/services/entity_file_writer.dart';
import 'package:people_tracker/shared/markdown/md_utils.dart';

// Regression suite for the June 2026 corruption: entity discovery keyed on
// `category:` alone pulled problem notes into the entity list, and the entity
// save path then rewrote them, destroying their content. See
// docs/entities.md § Entity discovery.

void main() {
  // ── Discovery predicate (Fix 1) ─────────────────────────────────────────────

  group('EntityFileParser.isEntityFrontmatter', () {
    YamlMap? fm(String s) => parseYamlMap(splitFrontmatter(s).frontmatter);

    test('proper entity (alias + category) is an entity', () {
      expect(
        EntityFileParser.isEntityFrontmatter(
            fm('---\nalias: david-deutsch\ncategory: People\n---\n# David Deutsch')),
        isTrue,
      );
    });

    test('problem note (category, no alias) is NOT an entity', () {
      // The exact shape that was corrupted.
      const note =
          '---\nup: \ncategory: Epistemology / Meme / Evolution\nanki_note_id: 1780572892522\n---\n'
          'What is a Memeplex?\n***\nGroup of memes that help to cause each other\'s replication.';
      expect(EntityFileParser.isEntityFrontmatter(fm(note)), isFalse);
    });

    test('plain note (no frontmatter / neither key) is NOT an entity', () {
      expect(EntityFileParser.isEntityFrontmatter(fm('# Plain\n\nJust prose.')), isFalse);
      expect(EntityFileParser.isEntityFrontmatter(fm('---\nup:\n  - "[[x]]"\n---\nBody')),
          isFalse);
    });

    test('bookmark (alias, no category) is NOT an entity', () {
      const bookmark =
          '---\nalias: some-tweet\nauthor: Someone\nsource_url: https://x.com/a/1\ndate: 2026-06-01\n---\n'
          '***\n\nTweet text.';
      expect(EntityFileParser.isEntityFrontmatter(fm(bookmark)), isFalse);
    });
  });

  // ── Corruption-husk detector (Fix 5) ────────────────────────────────────────

  group('EntityFileParser.isCorruptedHusk', () {
    test('matches the corruption signature (entity fm over an H1-only body)', () {
      const husk =
          '---\nalias: what-is-a-memeplex\ncategory: Epistemology / Meme / Evolution\n'
          'created_at: 2026-06-04T19:38:28.146Z\nupdated_at: 2026-06-04T19:38:28.146Z\n---\n'
          '# What is a Memeplex\n';
      expect(EntityFileParser.isCorruptedHusk(husk), isTrue);
    });

    test('a healthy problem note is not flagged (no alias)', () {
      const note =
          '---\ncategory: Default\nanki_note_id: 1\n---\nQ?\n***\nA.';
      expect(EntityFileParser.isCorruptedHusk(note), isFalse);
    });

    test('a healthy entity with sections is not flagged (body is more than an H1)', () {
      const entity =
          '---\nalias: x\ncategory: People\ncreated_at: 2026-01-01T00:00:00.000Z\n'
          'updated_at: 2026-01-01T00:00:00.000Z\n---\n# X\n\n## Why Interesting\n\n- a note';
      expect(EntityFileParser.isCorruptedHusk(entity), isFalse);
    });

    test('a card with a *** separator is not flagged', () {
      const card =
          '---\nalias: x\ncreated_at: 2026-01-01T00:00:00.000Z\n'
          'updated_at: 2026-01-01T00:00:00.000Z\n---\n# Q\n***\nA';
      expect(EntityFileParser.isCorruptedHusk(card), isFalse);
    });
  });

  // ── Writer guard (Fix 2, Layer B) ───────────────────────────────────────────

  group('EntityFileWriter.patchEntityContent guard', () {
    final entity = Entity(
      id: 'memeplex',
      name: 'Memeplex',
      categoryId: 'epistemology',
      createdAt: 1,
      updatedAt: 1,
    );

    String patch(String existing) => EntityFileWriter.patchEntityContent(
          existingContent: existing,
          entity: entity,
          categoryName: 'Epistemology',
          relatedEntityNames: const [],
        );

    test('patches a real entity file without throwing', () {
      const existing = '---\nalias: memeplex\ncategory: Epistemology\n---\n# Memeplex\n\n## Why Interesting\n\n- a note';
      final out = patch(existing);
      expect(out, contains('alias: memeplex'));
      expect(out, contains('# Memeplex'));
    });

    test('renders an instantiated template without throwing (template:)', () {
      const template = '---\ncategory: Default\ntemplate: true\n---\n# Memeplex\n\n## Why Interesting\n\n## Related\n\n## Sources';
      expect(() => patch(template), returnsNormally);
    });

    test('THROWS on a problem note (category, no alias, no template)', () {
      const note = '---\ncategory: Epistemology / Meme / Evolution\nanki_note_id: 1\n---\nWhat is a Memeplex?\n***\nGroup of memes.';
      expect(() => patch(note), throwsStateError);
    });

    test('THROWS on a file with no frontmatter at all', () {
      expect(() => patch('# Plain note\n\nUser prose that must not be destroyed.'),
          throwsStateError);
    });
  });
}
