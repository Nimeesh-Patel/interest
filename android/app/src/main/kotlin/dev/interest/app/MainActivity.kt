package dev.interest.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// The Collections + Projects UI, and the host of the Anki sync. The
/// `interest://sync-anki` deep link (fired by the Problem Notes Obsidian plugin)
/// opens this activity, which routes the trigger to Flutter over the deeplink
/// channel; the Dart side runs AnkiSyncController.sync(AnkiDroidTransport()) and
/// shows the result in a snackbar. Interest coming to the foreground is expected.
///
/// AnkiBridge (the AnkiDroid ContentProvider bridge) is registered here so its
/// runtime permission request runs through this Activity.
class MainActivity : FlutterActivity() {
    private val deeplinkChannelName = "dev.interest.app/deeplink"
    private var bridge: AnkiBridge? = null
    private var stateExport: AnkiStateExport? = null

    /// True when the launching intent was `interest://sync-anki` and Flutter
    /// hasn't yet picked it up (cold start). Consumed by `getInitialSyncAnki`.
    private var pendingSyncAnki = false

    /// The vault-relative note named by `?note=`, when the link came from a
    /// note being edited: Flutter then syncs only that note.
    private var pendingNote: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingSyncAnki = isSyncAnki(intent)
        pendingNote = if (pendingSyncAnki) noteOf(intent) else null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (isSyncAnki(intent)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, deeplinkChannelName).invokeMethod("syncAnki", noteOf(intent))
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        bridge = AnkiBridge(this).also { it.register(messenger) }
        stateExport = AnkiStateExport(this).also { it.register(messenger) }

        MethodChannel(messenger, deeplinkChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSyncAnki" -> {
                    result.success(mapOf("sync" to pendingSyncAnki, "note" to pendingNote))
                    pendingSyncAnki = false
                    pendingNote = null
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Used by the Android document chooser")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (stateExport?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        stateExport?.dispose()
        stateExport = null
        super.onDestroy()
    }

    private fun noteOf(intent: Intent): String? =
        intent.data?.getQueryParameter("note")?.takeIf { it.isNotBlank() }

    private fun isSyncAnki(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW) return false
        val uri = intent.data ?: return false
        return uri.scheme == "interest" && uri.host == "sync-anki"
    }
}
