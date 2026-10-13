import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/features/anki/services/ankidroid_transport.dart';
import 'package:people_tracker/features/anki/services/anki_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.interest.app/ankidroid');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'retirement carries exact source identity to the native guard',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final transport = AnkiDroidTransport();
      expect(transport.projectionCapabilities.supports('retire'), isTrue);
      expect(
        await transport.retireNote(
          555,
          'obsidian://open?vault=Research&file=Former',
        ),
        isTrue,
      );
      expect(calls.single.method, 'retireNote');
      expect(calls.single.arguments, {
        'noteId': 555,
        'expectedSourceUri': 'obsidian://open?vault=Research&file=Former',
      });
    },
  );

  test('native source refusal remains a visible failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'SOURCE',
        message: 'Anki source link does not match',
      );
    });
    await expectLater(
      AnkiDroidTransport().retireNote(
        555,
        'obsidian://open?vault=Research&file=Former',
      ),
      throwsA(
        isA<AnkiNoteFailure>().having(
          (error) => error.message,
          'message',
          contains('source link'),
        ),
      ),
    );
  });

  test(
    'unavailable native queries do not confirm retirement or absence',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'ANKI_ERROR',
          message: 'AnkiDroid note query unavailable',
        );
      });
      expect(await AnkiDroidTransport().noteExists(555), isNull);
      await expectLater(
        AnkiDroidTransport().retireNote(
          555,
          'obsidian://open?vault=Research&file=Former',
        ),
        throwsA(isA<AnkiNoteFailure>()),
      );
    },
  );

  test(
    'an empty native response is an unknown identity, not a missing card',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await AnkiDroidTransport().noteExists(555), isNull);
      expect(
        await AnkiDroidTransport().retireNote(
          555,
          'obsidian://open?vault=Research&file=Former',
        ),
        isFalse,
      );
    },
  );
}
