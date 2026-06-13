package com.nimee.people_tracker

import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Transparent, no-history trampoline that handles `interest://sync-anki` from
/// the Problem Notes Obsidian plugin. It runs the sync on its own Flutter engine
/// (the `ankiSyncMain` Dart entrypoint) WITHOUT bringing Interest's main UI to
/// the foreground — it lives on a separate task, is excluded from recents, draws
/// nothing (transparent), and finishes the moment Dart signals completion. The
/// user sees a notification and stays in Obsidian.
///
/// NOTE: this native headless path has not been verified on a physical device in
/// this environment. A fully invisible (zero-flash) variant would use a
/// foreground Service + long-lived background isolate; this trampoline is the
/// cleanest reliable approximation. See docs/anki.md.
class SyncActivity : FlutterActivity() {
    private var bridge: AnkiBridge? = null
    private val syncChannelName = "com.nimeesh.interest/sync"

    override fun getDartEntrypointFunctionName(): String = "ankiSyncMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Best-effort POST_NOTIFICATIONS request (Android 13+); the sync runs
        // regardless of the outcome — only the visible feedback depends on it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this, arrayOf("android.permission.POST_NOTIFICATIONS"), 1002)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        bridge = AnkiBridge(this).also { it.register(messenger) }

        MethodChannel(messenger, syncChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "notify" -> {
                    SyncNotifier.show(
                        applicationContext,
                        call.argument<String>("title") ?: "Anki sync",
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("ongoing") ?: false,
                    )
                    result.success(null)
                }
                "finish" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
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
}
