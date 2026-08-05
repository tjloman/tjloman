package com.tjloman.logbook

import android.Manifest
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import androidx.core.content.ContextCompat
import org.godotengine.godot.Dictionary
import java.io.File

/**
 * The part of the app that does not stop when the app does.
 *
 * A foreground service with a location type, holding a partial wake lock: it
 * keeps a GPS fix stream running with the screen off, samples the ebike's BMS
 * over Bluetooth, pulls in calls and photos, and writes all of it straight to
 * the same append-only files the Godot front end reads.
 *
 * Everything here is written to survive the ordinary indignities of a long
 * trip: the process being killed for memory and restarted (START_STICKY plus
 * a boot receiver), the phone rebooting on a dead battery, and the user
 * swiping the app away without meaning to end the day.
 *
 * The single rule that keeps the two processes from corrupting each other:
 * this service writes track.ndjson and sensor.ndjson and never reads them;
 * Godot reads them and never writes them.
 */
class LogService : Service(), LocationListener {

    companion object {
        const val ACTION_CONFIGURE = "configure"
        const val ACTION_START_LOCATION = "start_location"
        const val ACTION_STOP_LOCATION = "stop_location"
        const val ACTION_SCAN_CALLS = "scan_calls"
        const val ACTION_SCAN_PHOTOS = "scan_photos"
        const val ACTION_BLE_SCAN = "ble_scan"
        const val ACTION_BLE_STOP_SCAN = "ble_stop_scan"
        const val ACTION_BLE_CONNECT = "ble_connect"
        const val ACTION_BLE_DISCONNECT = "ble_disconnect"
        const val ACTION_BLE_SUBSCRIBE = "ble_subscribe"
        const val ACTION_BLE_READ = "ble_read"
        const val ACTION_BLE_WRITE = "ble_write"
        const val ACTION_STOP = "stop_everything"
        const val EXTRA_CONFIG = "config"

        @Volatile var running = false
        @Volatile var lastFix: Dictionary? = null

        /** Send a one-shot command to the service, starting it if need be. */
        fun post(context: Context, action: String, build: Intent.() -> Unit) {
            val intent = Intent(context, LogService::class.java)
            intent.action = action
            intent.build()
            ContextCompat.startForegroundService(context, intent)
        }
    }

    private lateinit var writer: LogWriter
    private lateinit var worker: Handler
    private var wakeLock: PowerManager.WakeLock? = null
    private var ble: BleLink? = null

    // Sampling policy, mirrored from the app's settings.
    private var minSeconds = 3.0
    private var minMeters = 8.0
    private var idleSeconds = 120.0
    private var maxAccuracy = 60.0
    private var captureCalls = true
    private var captureMessages = true
    private var captureBodies = false
    private var capturePhotos = true
    private var captureMusic = true
    private var bleAddresses = listOf<String>()
    private var bleSampleSeconds = 300.0

    private var lastKeptTime = 0L
    private var lastKeptLat = 0.0
    private var lastKeptLon = 0.0
    private var locating = false

    override fun onCreate() {
        super.onCreate()
        val thread = HandlerThread("logbook").apply { start() }
        worker = Handler(thread.looper)
        writer = LogWriter()
        Notifications.createChannels(this)
        NotificationCapture.service = this
        MediaBridge.onTrack = { info -> onTrackChanged(info) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(Notifications.ONGOING_ID, Notifications.ongoing(this, statusLine()))
        running = true
        when (intent?.action) {
            ACTION_CONFIGURE -> applyConfig(intent.getBundleExtra(EXTRA_CONFIG))
            ACTION_START_LOCATION -> startLocating()
            ACTION_STOP_LOCATION -> stopLocating()
            ACTION_SCAN_CALLS -> worker.post { scanCalls(intent.getDoubleExtra("since", 0.0)) }
            ACTION_SCAN_PHOTOS -> worker.post { scanPhotos(intent.getDoubleExtra("since", 0.0)) }
            ACTION_STOP -> { stopEverything(); return START_NOT_STICKY }
            else -> handleBle(intent)
        }
        // START_STICKY: if Android kills us for memory on a long ride, it brings
        // us back. The GPS gap shows up as a segment break, not a lost trip.
        return START_STICKY
    }

    private fun applyConfig(bundle: Bundle?) {
        if (bundle == null) return
        bundle.getString("dir")?.let { writer.open(File(it)) }
        minSeconds = bundle.getDouble("min_seconds", minSeconds)
        minMeters = bundle.getDouble("min_meters", minMeters)
        idleSeconds = bundle.getDouble("idle_seconds", idleSeconds)
        maxAccuracy = bundle.getDouble("max_accuracy_m", maxAccuracy)
        captureCalls = bundle.getBoolean("capture_calls", captureCalls)
        captureMessages = bundle.getBoolean("capture_messages", captureMessages)
        captureBodies = bundle.getBoolean("capture_message_bodies", captureBodies)
        capturePhotos = bundle.getBoolean("capture_photos", capturePhotos)
        captureMusic = bundle.getBoolean("capture_music", captureMusic)
        bleSampleSeconds = bundle.getDouble("ble_sample_seconds", bleSampleSeconds)
        // A comma-separated list because a Bundle of scalars is all the plugin
        // marshals — the rig currently means the bike and the cart.
        val addresses = (bundle.getString("ble_addresses") ?: "")
            .split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (addresses.isNotEmpty() && addresses != bleAddresses) {
            bleAddresses = addresses
            worker.post { bleEnsureConnected() }
        }
        if (!locating) startLocating()
    }

    // ------------------------------------------------------------- location

    private fun startLocating() {
        if (locating) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) return
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        // Ask the OS for updates a little finer than we intend to keep, so the
        // distance filter has something to filter. The real thinning happens in
        // onLocationChanged.
        val intervalMs = (minSeconds * 1000).toLong().coerceAtLeast(1000L)
        try {
            lm.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, intervalMs, minMeters.toFloat() / 2f, this,
                worker.looper
            )
            // The network provider costs nothing extra and covers the minutes
            // after a cold start when GPS has no sky yet.
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER, intervalMs * 4, 50f, this, worker.looper
                )
            }
        } catch (_: SecurityException) {
            return
        }
        locating = true
        acquireWakeLock()
        emitStatus()
    }

    private fun stopLocating() {
        if (!locating) return
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try { lm.removeUpdates(this) } catch (_: SecurityException) {}
        locating = false
        releaseWakeLock()
        emitStatus()
    }

    override fun onLocationChanged(location: Location) {
        val t = location.time / 1000.0
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0
        if (accuracy > maxAccuracy && lastKeptTime > 0L) return

        val dtSeconds = t - lastKeptTime / 1000.0
        val distance = if (lastKeptTime == 0L) Double.MAX_VALUE else
            distanceMeters(lastKeptLat, lastKeptLon, location.latitude, location.longitude)

        val fix = Dictionary()
        fix["t"] = t
        fix["lat"] = location.latitude
        fix["lon"] = location.longitude
        fix["alt"] = if (location.hasAltitude()) location.altitude else 0.0
        fix["speed"] = if (location.hasSpeed()) location.speed.toDouble() else 0.0
        fix["bearing"] = if (location.hasBearing()) location.bearing.toDouble() else 0.0
        fix["accuracy"] = accuracy
        fix["provider"] = location.provider ?: "gps"
        lastFix = fix
        // The app gets every fix for a live speed readout; only the thinned
        // ones are written, and only the written ones become the track.
        TripLogbookPlugin.instance?.emit("location_fix", fix)

        if (lastKeptTime > 0L) {
            if (dtSeconds < minSeconds) return
            if (distance < minMeters && dtSeconds < idleSeconds) return
        }
        lastKeptTime = location.time
        lastKeptLat = location.latitude
        lastKeptLon = location.longitude
        writer.appendFix(
            t, location.latitude, location.longitude,
            fix["alt"] as Double, fix["speed"] as Double, fix["bearing"] as Double, accuracy
        )
        Notifications.update(this, statusLine())
    }

    override fun onProviderEnabled(provider: String) = emitStatus()
    override fun onProviderDisabled(provider: String) = emitStatus()

    private fun emitStatus() {
        val d = Dictionary()
        d["logging"] = locating
        d["fixes"] = writer.fixCount
        TripLogbookPlugin.instance?.emit("location_status", d)
    }

    private fun statusLine(): String {
        val fix = lastFix ?: return "Waiting for a fix"
        val accuracy = (fix["accuracy"] as? Double)?.toInt() ?: 0
        return "Logging · ${writer.fixCount} fixes · ±${accuracy}m"
    }

    // ------------------------------------------------------------- captures

    /**
     * The call log is the source of truth, not a live callback: it is already
     * there after a reboot, and re-reading a window of it is how a call taken
     * while the app was closed still lands on the map.
     */
    private fun scanCalls(sinceUnix: Double) {
        if (!captureCalls) return
        for (call in CallLogReader.since(this, (sinceUnix * 1000).toLong())) {
            writer.appendEvent(call)
            TripLogbookPlugin.instance?.emit("call_logged", call.toGodot())
        }
    }

    private fun scanPhotos(sinceUnix: Double) {
        if (!capturePhotos) return
        for (photo in PhotoScanner.since(this, (sinceUnix * 1000).toLong())) {
            writer.appendEvent(photo)
            TripLogbookPlugin.instance?.emit("photo_found", photo.toGodot())
        }
    }

    /** Called by [NotificationCapture] for every notification we are shown. */
    fun onNotification(event: LogWriter.Event, body: String?) {
        if (!captureMessages) return
        if (captureBodies && body != null) event.fields["text"] = body
        writer.appendEvent(event)
        TripLogbookPlugin.instance?.emit("notification_posted", event.toGodot())
    }

    private fun onTrackChanged(info: Dictionary) {
        TripLogbookPlugin.instance?.emit("media_changed", info)
        if (!captureMusic) return
        val title = info["title"] as? String ?: return
        if (title.isEmpty()) return
        val event = LogWriter.Event("music")
        event.fields["title"] = title
        event.fields["artist"] = info["artist"] as? String ?: ""
        event.fields["album"] = info["album"] as? String ?: ""
        event.fields["app"] = info["app"] as? String ?: ""
        stampPosition(event)
        writer.appendEvent(event)
    }

    /**
     * Give an event the position it happened at. The service always has a
     * fresher fix than the app does, and an event without coordinates is just
     * a diary entry — the whole point is that it lands on the route.
     */
    private fun stampPosition(event: LogWriter.Event) {
        val fix = lastFix ?: return
        event.fields["lat"] = fix["lat"]
        event.fields["lon"] = fix["lon"]
    }

    // ------------------------------------------------------------------ ble

    private fun handleBle(intent: Intent?) {
        val action = intent?.action ?: return
        worker.post {
            val link = bleEnsureLink()
            val address = intent.getStringExtra("address") ?: ""
            when (action) {
                ACTION_BLE_SCAN -> link.scan(intent.getDoubleExtra("seconds", 8.0))
                ACTION_BLE_STOP_SCAN -> link.stopScan()
                ACTION_BLE_CONNECT -> {
                    if (address.isNotEmpty() && !bleAddresses.contains(address)) {
                        bleAddresses = bleAddresses + address
                    }
                    link.connect(address)
                }
                ACTION_BLE_DISCONNECT -> link.disconnect(address)
                ACTION_BLE_SUBSCRIBE -> link.subscribe(
                    address,
                    intent.getStringExtra("service") ?: "",
                    intent.getStringExtra("characteristic") ?: ""
                )
                ACTION_BLE_READ -> link.read(
                    address,
                    intent.getStringExtra("service") ?: "",
                    intent.getStringExtra("characteristic") ?: ""
                )
                ACTION_BLE_WRITE -> link.write(
                    address,
                    intent.getStringExtra("service") ?: "",
                    intent.getStringExtra("characteristic") ?: "",
                    intent.getByteArrayExtra("data") ?: ByteArray(0),
                    intent.getBooleanExtra("with_response", false)
                )
            }
        }
    }

    private fun bleEnsureLink(): BleLink {
        var link = ble
        if (link == null) {
            link = BleLink(this, worker)
            ble = link
        }
        return link
    }

    private fun bleEnsureConnected() {
        val link = bleEnsureLink()
        for (address in bleAddresses) link.connect(address)
    }

    /**
     * Called by [BleLink] with a slow raw sample from one machine. Deliberately
     * slow: a BMS chatters every second and a trip does not need 80,000 rows of
     * it — but a pack curve should still exist for the hours the app was not
     * running to decode anything.
     */
    fun onBatterySample(fields: MutableMap<String, Any>) {
        val event = LogWriter.Event("battery")
        event.fields.putAll(fields)
        stampPosition(event)
        writer.appendEvent(event)
    }

    // --------------------------------------------------------------- upkeep

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        // A partial lock keeps the CPU alive for GPS callbacks while the screen
        // sleeps. It is the difference between a continuous track and a track
        // that stops whenever the phone is in a bag.
        val lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "logbook:gps")
        lock.setReferenceCounted(false)
        lock.acquire()
        wakeLock = lock
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun stopEverything() {
        stopLocating()
        ble?.disconnect()
        writer.close()
        running = false
        NotificationCapture.service = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        writer.close()
        releaseWakeLock()
        running = false
        NotificationCapture.service = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val out = FloatArray(1)
        Location.distanceBetween(lat1, lon1, lat2, lon2, out)
        return out[0].toDouble()
    }
}
