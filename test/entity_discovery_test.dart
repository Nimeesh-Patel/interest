import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:people_tracker/features/entities/models/entity.dart';
import 'package:people_tracker/features/entities/services/entity_file_parser.dart';
import 'package:people_tracker/features/entities/services/entity_file_writer.dart';
import 'package:people_tracker/shared/markdown/md_utils.dart';

// Regression suite for the entity model after the June 2026 redefinition:
//   - An Entity is any note with a `collection:` frontmatter key.
//   - A Problem Note is any note with `***` in its body (orthogonal).
//   - The entity writer only patches frontmatter; it NEVER rewrites the body,
//     so a note that is both an Entity and a Problem Note keeps its `***`.

void main() {
  // ── Discovery predicate ─────────────────────────────────────────────────────

  group('EntityFileParser.isEntityFrontmatter', () {
    YamlMap? fm(String s) => parseYamlMap(splitFrontmatter(s).frontmatter);

    test('a note with collection: is an entity', () {
      expect(
        EntityFileParser.isEntityFrontmatter(
            fm('---\ncollection: People\n---\n# David Deutsch')),
        isTrue,
      );
    });

    test('a both-note (collection: + ***) is an entity', () {
      const both = '---\ncollection: People\ncategory: Deck\n---\nQ?\n***\nA.';
      expect(EntityFileParser.isEntityFrontmatter(fm(both)), isTrue);
    });

    test('a problem note (category, no collection) is NOT an entity', () {
      const note =
          '---\ncategory: Epistemology\nanki_note_id: 1780572892522\n---\nWhat?\n***\nBecause.';
      expect(EntityFileParser.isEntityFrontmatter(fm(note)), isFalse);
    });

    test('legacy entity shape (category + alias, no collection) is NOT an entity', () {
      const legacy = '---\nalias: david-deutsch\ncategory: People\n---\n# David Deutsch';
      expect(EntityFileParser.isEntityFrontmatter(fm(legacy)), isFalse);
    });

    test('bookmark (alias, no collection) is NOT an entity', () {
      expect(
        EntityFileParser.isEntityFrontmatter(
            fm('---\nalias: a-tweet\nsource_url: https://x.com/a/1\n---\n***\n\nText.')),
        isFalse,
      );
    });
  });

  // ── Parse ───────────────────────────────────────────────────────────────────

  group('EntityFileParser.parseEntityFile', () {
    test('name is the filename, collection + wikilinks are read', () {
      const content =
          '---\ncollection: People\nscore: 9.0\n---\n# David Deutsch\n\nSee [[Karl Popper]] and [[Constructor Theory]].';
      final r = EntityFileParser.parseEntityFile(content, '/vault/David Deutsch.md');
      expect(r.entity.name, 'David Deutsch');
      expect(r.entity.collection, 'People');
      expect(r.entity.collectionId, 'people');
      expect(r.entity.score, 9.0);
      expect(r.entity.sourcePath, '/vault/David Deutsch.md');
      expect(r.relatedNames, containsAll(['Karl Popper', 'Constructor Theory']));
    });
  });

  // ── Corruption-husk detector (diagnostic) ───────────────────────────────────

  group('EntityFileParser.isCorruptedHusk', () {
    test('matches the corruption signature (entity-ish fm over an H1-only body)', () {
      const husk =
          '---\nalias: what-is-a-memeplex\ncategory: Epistemology\n'
          'created_at: 2026-06-04T19:38:28.146Z\nupdated_at: 2026-06-04T19:38:28.146Z\n---\n'
          '# What is a Memeplex\n';
      expect(EntityFileParser.isCorruptedHusk(husk), isTrue);
    });

    test('a card with a *** separator is not flagged', () {
      const card =
          '---\nalias: x\ncreated_at: 2026-01-01T00:00:00.000Z\n'
          'updated_at: 2026-01-01T00:00:00.000Z\n---\n# Q\n***\nA';
      expect(EntityFileParser.isCorruptedHusk(card), isFalse);
    });
  });

  // ── Writer: frontmatter-only, body preserved ────────────────────────────────

  group('EntityFileWriter.patchFrontmatter', () {
    Entity entity({String collection = 'Thinkers', double? score, List<String>? tags}) =>
        Entity(
          id: 'x',
          name: 'X',
          collection: collection,
          score: score,
          tags: tags,
          createdAt: 1,
          updatedAt: 2,
        );

    test('updates collection and preserves the entire body verbatim', () {
      const existing = '---\ncollection: People\n---\n# X\n\nSome prose with [[Y]].';
      final out = EntityFileWriter.patchFrontmatter(
          existingContent: existing, entity: entity());
      expect(out, contains('collection: Thinkers'));
      expect(out, contains('# X\n\nSome prose with [[Y]].'));
    });

    test('a both-note keeps its *** front/back and its deck (category)', () {
      const both = '---\ncollection: People\ncategory: Deck\nanki_note_id: 5\n---\nFront?\n***\nBack.';
      final out = EntityFileWriter.patchFrontmatter(
          existingContent: both, entity: entity());
      expect(out, contains('collection: Thinkers')); // entity grouping updated
      expect(out, contains('category: Deck'));        // anki deck preserved
      expect(out, contains('anki_note_id: 5'));       // preserved
      expect(out, contains('Front?\n***\nBack.'));    // problem-note body intact
    });

    test('preserves an unknown list key with wikilinks (round-trips as a list)', () {
      const withUp = '---\ncollection: People\nup:\n  - "[[epistemology]]"\n---\nBody';
      final out = EntityFileWriter.patchFrontmatter(
          existingContent: withUp, entity: entity());
      final reparsed = parseYamlMap(splitFrontmatter(out).frontmatter);
      expect(reparsed?['up'], isA<YamlList>());
      expect((reparsed!['up'] as YamlList).first.toString(), '[[epistemology]]');
    });

    test('removes score/tags when unset', () {
      const existing = '---\ncollection: People\nscore: 8.0\ntags:\n  - a\n---\nBody';
      final out = EntityFileWriter.patchFrontmatter(
          existingContent: existing, entity: entity());
      expect(out, isNot(contains('score:')));
      expect(out, isNot(contains('tags:')));
    });

    test('buildNewEntity emits only collection frontmatter — no body, no timestamps', () {
      final out = EntityFileWriter.buildNewEntity(collection: 'People');
      expect(out, contains('collection: People'));
      expect(out, isNot(contains('#'))); // no heading / body structure imposed
      expect(out, isNot(contains('created_at'))); // no timestamps imposed
      expect(out, isNot(contains('updated_at')));
      expect(out.trim().endsWith('---'), isTrue); // body is empty
    });
  });
}
