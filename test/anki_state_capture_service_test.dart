import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/features/anki/services/anki_state_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const anki = MethodChannel('dev.interest.app/ankidroid');
  const export = MethodChannel('dev.interest.app/anki-state-export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final instant = DateTime.utc(2026, 11, 5, 9);

  Map<String, Object?> card(int id, {int ordinal = 0}) => {
    'card_id': id,
    'note_id': 23,
    'ordinal': ordinal,
    'state': {
      'deck_id': 5,
      'original_deck_id': 0,
      'type': 2,
      'queue': 2,
      'due': 812,
      'original_due': 0,
      'interval': 4,
      'reps': 7,
      'lapses': 1,
      'future_native_field': 'preserved',
    },
    'source_front_html':
        '<a href="obsidian://open?vault=Ideas&file=Nuance">根</a>',
  };

  Map<String, Object?> observation(String query, List<Object?> cards) => {
    'query': query,
    'status': 'complete',
    'observed_at_ms': instant.millisecondsSinceEpoch,
    'total': cards.length,
    'cards': cards,
    'errors': <Object?>[],
    'future_query_extension': {'retained': true},
  };

  void handle(Future<Object?> Function(MethodCall call) query) {
    messenger.setMockMethodCallHandler(anki, (call) async {
      switch (call.method) {
        case 'isAnkiDroidAvailable':
        case 'requestPermission':
          return true;
        case 'getAnkiDroidVersion':
          return '2.25.1';
        case 'queryCardState':
          return query(call);
        default:
          fail('Capture invoked unexpected native operation ${call.method}');
      }
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(anki, null);
    messenger.setMockMethodCallHandler(export, null);
  });

  test(
    'capture preserves overlapping queries and distinct cards per note without sync',
    () async {
      final calls = <Map<Object?, Object?>>[];
      handle((call) async {
        final args = call.arguments as Map;
        calls.add(args);
        final query = args['query'] as String;
        return observation(
          query,
          query == 'is:new' ? [] : [card(41), card(42, ordinal: 1)],
        );
      });
      final capture = await AnkiStateCaptureService(
        now: () => instant,
      ).capture(limit: 3);
      expect(capture['status'], 'complete');
      expect(calls, [
        {'query': 'is:due', 'limit': 3},
        {'query': 'rated:1', 'limit': 3},
        {'query': 'is:new', 'limit': 3},
      ]);
      expect(capture['freshness'], containsPair('live', false));
      expect(capture['scope'], containsPair('collection_identity', null));
      final records = capture['records'] as List;
      expect((records[0] as Map)['cards'], [card(41), card(42, ordinal: 1)]);
      expect((records[1] as Map)['cards'], [card(41), card(42, ordinal: 1)]);
      expect((records[0] as Map)['future_query_extension'], {'retained': true});
      expect(jsonDecode(jsonEncode(capture)), capture);
    },
  );

  test(
    'failed and malformed native queries remain unavailable beside valid empty results',
    () async {
      handle((call) async {
        final query = (call.arguments as Map)['query'] as String;
        if (query == 'rated:1') {
          throw PlatformException(
            code: 'UNSUPPORTED',
            message: 'Provider unavailable',
          );
        }
        if (query == 'is:new') return observation('wrong identity', []);
        return observation(query, []);
      });
      final capture =
          await AnkiStateCaptureService(now: () => instant).capture();
      expect(capture['status'], 'partial');
      final records = capture['records'] as List;
      expect((records[0] as Map)['status'], 'complete');
      for (final record in records.skip(1).cast<Map>()) {
        expect(record['status'], 'unavailable');
        expect(record['total'], isNull);
        expect(record['errors'], isNotEmpty);
      }
    },
  );

  test(
    'truncation and native source errors retain limits and raw state',
    () async {
      handle((call) async {
        final query = (call.arguments as Map)['query'] as String;
        return {
          ...observation(query, [
            {
              ...card(41),
              'source_front_html': null,
              'source_error': 'Could not read note',
            },
          ]),
          'status': 'partial',
          'total': 600,
          'errors': [
            {
              'stage': 'source',
              'note_id': 23,
              'message': 'Could not read note',
            },
          ],
        };
      });
      final capture =
          await AnkiStateCaptureService(now: () => instant).capture();
      expect(capture['status'], 'partial');
      final first = (capture['records'] as List).first as Map;
      expect(first['total'], 600);
      expect(
        ((first['cards'] as List).single as Map)['source_error'],
        'Could not read note',
      );
    },
  );

  test(
    'inconsistent complete counts and duplicate cards are not accepted as complete',
    () async {
      handle(
        (call) async => {
          ...observation((call.arguments as Map)['query'] as String, [
            card(41),
            card(41),
          ]),
          'total': 5,
        },
      );
      final capture =
          await AnkiStateCaptureService(now: () => instant).capture();
      expect(capture['status'], 'unavailable');
      expect(
        (capture['records'] as List).cast<Map>().every(
          (r) => r['total'] == null,
        ),
        isTrue,
      );
    },
  );

  test('permission refusal never queries or exports a collection', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(anki, (call) async {
      calls.add(call.method);
      return call.method == 'isAnkiDroidAvailable';
    });
    await expectLater(AnkiStateCaptureService().capture(), throwsStateError);
    expect(calls, ['isAnkiDroidAvailable', 'requestPermission']);
  });

  test(
    'save carries exact UTF-8 bytes and accepts only explicit verified URI',
    () async {
      const capture = {'preserved': '根 and naïve', 'unknown_extension': 12};
      messenger.setMockMethodCallHandler(export, (call) async {
        expect(call.method, 'save');
        final args = call.arguments as Map;
        expect(args['fileName'], endsWith('.json'));
        expect(jsonDecode(utf8.decode(args['bytes'] as Uint8List)), capture);
        return {
          'status': 'verified',
          'uri': 'content://chosen-provider/exact-document',
        };
      });
      final result = await AnkiStateCaptureService(
        now: () => instant,
      ).save(capture);
      expect(result['uri'], 'content://chosen-provider/exact-document');
      expect(result['status'], 'verified');
    },
  );

  test(
    'save cancellation and unverified writes remain distinct, failures propagate',
    () async {
      final service = AnkiStateCaptureService(now: () => instant);
      messenger.setMockMethodCallHandler(
        export,
        (_) async => {'status': 'cancelled', 'uri': null},
      );
      expect((await service.save({}))['status'], 'cancelled');
      messenger.setMockMethodCallHandler(
        export,
        (_) async => {
          'status': 'written_unverified',
          'uri': 'content://chosen/document',
          'error': 'Read grant unavailable',
        },
      );
      expect((await service.save({}))['status'], 'written_unverified');
      messenger.setMockMethodCallHandler(
        export,
        (_) async => {'status': 'verified', 'uri': null},
      );
      await expectLater(service.save({}), throwsFormatException);
      messenger.setMockMethodCallHandler(
        export,
        (_) async =>
            throw PlatformException(
              code: 'EXPORT_VERIFY',
              message: 'Bytes differ',
            ),
      );
      await expectLater(service.save({}), throwsA(isA<PlatformException>()));
    },
  );
}
