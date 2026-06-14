package com.nimee.people_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/// Builds/posts the single Anki-sync notification. The same NOTIFICATION_ID backs
/// both SyncService's mandatory foreground notification and every progress/result
/// update the Dart side pushes over the `notify` channel — so the user sees one
/// notification that morphs from "Syncing…" to the result, never a duplicate.
object SyncNotifier {
    const val CHANNEL_ID = "anki_sync"
    const val NOTIFICATION_ID = 4201

    /// Builds the notification (and ensures the channel exists). Used directly by
    /// SyncService for startForeground; `show` wraps it for the Dart updates.
    fun build(context: Context, title: String, text: String, ongoing: Boolean): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Anki sync",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Progress of problem-note sync to AnkiDroid" }
            manager.createNotificationChannel(channel)
        }

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)

        if (!ongoing) builder.setAutoCancel(true)

        return builder.build()
    }

    fun show(context: Context, title: String, text: String, ongoing: Boolean) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, build(context, title, text, ongoing))
    }
}
