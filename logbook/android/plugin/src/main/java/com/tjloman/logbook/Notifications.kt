package com.tjloman.logbook

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.godotengine.godot.Dictionary

/**
 * The persistent notification that keeps the service alive, plus the alerts
 * that need to reach you when the phone is in a pocket.
 *
 * Two channels on purpose: the ongoing one is silent and unremovable (Android
 * requires it for a foreground service, and it is also the honest disclosure
 * that the app is logging), while alerts — a severe weather warning, a pack at
 * 15% — are allowed to buzz.
 */
object Notifications {

    const val ONGOING_ID = 4201
    private const val CHANNEL_ONGOING = "logbook_ongoing"
    private const val CHANNEL_ALERT = "logbook_alerts"
    private var alertId = 4300

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ONGOING, "Trip logging", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Shown while the journey is being recorded." }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERT, "Alerts", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Weather warnings and battery alerts." }
        )
    }

    fun ongoing(context: Context, text: String): Notification {
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val openPending = PendingIntent.getActivity(
            context, 0, open ?: Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stop = Intent(context, LogService::class.java).apply {
            action = LogService.ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            context, 1, stop, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(context, CHANNEL_ONGOING)
        else
            @Suppress("DEPRECATION") Notification.Builder(context)
        return builder
            .setContentTitle("Trip Logbook")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(
                Notification.Action.Builder(null, "Stop logging", stopPending).build()
            )
            .build()
    }

    fun update(context: Context, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(ONGOING_ID, ongoing(context, text))
    }

    fun post(context: Context, title: String, body: String, tag: String) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(context, CHANNEL_ALERT)
        else
            @Suppress("DEPRECATION") Notification.Builder(context)
        val notification = builder
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setAutoCancel(true)
            .build()
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(tag, alertId++, notification)
    }

    fun vibrate(context: Context, ms: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION") vibrator.vibrate(ms)
        }
    }

    /** The phone's own battery — the one that decides how long any of this lasts. */
    fun batteryStatus(context: Context): Dictionary {
        val d = Dictionary()
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        d["level"] = if (level >= 0 && scale > 0) level * 100 / scale else -1
        d["charging"] = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return d
    }
}
