package com.tjloman.logbook

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * The Godot-facing half of the logbook.
 *
 * Godot is the front end. This class does almost nothing itself: it starts
 * [LogService] — a foreground service that owns GPS, Bluetooth, the call log,
 * notifications and the media session — and forwards the service's events up
 * into GDScript for live display.
 *
 * The consequence that matters: the app does not have to be running for the
 * journey to be recorded. The service writes the log files directly and Godot
 * tails them, so a phone locked on a charger in the trailer keeps logging
 * exactly as if the screen were on.
 */
class TripLogbookPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val NAME = "TripLogbook"
        private const val REQ_PERMS = 8801

        /** The live instance, so the service can push events without binding. */
        @Volatile
        var instance: TripLogbookPlugin? = null
    }

    override fun getPluginName() = NAME

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("location_fix", Dictionary::class.java),
        SignalInfo("location_status", Dictionary::class.java),
        SignalInfo("call_logged", Dictionary::class.java),
        SignalInfo("notification_posted", Dictionary::class.java),
        SignalInfo("photo_found", Dictionary::class.java),
        SignalInfo("connectivity_changed", Dictionary::class.java),
        SignalInfo("device_battery_changed", Dictionary::class.java),
        SignalInfo("service_state", Dictionary::class.java),
        SignalInfo("media_changed", Dictionary::class.java),
        SignalInfo("permissions_changed", Dictionary::class.java),
        SignalInfo("ble_state", Dictionary::class.java),
        SignalInfo("ble_device_found", Dictionary::class.java),
        SignalInfo("ble_services_discovered", String::class.java, Array<Any>::class.java),
        SignalInfo("ble_value", String::class.java, String::class.java, ByteArray::class.java),
    )

    override fun onMainCreate(activity: Activity): android.view.View? {
        instance = this
        return null
    }

    override fun onMainDestroy() {
        // Deliberately does NOT stop the service. Swiping the app away is not a
        // statement about the trip; the notification's "Stop logging" action is.
        instance = null
    }

    private val context: Context get() = activity as Context

    // -------------------------------------------------------------- service

    @UsedByGodot
    fun configureService(config: Dictionary) {
        val bundle = Bundle()
        for ((k, v) in config) {
            when (v) {
                is String -> bundle.putString(k, v)
                is Boolean -> bundle.putBoolean(k, v)
                is Int -> bundle.putDouble(k, v.toDouble())
                is Long -> bundle.putDouble(k, v.toDouble())
                is Float -> bundle.putDouble(k, v.toDouble())
                is Double -> bundle.putDouble(k, v)
            }
        }
        val intent = Intent(context, LogService::class.java)
        intent.action = LogService.ACTION_CONFIGURE
        intent.putExtra(LogService.EXTRA_CONFIG, bundle)
        ContextCompat.startForegroundService(context, intent)
    }

    @UsedByGodot
    fun serviceRunning(): Boolean = LogService.running

    @UsedByGodot
    fun startLocation(minSeconds: Double, minMeters: Double, background: Boolean) {
        LogService.post(context, LogService.ACTION_START_LOCATION) {
            putExtra("min_seconds", minSeconds)
            putExtra("min_meters", minMeters)
            putExtra("background", background)
        }
    }

    @UsedByGodot
    fun stopLocation() = LogService.post(context, LogService.ACTION_STOP_LOCATION) {}

    @UsedByGodot
    fun lastKnownLocation(): Dictionary = LogService.lastFix ?: Dictionary()

    // ---------------------------------------------------------- permissions

    /**
     * Android will not grant background location in the same breath as
     * foreground location — the second request is rejected outright unless the
     * first is already held. So this asks in two passes, and the service only
     * claims background capability once it actually has it.
     */
    @UsedByGodot
    fun requestPermissions() {
        val act = activity ?: return
        val wanted = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.READ_CALL_LOG,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            wanted += Manifest.permission.BLUETOOTH_SCAN
            wanted += Manifest.permission.BLUETOOTH_CONNECT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
            wanted += Manifest.permission.READ_MEDIA_IMAGES
        } else {
            wanted += Manifest.permission.READ_EXTERNAL_STORAGE
        }
        val missing = wanted.filter { !granted(it) }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(act, missing.toTypedArray(), REQ_PERMS)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            !granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        ) {
            ActivityCompat.requestPermissions(
                act, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQ_PERMS + 1
            )
        }
        reportPermissions()
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>?, grantResults: IntArray?
    ) {
        reportPermissions()
    }

    private fun granted(perm: String) =
        ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED

    private fun reportPermissions() {
        val d = Dictionary()
        d["location"] = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        d["background_location"] =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        d["call_log"] = granted(Manifest.permission.READ_CALL_LOG)
        d["notifications"] = notificationAccessGranted()
        d["media"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            granted(Manifest.permission.READ_MEDIA_IMAGES) else true
        d["bluetooth"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            granted(Manifest.permission.BLUETOOTH_CONNECT) else true
        emit("permissions_changed", d)
    }

    /**
     * Notification access is not a runtime permission — it is a settings toggle
     * the user flips by hand. It is also what grants access to other apps'
     * media sessions, which is how the Spotify controls work without an
     * account, so it is worth granting even if message logging is off.
     */
    private fun notificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver, "enabled_notification_listeners"
        ) ?: return false
        val want = ComponentName(context, NotificationCapture::class.java).flattenToString()
        return flat.split(":").any { it == want }
    }

    @UsedByGodot
    fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    // --------------------------------------------------------------- device

    @UsedByGodot
    fun netStatus(): Dictionary {
        val d = Dictionary()
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        val online = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        val wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        d["online"] = online
        d["kind"] = if (!online) "none" else if (wifi) "wifi" else "cell"
        // NOT_METERED is the honest signal: a phone hotspot reports as wifi but
        // is metered, and a map corridor over it is a real bill.
        d["metered"] = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
        return d
    }

    @UsedByGodot
    fun deviceBattery(): Dictionary = Notifications.batteryStatus(context)

    @UsedByGodot
    fun vibrate(ms: Int) = Notifications.vibrate(context, ms.toLong())

    @UsedByGodot
    fun notify(title: String, body: String, tag: String) =
        Notifications.post(context, title, body, tag)

    @UsedByGodot
    fun queryCallLog(sinceUnix: Double) =
        LogService.post(context, LogService.ACTION_SCAN_CALLS) { putExtra("since", sinceUnix) }

    @UsedByGodot
    fun queryPhotos(sinceUnix: Double) =
        LogService.post(context, LogService.ACTION_SCAN_PHOTOS) { putExtra("since", sinceUnix) }

    // ---------------------------------------------------------------- media

    @UsedByGodot
    fun mediaPlayPause() = MediaBridge.playPause(context)

    @UsedByGodot
    fun mediaNext() = MediaBridge.next(context)

    @UsedByGodot
    fun mediaPrev() = MediaBridge.previous(context)

    @UsedByGodot
    fun mediaVolume(delta: Int) = MediaBridge.volume(context, delta)

    @UsedByGodot
    fun mediaLaunch(packageName: String) = MediaBridge.launchAndPlay(context, packageName)

    @UsedByGodot
    fun nowPlaying(): Dictionary = MediaBridge.nowPlaying(context)

    // ------------------------------------------------------------------ ble

    @UsedByGodot
    fun bleScan(seconds: Double) =
        LogService.post(context, LogService.ACTION_BLE_SCAN) { putExtra("seconds", seconds) }

    @UsedByGodot
    fun bleStopScan() = LogService.post(context, LogService.ACTION_BLE_STOP_SCAN) {}

    @UsedByGodot
    fun bleConnect(address: String) =
        LogService.post(context, LogService.ACTION_BLE_CONNECT) { putExtra("address", address) }

    // Every call is scoped to one machine: the rig is a bike and a powered
    // cart, connected at the same time.

    @UsedByGodot
    fun bleDisconnect(address: String) =
        LogService.post(context, LogService.ACTION_BLE_DISCONNECT) {
            putExtra("address", address)
        }

    @UsedByGodot
    fun bleSubscribe(address: String, service: String, characteristic: String) =
        LogService.post(context, LogService.ACTION_BLE_SUBSCRIBE) {
            putExtra("address", address)
            putExtra("service", service)
            putExtra("characteristic", characteristic)
        }

    @UsedByGodot
    fun bleRead(address: String, service: String, characteristic: String) =
        LogService.post(context, LogService.ACTION_BLE_READ) {
            putExtra("address", address)
            putExtra("service", service)
            putExtra("characteristic", characteristic)
        }

    @UsedByGodot
    fun bleWrite(
        address: String, service: String, characteristic: String,
        data: ByteArray, withResponse: Boolean
    ) = LogService.post(context, LogService.ACTION_BLE_WRITE) {
        putExtra("address", address)
        putExtra("service", service)
        putExtra("characteristic", characteristic)
        putExtra("data", data)
        putExtra("with_response", withResponse)
    }

    // ----------------------------------------------------------------- emit

    /** Signals must reach Godot on its own thread; the service runs on ours. */
    fun emit(signal: String, vararg args: Any) {
        runOnRenderThread { emitSignal(signal, *args) }
    }
}
