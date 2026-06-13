package com.nimee.people_tracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/// Posts the Anki-sync progress/result notification so the user sees the
/// outcome without Interest stealing the foreground from Obsidian.
object SyncNotifier {
    private const val CHANNEL_ID = "anki_sync"
    private const val NOTIFICATION_ID = 4201

    fun show(context: Context, title: String, text: String, ongoing: Boolean) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Anki sync",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Progress of problem-note sync to AnkiDroid" }
            manager.createNotificationChannel(channel)
        }

        val builder = android.app.Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)

        if (!ongoing) builder.setAutoCancel(true)

        manager.notify(NOTIFICATION_ID, builder.build())
    }
}
