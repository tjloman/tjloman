package com.tjloman.logbook

import android.content.Context
import android.provider.MediaStore

/**
 * Photos taken during the trip, found through MediaStore.
 *
 * The camera app is the camera app — nobody wants to shoot through a logbook.
 * So pictures are taken normally and matched afterwards: MediaStore gives the
 * file and the moment, and if the picture has no location of its own the track
 * supplies one. That is the payoff of logging position continuously: every
 * photo is placed, even the ones shot in airplane mode.
 */
object PhotoScanner {

    fun since(context: Context, sinceMillis: Long): List<LogWriter.Event> {
        val out = ArrayList<LogWriter.Event>()
        val columns = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
        )
        val cursor = try {
            context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, columns,
                "${MediaStore.Images.Media.DATE_TAKEN} > ?", arrayOf(sinceMillis.toString()),
                "${MediaStore.Images.Media.DATE_TAKEN} ASC"
            )
        } catch (_: SecurityException) {
            null
        } ?: return out

        cursor.use { c ->
            while (c.moveToNext()) {
                val taken = c.getLong(1)
                if (taken <= 0L) continue
                val event = LogWriter.Event("photo")
                event.time = taken / 1000.0
                event.id = "photo-${taken / 1000}"
                event.fields["file"] = c.getString(2) ?: ""
                event.fields["width"] = c.getInt(3)
                event.fields["height"] = c.getInt(4)
                out.add(event)
            }
        }
        return out
    }
}
