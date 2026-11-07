import 'dart:io';

import '../anki/services/anki_connect_transport.dart';
import '../anki/services/anki_transport.dart';
import '../anki/services/ankidroid_transport.dart';

/// Whether this device can reach its Anki collection right now.
enum TargetReadiness { ready, notInstalled, permissionDenied }

/// The one Anki collection this device syncs: AnkiDroid on the phone, Anki
/// desktop (through AnkiConnect) everywhere else.
class SyncTarget {
  final AnkiTransport transport;
  const SyncTarget._(this.transport);

  factory SyncTarget.forPlatform() => SyncTarget._(
    Platform.isAndroid ? AnkiDroidTransport() : AnkiConnectTransport(),
  );

  String get name => transport.displayName;

  /// Checks availability, then asks for permission if it is missing. On the
  /// phone the request shows Android's own permission prompt once.
  Future<TargetReadiness> prepare() async {
    if (!await transport.isAvailable()) return TargetReadiness.notInstalled;
    if (!await transport.requestPermission()) {
      return TargetReadiness.permissionDenied;
    }
    return TargetReadiness.ready;
  }
}
