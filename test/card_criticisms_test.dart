import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/anki/services/anki_problem_note_scanner.dart';
import 'package:people_tracker/features/anki/services/anki_sync_service.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';
import 'package:people_tracker/features/anki/services/card_criticisms.dart';
import 'package:yaml/yaml.dart';

// Open criticisms: an objection recorded on the challenged note must reach
// the card's answer side, and a damaged list must never read as "none open".

class _Anki extends AnkiTransport {
  final Map<int, AnkiNoteState> cards = {};
  int updates = 0;
  int _next = 1;

  @override
  String get displayName => 'Fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<int> addNote(String deck, String front, String back, List<String> tags) async {
    final id = _next++;
    cards[id] = AnkiNoteState(id: id, front: front, back: back, tags: tags.toSet(), decks: {deck});
    return id;
  }

  @override
  Future<bool> updateNote(int id, String front, String back, List<String> tags) async {
    updates++;
    cards[id] = AnkiNoteState(
      id: id,
      front: front,
      back: back,
      tags: tags.toSet(),
      decks: cards[id]!.decks,
      reviews: cards[id]!.reviews,
    );
    return true;
  }

  @override
  Future<AnkiCollectionSnapshot> snapshot() async => AnkiCollectionSnapshot(Map.of(cards));

  @override
  Future<bool> moveToDeck(int id, String deck) async {
    final c = cards[id]!;
    cards[id] = AnkiNoteState(id: id, front: c.front, back: c.back, tags: c.tags, decks: {deck}, reviews: c.reviews);
    return true;
  }
}

void main() {
  Object? property(String yaml) => (loadYaml(yaml) as YamlMap)['criticisms'];
  ({String href, String title}) href(String target) =>
      (href: 'obsidian://open?file=$target', title: target);

  group('reading the property', () {
    test('links are kept in order', () {
      expect(
        CardCriticisms.parse(property('criticisms:\n  - "[[Fads]]"\n  - "[[Hubs|the hub case]]"\n')),
        ['[[Fads]]', '[[Hubs|the hub case]]'],
      );
    });

    test('an absent or empty property means nothing is open', () {
      expect(CardCriticisms.parse(null), isEmpty);
      expect(CardCriticisms.parse(property('criticisms: []\n')), isEmpty);
      expect(CardCriticisms.parse(property('criticisms:\n  - ""\n')), isEmpty);
    });

    test('one link without a list is one entry', () {
      expect(CardCriticisms.parse(property('criticisms: "[[Fads]]"\n')), ['[[Fads]]']);
    });

    test('a sentence is refused: an objection lives in a note', () {
      expect(() => CardCriticisms.parse(property('criticisms:\n  - Too broad\n')), throwsFormatException);
      expect(() => CardCriticisms.parse(property('criticisms:\n  - "see [[Fads]]"\n')), throwsFormatException);
    });

    test('an unquoted link, which YAML reads as a nested list, is the link', () {
      expect(CardCriticisms.parse(property('criticisms:\n  - [[Fads]]\n')), ['[[Fads]]']);
    });

    test('anything else is an error, never an empty list', () {
      expect(() => CardCriticisms.parse(property('criticisms:\n  - {a: b}\n')), throwsFormatException);
      expect(() => CardCriticisms.parse(property('criticisms:\n  a: b\n')), throwsFormatException);
      expect(() => CardCriticisms.parse(property('criticisms: 3\n')), throwsFormatException);
      expect(() => CardCriticisms.parse('[[   |label]]'), throwsFormatException);
    });
  });

  group('the section on the card', () {
    test('nothing open adds nothing', () {
      expect(CardCriticisms.html(const [], href), '');
    });

    test('a link entry is one tappable row to the objection', () {
      final html = CardCriticisms.html(['[[Fads|the fad objection]]'], href);
      expect(html, startsWith('<div class="interest-criticisms"'));
      expect(html, contains('>Open criticism</h2>'));
      expect(html, contains('<a href="obsidian://open?file=Fads"'));
      expect(html, contains('>Fads</span>'));
      expect(html, isNot(contains('the fad objection')));
      expect(html, contains('min-height:48px'));
      // One div, so readers can cut the section off whole.
      expect('<div'.allMatches(html).length, 1);
    });

    test('several links are several rows, with labels escaped', () {
      final html = CardCriticisms.html(['[[Q & A]]', '[[Fads]]'], href);
      expect(html, contains('>Open criticisms<'));
      expect(html, contains('>Q &amp; A</span>'));
      expect('<a href'.allMatches(html).length, 2);
    });

    test('the conjecture alone can be recovered from the back', () {
      final back = '<p>Conjecture.</p>\n${CardCriticisms.html(['[[Fads]]'], href)}';
      expect(CardCriticisms.withoutSection(back), '<p>Conjecture.</p>\n');
      expect(CardCriticisms.withoutSection('<p>Plain.</p>'), '<p>Plain.</p>');
    });
  });

  group('from note to card', () {
    late Directory vault;
    setUp(() => vault = Directory.systemTemp.createTempSync('criticisms'));
    tearDown(() => vault.deleteSync(recursive: true));

    File note(String name, String text) => File(p.join(vault.path, '$name.md'))..writeAsStringSync(text);

    test('uses the resolved note title and aligns multi-paragraph answers', () async {
      note('Challenged', '---\ncriticisms:\n  - "[[Alt|Custom label]]"\n---\nQ\n***\nFirst.\n\nSecond.\n');
      note('Actual objection', '---\naliases: [Alt]\n---\nObjection details.\n');
      final anki = _Anki();
      final scan = await AnkiProblemNoteScanner.scan(vault.path);
      await AnkiSyncService.syncVault(anki, scan.notes, vault.path);
      final back = anki.cards.values.single.back;
      expect(back, startsWith('<section style="text-align:left;">'));
      expect(back, contains('file=Actual%20objection'));
      expect(back, contains('>Actual objection</span>'));
      expect(back, isNot(contains('Custom label')));
    });

    test('the card back lists what is open, and clears when the list empties', () async {
      final file = note(
        'Challenged',
        '---\ncriticisms:\n  - "[[Objection]]"\n  - "[[Hubs]]"\n---\nProblem?\n***\nConjecture.\n',
      );
      final anki = _Anki();
      var scan = await AnkiProblemNoteScanner.scan(vault.path);
      expect(scan.errors, isEmpty);
      expect(scan.notes.single.criticisms, ['[[Objection]]', '[[Hubs]]']);
      await AnkiSyncService.syncVault(anki, scan.notes, vault.path);

      final card = anki.cards.values.single;
      expect(card.front, isNot(contains('interest-criticisms')));
      expect(card.front, isNot(contains('text-align:left;')));
      expect(card.back, startsWith('<section style="text-align:left;">'));
      expect(card.back, contains('<p>Conjecture.</p>'));
      expect(card.back.indexOf('Conjecture.'), lessThan(card.back.indexOf('interest-criticisms')));
      expect(card.back, contains('file=Objection'));
      expect(card.back, contains('file=Hubs'));

      // Syncing the same state again writes nothing.
      scan = await AnkiProblemNoteScanner.scan(vault.path);
      await AnkiSyncService.syncVault(anki, scan.notes, vault.path);
      expect(anki.updates, 0);

      // Removing the entries is how he says they no longer apply.
      file.writeAsStringSync(file.readAsStringSync().replaceFirst(
        RegExp(r'criticisms:\n(  - .*\n)+'),
        'criticisms: []\n',
      ));
      scan = await AnkiProblemNoteScanner.scan(vault.path);
      await AnkiSyncService.syncVault(anki, scan.notes, vault.path);
      expect(anki.updates, 1);
      expect(anki.cards.values.single.back, isNot(contains('interest-criticisms')));
      expect(anki.cards.values.single.id, card.id);
    });

    test('a damaged list stops the note from syncing as if nothing were open', () async {
      note('Damaged', '---\ncriticisms:\n  - {oops: 1}\n---\nQ\n***\nA\n');
      final scan = await AnkiProblemNoteScanner.scan(vault.path);
      expect(scan.notes, isEmpty);
      expect(scan.errors.single, contains('Damaged.md'));
      expect(scan.errors.single, contains('criticisms must be links'));
    });
  });
}
