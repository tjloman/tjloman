package com.tjloman.logbook

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import androidx.core.content.ContextCompat

/**
 * Calls, read from the system call log rather than watched live.
 *
 * The log is already there after a reboot, after the app was force-stopped,
 * and after a day with the phone off — so re-reading a window of it whenever
 * the app wakes is what makes a call taken in a dead zone still land in the
 * right valley on the map. Each call is keyed by its start time, so re-reads
 * are idempotent.
 */
object CallLogReader {

    fun since(context: Context, sinceMillis: Long): List<LogWriter.Event> {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG)
            != PackageManager.PERMISSION_GRANTED
        ) return emptyList()

        val out = ArrayList<LogWriter.Event>()
        val columns = arrayOf(
            CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE,
            CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME,
        )
        val cursor = try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI, columns,
                "${CallLog.Calls.DATE} > ?", arrayOf(sinceMillis.toString()),
                "${CallLog.Calls.DATE} ASC"
            )
        } catch (_: SecurityException) {
            null
        } ?: return out

        cursor.use { c ->
            while (c.moveToNext()) {
                val started = c.getLong(0)
                val event = LogWriter.Event("call")
                event.time = started / 1000.0
                event.id = "call-${started / 1000}"
                event.fields["seconds"] = c.getLong(1)
                event.fields["direction"] = when (c.getInt(2)) {
                    CallLog.Calls.INCOMING_TYPE -> "in"
                    CallLog.Calls.OUTGOING_TYPE -> "out"
                    CallLog.Calls.MISSED_TYPE -> "missed"
                    CallLog.Calls.REJECTED_TYPE -> "rejected"
                    else -> "other"
                }
                event.fields["number"] = c.getString(3) ?: ""
                event.fields["who"] = c.getString(4) ?: c.getString(3) ?: "Unknown"
                out.add(event)
            }
        }
        return out
    }
}
