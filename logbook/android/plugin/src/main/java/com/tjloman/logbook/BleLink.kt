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
 * The Bluetooth LE links to the rig, living inside the service so the packs
 * are still being sampled when the app is closed.
 *
 * Plural links: the rig is a bike and a powered cart, two peripherals with
 * their own packs, and Android is perfectly happy holding several GATT
 * connections at once — as long as each one gets its own operation queue. The
 * stack allows exactly one outstanding operation *per connection* and silently
 * drops the rest, which is the single most common cause of "it worked for ten
 * seconds and then stopped".
 *
 * This class is deliberately dumb: it connects, subscribes, and moves bytes.
 * It knows nothing about what a BMS or cart frame means — that lives in
 * GDScript, in the profiles, where it can be changed without rebuilding an
 * APK. Supporting a new machine should be a text edit, not a toolchain.
 */
class BleLink(private val service: LogService, private val worker: Handler) {

    companion object {
        private const val CCCD = "00002902-0000-1000-8000-00805f9b34fb"
        private const val RECONNECT_MS = 20_000L
    }

    /** One connected machine: its GATT handle and its own operation queue. */
    private class Conn(val address: String) {
        var gatt: BluetoothGatt? = null
        var want = true
        var lastSampleAt = 0L
        val pending = ArrayDeque<() -> Unit>()
        var busy = false
    }

    private val conns = HashMap<String, Conn>()
    private var scanning = false

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
        val conn = conns.getOrPut(deviceAddress) { Conn(deviceAddress) }
        conn.want = true
        val device = try { adapter?.getRemoteDevice(deviceAddress) } catch (_: Exception) { null }
            ?: return
        try { conn.gatt?.close() } catch (_: SecurityException) {}
        conn.gatt = try {
            // autoConnect=true: the stack keeps trying in the background, which
            // is what reconnects the cart when it comes back into range after a
            // stop without the app doing anything.
            device.connectGatt(service, true, callback, BluetoothGatt.TRANSPORT_LE)
        } catch (_: SecurityException) {
            null
        }
    }

    /** Disconnect one machine, or everything when the address is empty. */
    fun disconnect(deviceAddress: String = "") {
        val targets = if (deviceAddress.isEmpty()) conns.values.toList()
        else listOfNotNull(conns[deviceAddress])
        for (conn in targets) {
            conn.want = false
            try { conn.gatt?.disconnect(); conn.gatt?.close() } catch (_: SecurityException) {}
            conn.gatt = null
            emitState(conn.address, false, "")
        }
    }

    private fun connFor(gatt: BluetoothGatt): Conn? = conns[gatt.device.address]

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            val conn = connFor(g) ?: return
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                try { g.discoverServices() } catch (_: SecurityException) {}
                emitState(conn.address, true, deviceName(g))
            } else {
                // A dropped link must not leave its queue jammed: the machine
                // that comes back is the same object.
                conn.pending.clear()
                conn.busy = false
                emitState(conn.address, false, deviceName(g))
                // autoConnect retries on its own, but a cart that was switched
                // off needs a fresh attempt when it comes back — hence the
                // timer as well.
                if (conn.want) worker.postDelayed({ connect(conn.address) }, RECONNECT_MS)
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
            TripLogbookPlugin.instance?.emit(
                "ble_services_discovered", g.device.address, services.toTypedArray()
            )
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray
        ) = deliver(g, c.uuid, value)

        @Deprecated("Pre-33 signature, still the one older devices call")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            deliver(g, c.uuid, c.value ?: ByteArray(0))
        }

        override fun onCharacteristicRead(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int
        ) {
            deliver(g, c.uuid, value)
            next(connFor(g))
        }

        @Deprecated("Pre-33 signature, still the one older devices call")
        override fun onCharacteristicRead(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int
        ) {
            @Suppress("DEPRECATION")
            deliver(g, c.uuid, c.value ?: ByteArray(0))
            next(connFor(g))
        }

        override fun onCharacteristicWrite(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int
        ) = next(connFor(g))

        override fun onDescriptorWrite(
            g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int
        ) = next(connFor(g))
    }

    private fun deviceName(g: BluetoothGatt): String =
        try { g.device.name ?: "" } catch (_: SecurityException) { "" }

    private fun deliver(g: BluetoothGatt, uuid: UUID, value: ByteArray) {
        val address = g.device.address
        TripLogbookPlugin.instance?.emit("ble_value", address, uuid.toString(), value)
        // The app decodes these into a state dictionary; the service only keeps
        // a slow raw sample of its own, so a pack curve still exists for the
        // hours when nothing was watching.
        val conn = conns[address] ?: return
        val now = System.currentTimeMillis()
        if (now - conn.lastSampleAt > 300_000L) {
            conn.lastSampleAt = now
            val fields = HashMap<String, Any>()
            fields["address"] = address
            fields["uuid"] = uuid.toString()
            fields["raw"] = value.joinToString(" ") { "%02X".format(it) }
            service.onBatterySample(fields)
        }
    }

    private fun emitState(address: String, connected: Boolean, name: String) {
        val d = Dictionary()
        d["connected"] = connected
        d["address"] = address
        d["name"] = name
        TripLogbookPlugin.instance?.emit("ble_state", d)
    }

    // --------------------------------------------------------------- access

    /**
     * One queue per connection, advanced by the completion callbacks. Two
     * machines can therefore have an operation in flight at the same time
     * without either one stalling the other.
     */
    private fun enqueue(address: String, op: () -> Unit) {
        val conn = conns[address] ?: return
        conn.pending.addLast(op)
        if (!conn.busy) next(conn)
    }

    private fun next(conn: Conn?) {
        if (conn == null) return
        val op = conn.pending.removeFirstOrNull()
        if (op == null) {
            conn.busy = false
            return
        }
        conn.busy = true
        try { op() } catch (_: Exception) { conn.busy = false }
    }

    private fun find(
        address: String, service: String, characteristic: String
    ): BluetoothGattCharacteristic? {
        val g = conns[address]?.gatt ?: return null
        val s = g.getService(UUID.fromString(service)) ?: return null
        return s.getCharacteristic(UUID.fromString(characteristic))
    }

    fun subscribe(address: String, serviceUuid: String, characteristic: String) =
            enqueue(address) {
        val conn = conns[address]
        val g = conn?.gatt
        val c = find(address, serviceUuid, characteristic)
        if (g == null || c == null) { next(conn); return@enqueue }
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
                next(conn)
            }
        } catch (_: SecurityException) {
            next(conn)
        }
    }

    fun read(address: String, serviceUuid: String, characteristic: String) = enqueue(address) {
        val conn = conns[address]
        val c = find(address, serviceUuid, characteristic)
        if (c == null) { next(conn); return@enqueue }
        try { conn?.gatt?.readCharacteristic(c) } catch (_: SecurityException) { next(conn) }
    }

    fun write(
        address: String, serviceUuid: String, characteristic: String,
        data: ByteArray, withResponse: Boolean
    ) = enqueue(address) {
        val conn = conns[address]
        val g = conn?.gatt
        val c = find(address, serviceUuid, characteristic)
        if (g == null || c == null) { next(conn); return@enqueue }
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
            next(conn)
        }
    }
}
