package com.nimee.people_tracker

import io.flutter.embedding.android.FlutterActivity

/// The main Collections + Projects UI. The Anki sync no longer runs here — it is
/// triggered by the `interest://sync-anki` deep link, which SyncActivity handles
/// on a separate task without foregrounding this UI.
class MainActivity : FlutterActivity()
