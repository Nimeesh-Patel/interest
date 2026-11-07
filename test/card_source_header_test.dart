import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/anki/services/anki_problem_note_scanner.dart';
import 'package:people_tracker/features/anki/services/anki_sync_service.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';
import 'package:people_tracker/features/anki/services/card_source_header.dart';
import 'package:people_tracker/shared/markdown/md_utils.dart';

import 'anki_sync_service_test.dart' show FakeTransport;

// The card header is the ownership anchor every reader depends on; its look
// may change, its contract may not.

const _legacyStyle =
    'text-align:right;font-size:0.75em;margin-bottom:6px;opacity:0.6;';

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('vault');
  });

  tearDown(() => vault.delete(recursive: true));

  Future<String> write(String name, String content) async {
    final file = File(p.join(vault.path, '$name.md'));
    await file.writeAsString(content);
    return file.path;
  }

  test('the header keeps the contract its readers rely on', () {
    const uri = 'obsidian://open?vault=v&file=A%20%26%20B';
    final html = CardSourceHeader.html(uri, 'A & <B>');
    expect(html, startsWith('<div class="interest-source"'));
    expect('<a '.allMatches(html), hasLength(1));
    expect('href='.allMatches(html), hasLength(1));
    expect(hasAnkiSourceLink(html, uri), isTrue);
    expect(
      html.indexOf('</div>'),
      html.length - '</div>'.length,
      reason: 'no nested div: _plainText strips up to the first </div>',
    );
    expect(html, contains('A &amp; &lt;B&gt;'));
  });

  test('a card in the old style is updated, not duplicated or orphaned',
      () async {
    final path = await write(
      'Old',
      '---\nanki_note_id: 42\n---\nOld?\n\n***\n\nYes.\n',
    );
    final uri = obsidianUri(vault.path, path);
    final transport = FakeTransport()..existingIds.add(42);
    transport.stored[42] = AnkiNoteState(
      id: 42,
      front:
          '<div style="$_legacyStyle"><a href="$uri">Old ↗</a></div><p>Old?</p>',
      back: '<p>Yes.</p>',
      tags: const {},
      decks: const {'Default'},
      reviews: 30,
    );
    final scanned = await AnkiProblemNoteScanner.scan(vault.path);
    final result = await AnkiSyncService.syncVault(
      transport,
      scanned.notes,
      vault.path,
      reconcileCollection: true,
    );
    expect(result.isSuccessful, isTrue);
    expect(result.updated, 1);
    expect(result.orphans, isEmpty);
    expect(result.duplicatesRetired, 0);
    expect(transport.addCalls, isEmpty);
    expect(transport.retireCalls, isEmpty);
    final front = transport.stored[42]!.front;
    expect(front, startsWith('<div class="interest-source"'));
    expect(hasAnkiSourceLink(front, uri), isTrue);
  });

  test('an orphan in the new style still shows its problem as text', () async {
    final transport = FakeTransport()..existingIds.add(9);
    final uri = obsidianUriForName(vault.path, 'Gone');
    transport.stored[9] = AnkiNoteState(
      id: 9,
      front: '${CardSourceHeader.html(uri, 'Gone')}<p>What was it?</p>',
      back: '<p>This.</p>',
      tags: const {},
      decks: const {'Default'},
    );
    final result = await AnkiSyncService.syncVault(
      transport,
      const [],
      vault.path,
      reconcileCollection: true,
    );
    expect(result.orphans.single.problem, 'What was it?');
    expect(result.orphans.single.noteName, 'Gone');
  });
}
