package com.nimee.people_tracker

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/// Foreground service that runs the whole-vault AnkiDroid push headlessly on its
/// own Flutter engine (the `ankiSyncMain` entrypoint). It owns no window — there
/// is nothing to focus or freeze — and surfaces progress/result purely through
/// the foreground notification. Being a foreground service, Android won't kill it
/// mid-sync.
///
/// SyncActivity starts this only once AnkiDroid's READ_WRITE_DATABASE permission
/// is already granted, so the engine never needs an Activity for a runtime
/// permission request (a service can't show one anyway).
class SyncService : Service() {
    private var engine: FlutterEngine? = null
    private var bridge: AnkiBridge? = null

    companion object {
        private const val SYNC_CHANNEL = "com.nimeesh.interest/sync"

        fun start(context: Context) {
            val intent = Intent(context, SyncService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        enterForeground()
        if (engine == null) runSync()
        return START_NOT_STICKY
    }

    private fun enterForeground() {
        val notification = SyncNotifier.build(
            this, "Anki sync", "Syncing problem notes to AnkiDroid…", ongoing = true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SyncNotifier.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(SyncNotifier.NOTIFICATION_ID, notification)
        }
    }

    private fun runSync() {
        val eng = FlutterEngine(applicationContext)
        engine = eng
        val messenger = eng.dartExecutor.binaryMessenger

        bridge = AnkiBridge(applicationContext).also { it.register(messenger) }

        MethodChannel(messenger, SYNC_CHANNEL).setMethodCallHandler { call, result ->
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
                    stopSyncSelf()
                }
                else -> result.notImplemented()
            }
        }

        eng.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "ankiSyncMain",
            )
        )
    }

    /// Detach the (already-updated, non-ongoing) result notification so it
    /// survives the service stop, then tear down the engine.
    private fun stopSyncSelf() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION") stopForeground(false)
        }
        stopSelf()
    }

    override fun onDestroy() {
        engine?.destroy()
        engine = null
        bridge = null
        super.onDestroy()
    }
}
