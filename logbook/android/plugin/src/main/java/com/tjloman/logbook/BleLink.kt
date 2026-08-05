package com.tjloman.logbook

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import androidx.core.content.ContextCompat
import org.godotengine.godot.Dictionary
import java.util.UUID

/**
 * The Bluetooth LE link to the bike, living inside the service so the pack is
 * still being sampled when the app is closed.
 *
 * This class is deliberately dumb: it connects, subscribes, and moves bytes.
 * It knows nothing about what a BMS frame means — that lives in GDScript, in
 * the profiles, where it can be changed without rebuilding an APK. Getting a
 * new bike supported should be a text edit, not a toolchain.
 */
class BleLink(private val service: LogService, private val worker: Handler) {

    companion object {
        private const val CCCD = "00002902-0000-1000-8000-00805f9b34fb"
        private const val RECONNECT_MS = 20_000L
    }

    private var gatt: BluetoothGatt? = null
    private var scanning = false
    private var address = ""
    private var wantConnection = false
    private var lastSampleAt = 0L
    private val pending = ArrayDeque<() -> Unit>()
    private var busy = false

    private val adapter: BluetoothAdapter?
        get() = (service.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun allowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(service, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    // ----------------------------------------------------------------- scan

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val d = Dictionary()
            d["address"] = result.device.address
            d["name"] = try {
                result.device.name ?: result.scanRecord?.deviceName ?: ""
            } catch (_: SecurityException) { "" }
            d["rssi"] = result.rssi
            TripLogbookPlugin.instance?.emit("ble_device_found", d)
        }
    }

    fun scan(seconds: Double) {
        if (!allowed() || scanning) return
        val scanner = adapter?.bluetoothLeScanner ?: return
        try {
            scanner.startScan(scanCallback)
            scanning = true
            worker.postDelayed({ stopScan() }, (seconds * 1000).toLong())
        } catch (_: SecurityException) {
        }
    }

    fun stopScan() {
        if (!scanning) return
        try { adapter?.bluetoothLeScanner?.stopScan(scanCallback) } catch (_: SecurityException) {}
        scanning = false
    }

    // -------------------------------------------------------------- connect

    fun connect(deviceAddress: String) {
        if (!allowed() || deviceAddress.isEmpty()) return
        address = deviceAddress
        wantConnection = true
        val device = try { adapter?.getRemoteDevice(deviceAddress) } catch (_: Exception) { null }
            ?: return
        gatt?.close()
        gatt = try {
            device.connectGatt(service, true, callback, BluetoothGatt.TRANSPORT_LE)
        } catch (_: SecurityException) {
            null
        }
    }

    fun disconnect() {
        wantConnection = false
        try { gatt?.disconnect(); gatt?.close() } catch (_: SecurityException) {}
        gatt = null
        emitState(false)
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                try { g.discoverServices() } catch (_: SecurityException) {}
                emitState(true)
            } else {
                emitState(false)
                // autoConnect=true means the stack retries on its own, but a
                // bike that was switched off needs a fresh attempt when it
                // comes back — hence the timer as well.
                if (wantConnection) worker.postDelayed({ connect(address) }, RECONNECT_MS)
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val services = ArrayList<Dictionary>()
            for (s in g.services) {
                val d = Dictionary()
                d["service"] = s.uuid.toString()
                d["characteristics"] = s.characteristics.map { it.uuid.toString() }.toTypedArray()
                services.add(d)
            }
            TripLogbookPlugin.instance?.emit("ble_services_discovered", services.toTypedArray())
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray
        ) = deliver(c.uuid, value)

        @Deprecated("Pre-33 signature, still the one older devices call")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            deliver(c.uuid, c.value ?: ByteArray(0))
        }

        override fun onCharacteristicRead(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int
        ) {
            deliver(c.uuid, value)
            next()
        }

        @Deprecated("Pre-33 signature, still the one older devices call")
        override fun onCharacteristicRead(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int
        ) {
            @Suppress("DEPRECATION")
            deliver(c.uuid, c.value ?: ByteArray(0))
            next()
        }

        override fun onCharacteristicWrite(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int
        ) = next()

        override fun onDescriptorWrite(
            g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int
        ) = next()
    }

    private fun deliver(uuid: UUID, value: ByteArray) {
        TripLogbookPlugin.instance?.emit("ble_value", uuid.toString(), value)
        // The app decodes these into a state dictionary; the service only needs
        // to know that something arrived, so it can log a periodic sample even
        // when nothing is watching.
        val now = System.currentTimeMillis()
        if (now - lastSampleAt > 300_000L) {
            lastSampleAt = now
            val fields = HashMap<String, Any>()
            fields["raw"] = value.joinToString(" ") { "%02X".format(it) }
            fields["uuid"] = uuid.toString()
            service.onBatterySample(fields)
        }
    }

    private fun emitState(connected: Boolean) {
        val d = Dictionary()
        d["connected"] = connected
        d["address"] = address
        d["name"] = try { gatt?.device?.name ?: "" } catch (_: SecurityException) { "" }
        TripLogbookPlugin.instance?.emit("ble_state", d)
    }

    // --------------------------------------------------------------- access

    /**
     * Android's GATT stack allows exactly one outstanding operation at a time
     * and silently drops the rest, which is the single most common source of
     * "it works for ten seconds then stops". Everything therefore goes through
     * one queue, advanced by the completion callbacks.
     */
    private fun enqueue(op: () -> Unit) {
        pending.addLast(op)
        if (!busy) next()
    }

    private fun next() {
        val op = pending.removeFirstOrNull()
        if (op == null) {
            busy = false
            return
        }
        busy = true
        try { op() } catch (_: Exception) { busy = false }
    }

    private fun find(service: String, characteristic: String): BluetoothGattCharacteristic? {
        val g = gatt ?: return null
        val s = g.getService(UUID.fromString(service)) ?: return null
        return s.getCharacteristic(UUID.fromString(characteristic))
    }

    fun subscribe(serviceUuid: String, characteristic: String) = enqueue {
        val g = gatt
        val c = find(serviceUuid, characteristic)
        if (g == null || c == null) { next(); return@enqueue }
        try {
            g.setCharacteristicNotification(c, true)
            val cccd = c.getDescriptor(UUID.fromString(CCCD))
            if (cccd != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                } else {
                    @Suppress("DEPRECATION")
                    run {
                        cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        g.writeDescriptor(cccd)
                    }
                }
            } else {
                next()
            }
        } catch (_: SecurityException) {
            next()
        }
    }

    fun read(serviceUuid: String, characteristic: String) = enqueue {
        val c = find(serviceUuid, characteristic)
        if (c == null) { next(); return@enqueue }
        try { gatt?.readCharacteristic(c) } catch (_: SecurityException) { next() }
    }

    fun write(
        serviceUuid: String, characteristic: String, data: ByteArray, withResponse: Boolean
    ) = enqueue {
        val g = gatt
        val c = find(serviceUuid, characteristic)
        if (g == null || c == null) { next(); return@enqueue }
        val type = if (withResponse) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(c, data, type)
            } else {
                @Suppress("DEPRECATION")
                run {
                    c.writeType = type
                    c.value = data
                    g.writeCharacteristic(c)
                }
            }
        } catch (_: SecurityException) {
            next()
        }
    }
}
