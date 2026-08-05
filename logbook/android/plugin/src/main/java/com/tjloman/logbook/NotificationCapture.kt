package com.tjloman.logbook

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Messenger activity, and the key that unlocks media session access.
 *
 * Two jobs in one component:
 *
 *   1. Every notification from a messaging app becomes a logbook entry — who,
 *      which app, when — so the timeline shows the conversation you had at the
 *      overlook without anybody having to remember it.
 *   2. Being an enabled notification listener is what Android accepts in place
 *      of the system-only MEDIA_CONTENT_CONTROL permission, so this is also
 *      what lets the app read and drive Spotify's media session.
 *
 * Message *text* is only recorded when explicitly switched on in Settings.
 * The default is metadata: the sender and the time are enough to remember a
 * conversation, and the rest is other people's words.
 */
class NotificationCapture : NotificationListenerService() {

    companion object {
        /** Set by the service while it is alive. */
        @Volatile
        var service: LogService? = null

        /** Apps whose notifications are diary material rather than noise. */
        private val MESSAGING = listOf(
            "com.google.android.apps.messaging", "com.android.mms",
            "org.thoughtcrime.securesms",            // Signal
            "com.whatsapp", "com.facebook.orca",     // WhatsApp, Messenger
            "org.telegram.messenger", "com.discord",
            "com.instagram.android", "com.snapchat.android",
            "com.Slack", "com.google.android.gm",
        )
    }

    override fun onListenerConnected() {
        // Sessions can only be enumerated once we are connected as a listener.
        MediaBridge.watch(applicationContext)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val target = service ?: return
        val pkg = sbn.packageName ?: return
        // A media notification is not a message, but it is a reliable hint that
        // the playing app changed — cheaper than polling for it.
        if (sbn.notification?.category == Notification.CATEGORY_TRANSPORT) {
            MediaBridge.watch(applicationContext)
            return
        }
        if (!MESSAGING.any { pkg.startsWith(it) }) return
        if (sbn.isOngoing) return   // "syncing…" and other permanent fixtures

        val extras = sbn.notification?.extras
        val who = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val body = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()

        val event = LogWriter.Event("message")
        event.time = sbn.postTime / 1000.0
        event.id = "message-${sbn.postTime}"
        event.fields["app"] = appLabel(pkg)
        event.fields["package"] = pkg
        event.fields["who"] = who
        target.onNotification(event, body)
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }
}
