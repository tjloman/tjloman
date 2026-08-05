package com.tjloman.logbook

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Brings the logger back after a reboot.
 *
 * On a long trip the phone will restart — a flat battery overnight, a crash, a
 * system update at a motel. Without this the trip quietly stops being recorded
 * and you find out days later. With it, the service is up again before you
 * unlock the screen, using the trip directory it was last configured with.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return
        val start = Intent(context, LogService::class.java)
        start.action = LogService.ACTION_START_LOCATION
        ContextCompat.startForegroundService(context, start)
    }
}
