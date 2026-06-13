import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'features/anki/services/anki_sync_controller.dart';
import 'features/anki/services/anki_sync_service.dart';
import 'features/anki/services/ankidroid_transport.dart';

/// Headless Dart entrypoint run by SyncActivity (the `interest://sync-anki`
/// trampoline). It performs the whole-vault AnkiDroid push WITHOUT any UI —
/// progress and result surface as an Android notification posted over the
/// platform channel — then asks the native side to finish the activity, so the
/// user stays in Obsidian. The sync logic itself is unchanged from the in-app
/// path; only the trigger and feedback differ.
@pragma('vm:entry-point')
void ankiSyncMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.nimeesh.interest/sync');

  Future<void> notify(String text, {bool ongoing = false}) => channel
      .invokeMethod<void>('notify',
          {'title': 'Anki sync', 'text': text, 'ongoing': ongoing})
      .catchError((_) {});

  try {
    await notify('Syncing problem notes to AnkiDroid…', ongoing: true);
    final transport = AnkiDroidTransport();

    if (!await transport.isAvailable()) {
      await notify('AnkiDroid not installed');
    } else if (!await transport.requestPermission()) {
      await notify('AnkiDroid permission denied');
    } else {
      final result = await AnkiSyncController.sync(transport);
      await notify(_summary(result));
    }
  } catch (e) {
    await notify('Sync failed: $e');
  } finally {
    await channel.invokeMethod<void>('finish').catchError((_) {});
  }
}

String _summary(AnkiSyncResult? result) {
  if (result == null) return 'No vault configured';
  final total = result.added + result.updated;
  final base =
      '$total synced (${result.added} added, ${result.updated} updated)';
  return result.failed == 0 ? base : '$base · ${result.failed} failed';
}
