import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/features/anki/services/anki_connect_transport.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';

// Verifies the AnkiConnect transport against a local fake implementing the
// wire contract confirmed live against AnkiConnect API version 6:
//   - POST {action, version, params} → {result, error}
//   - createDeck is idempotent and must precede addNote (addNote errors on a
//     missing deck)
//   - notesInfo returns an empty object (not an error) for a missing note id

/// Minimal fake AnkiConnect server. Handlers return the `result` value or
/// throw a String to simulate AnkiConnect's `error` field.
class FakeAnkiConnect {
  late final HttpServer _server;
  final List<Map<String, dynamic>> requests = [];
  final Map<String, Object? Function(Map<String, dynamic>? params)> handlers =
      {};

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final decoded =
          jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      requests.add(decoded);
      Object? result;
      String? error;
      final handler = handlers[decoded['action'] as String];
      if (handler == null) {
        error = 'unsupported action: ${decoded['action']}';
      } else {
        try {
          result = handler(decoded['params'] as Map<String, dynamic>?);
        } on String catch (e) {
          error = e;
        }
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'result': result, 'error': error}));
      await req.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${_server.port}';

  List<String> get actions =>
      requests.map((r) => r['action'] as String).toList();

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeAnkiConnect anki;
  late AnkiConnectTransport transport;

  setUp(() async {
    anki = FakeAnkiConnect();
    await anki.start();
    transport = AnkiConnectTransport(url: anki.url);
  });

  tearDown(() => anki.stop());

  void allowBasicModel() =>
      anki.handlers['modelNames'] = (_) => ['Basic', 'Cloze'];

  group('availability and permission', () {
    test('isAvailable true when version answers', () async {
      anki.handlers['version'] = (_) => 6;
      expect(await transport.isAvailable(), isTrue);
      final req = anki.requests.single;
      expect(req['action'], 'version');
      expect(req['version'], 6);
    });

    test('isAvailable false when nothing listens on the port', () async {
      await anki.stop();
      expect(await transport.isAvailable(), isFalse);
    });

    test('requestPermission true only on granted', () async {
      anki.handlers['requestPermission'] =
          (_) => {'permission': 'granted', 'requireApikey': false};
      expect(await transport.requestPermission(), isTrue);

      anki.handlers['requestPermission'] = (_) => {'permission': 'denied'};
      expect(await transport.requestPermission(), isFalse);
    });
  });

  group('addNote', () {
    test('creates deck first, then adds on the Basic model', () async {
      allowBasicModel();
      anki.handlers['createDeck'] = (_) => 42;
      anki.handlers['addNote'] = (_) => 1781279337415;

      final id = await transport
          .addNote('Philosophy', '<b>front</b>', 'back', ['tag-a']);

      expect(id, 1781279337415);
      expect(anki.actions, ['modelNames', 'createDeck', 'addNote']);

      final createDeck = anki.requests[1]['params'] as Map<String, dynamic>;
      expect(createDeck['deck'], 'Philosophy');

      final note = (anki.requests[2]['params']
          as Map<String, dynamic>)['note'] as Map<String, dynamic>;
      expect(note['deckName'], 'Philosophy');
      expect(note['modelName'], 'Basic');
      expect(note['fields'], {'Front': '<b>front</b>', 'Back': 'back'});
      expect(note['tags'], ['tag-a']);
      expect((note['options'] as Map<String, dynamic>)['allowDuplicate'], true);
    });

    test('missing Basic model aborts the sync', () async {
      anki.handlers['modelNames'] = (_) => ['Einfach', 'Cloze'];
      expect(() => transport.addNote('D', 'f', 'b', []),
          throwsA(isA<AnkiSyncAbort>()));
    });

    test('AnkiConnect error surfaces as a per-note failure with message',
        () async {
      allowBasicModel();
      anki.handlers['createDeck'] = (_) => 42;
      anki.handlers['addNote'] =
          (_) => throw 'cannot create note because it is empty';

      expect(
          () => transport.addNote('D', 'f', 'b', []),
          throwsA(isA<AnkiNoteFailure>().having((e) => e.message, 'message',
              'cannot create note because it is empty')));
    });

    test('Basic-model check runs once per transport instance', () async {
      allowBasicModel();
      anki.handlers['createDeck'] = (_) => 42;
      anki.handlers['addNote'] = (_) => 1;

      await transport.addNote('D', 'f', 'b', []);
      await transport.addNote('D', 'f2', 'b2', []);

      expect(anki.actions.where((a) => a == 'modelNames').length, 1);
    });
  });

  group('updateNote', () {
    test('updates fields then tags', () async {
      anki.handlers['updateNoteFields'] = (_) => null;
      anki.handlers['updateNoteTags'] = (_) => null;

      final ok = await transport.updateNote(99, 'f', 'b', ['t1', 't2']);

      expect(ok, isTrue);
      expect(anki.actions, ['updateNoteFields', 'updateNoteTags']);

      final fieldsNote = (anki.requests[0]['params']
          as Map<String, dynamic>)['note'] as Map<String, dynamic>;
      expect(fieldsNote['id'], 99);
      expect(fieldsNote['fields'], {'Front': 'f', 'Back': 'b'});

      final tagsParams = anki.requests[1]['params'] as Map<String, dynamic>;
      expect(tagsParams['note'], 99);
      expect(tagsParams['tags'], ['t1', 't2']);
    });

    test('returns false on AnkiConnect error', () async {
      anki.handlers['updateNoteFields'] = (_) => throw 'note was not found: 99';
      expect(await transport.updateNote(99, 'f', 'b', []), isFalse);
    });
  });

  group('noteExists', () {
    test('empty object means missing (AnkiConnect convention)', () async {
      anki.handlers['notesInfo'] = (_) => [<String, Object?>{}];
      expect(await transport.noteExists(123), isFalse);
    });

    test('populated info means present', () async {
      anki.handlers['notesInfo'] = (_) => [
            {'noteId': 123, 'modelName': 'Basic'}
          ];
      expect(await transport.noteExists(123), isTrue);
      final params = anki.requests.single['params'] as Map<String, dynamic>;
      expect(params['notes'], [123]);
    });
  });
}
