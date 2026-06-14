package com.nimee.people_tracker

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/// Receives the `interest://sync-anki` deep link and immediately hands the work
/// to the headless SyncService foreground service, then finishes. It draws no
/// content (translucent theme) and never runs the sync itself — so it cannot
/// freeze or steal focus from Obsidian, the bug the old transparent-FlutterActivity
/// trampoline had.
///
/// The one thing only an Activity can do is request AnkiDroid's runtime
/// READ_WRITE_DATABASE permission (a service can't), so this is the sole reason
/// the deep link still touches an Activity at all:
///   • permission already granted (every sync after the first) → start the
///     service and finish in onCreate; effectively a zero-window bounce.
///   • not yet granted (first run only) → request it here; on grant start the
///     service, otherwise post a notification telling the user. Either way finish.
class SyncActivity : Activity() {
    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (hasAnkiPermission()) {
            startSyncAndFinish()
        } else {
            ActivityCompat.requestPermissions(
                this, arrayOf(AnkiBridge.PERMISSION), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) {
            finish()
            return
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startSyncAndFinish()
        } else {
            SyncNotifier.show(
                applicationContext,
                "Anki sync",
                "Grant AnkiDroid access to Interest, then sync again.",
                ongoing = false,
            )
            finish()
        }
    }

    private fun hasAnkiPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, AnkiBridge.PERMISSION) ==
            PackageManager.PERMISSION_GRANTED

    private fun startSyncAndFinish() {
        SyncService.start(this)
        finish()
    }
}
