package com.tjloman.logbook

import org.godotengine.godot.Dictionary
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter

/**
 * The service's half of the log files.
 *
 * Two files, both append-only, both single-writer:
 *
 *   track.ndjson    one array per line: [t, lat, lon, alt, spd, hdg, acc]
 *   sensor.ndjson   one object per line: calls, messages, music, photos,
 *                   battery samples
 *
 * Godot tails both and never writes to either. That is the whole concurrency
 * design — no locks, no database, no coordination — and it is why a phone
 * killed mid-write costs one truncated line instead of a corrupt trip.
 *
 * Fixes are flushed in small batches; everything else flushes immediately,
 * because events are rare and losing the note about the flat tyre would be
 * worse than the syscall.
 */
class LogWriter {

    /** A logged happening. `kind` matches the GDScript `Ev` constants. */
    class Event(val kind: String) {
        val fields: MutableMap<String, Any> = LinkedHashMap()
        var time: Double = System.currentTimeMillis() / 1000.0
        var id: String = ""

        fun json(): String {
            val o = JSONObject()
            o.put("kind", kind)
            o.put("t", time)
            o.put("id", if (id.isEmpty()) "$kind-${time.toLong()}" else id)
            for ((k, v) in fields) o.put(k, v)
            return o.toString()
        }

        fun toGodot(): Dictionary {
            val d = Dictionary()
            d["kind"] = kind
            d["t"] = time
            d["id"] = if (id.isEmpty()) "$kind-${time.toLong()}" else id
            for ((k, v) in fields) d[k] = v
            return d
        }
    }

    var fixCount: Int = 0
        private set

    private var dir: File? = null
    private var track: OutputStreamWriter? = null
    private var sensor: OutputStreamWriter? = null
    private var unflushed = 0

    /**
     * Point the writer at a trip directory — the same one Godot has open. The
     * path comes from GDScript (`ProjectSettings.globalize_path`), so the two
     * processes can never disagree about where the trip lives.
     */
    @Synchronized
    fun open(directory: File) {
        if (dir?.absolutePath == directory.absolutePath && track != null) return
        close()
        directory.mkdirs()
        dir = directory
        track = OutputStreamWriter(FileOutputStream(File(directory, "track.ndjson"), true))
        sensor = OutputStreamWriter(FileOutputStream(File(directory, "sensor.ndjson"), true))
        fixCount = countLines(File(directory, "track.ndjson"))
    }

    @Synchronized
    fun appendFix(
        t: Double, lat: Double, lon: Double, alt: Double,
        speed: Double, bearing: Double, accuracy: Double
    ) {
        val out = track ?: return
        try {
            // Six decimals is ~0.1 m, finer than any consumer GPS, and keeps a
            // day of riding to about a megabyte.
            out.write(
                String.format(
                    java.util.Locale.US,
                    "[%.1f,%.6f,%.6f,%.1f,%.2f,%.1f,%.1f]\n",
                    t, lat, lon, alt, speed, bearing, accuracy
                )
            )
            fixCount++
            if (++unflushed >= 10) {
                out.flush()
                unflushed = 0
            }
        } catch (_: Exception) {
            // A full disk or a yanked SD card must not take the service down;
            // the ride keeps going and the next write may well succeed.
        }
    }

    @Synchronized
    fun appendEvent(event: Event) {
        val out = sensor ?: return
        try {
            out.write(event.json())
            out.write("\n")
            out.flush()
        } catch (_: Exception) {
        }
    }

    @Synchronized
    fun flush() {
        try { track?.flush(); sensor?.flush() } catch (_: Exception) {}
        unflushed = 0
    }

    @Synchronized
    fun close() {
        try { track?.flush(); track?.close() } catch (_: Exception) {}
        try { sensor?.flush(); sensor?.close() } catch (_: Exception) {}
        track = null
        sensor = null
    }

    private fun countLines(file: File): Int {
        if (!file.exists()) return 0
        return try {
            file.bufferedReader().useLines { lines -> lines.count() }
        } catch (_: Exception) {
            0
        }
    }
}
