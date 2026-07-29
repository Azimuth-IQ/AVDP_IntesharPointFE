package com.example.inteshar

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

/**
 * Bluetooth **Classic** (RFCOMM / Serial Port Profile) printing.
 *
 * Why this file exists: `flutter_blue_plus` is BLE/GATT only — there is no
 * `createRfcommSocket` anywhere in its Android source — while nearly every
 * external ESC/POS thermal printer (X-Printer X50, the terminals' internal
 * heads, generic 58 mm units) speaks Classic SPP. That mismatch, not the UI, is
 * why "connect" never worked for external printers.
 *
 * It sends the **same ESC/POS bytes** the Sunmi AIDL path sends, so the paper
 * comes out identical. No plugin, no re-rendering by a third app.
 */
class SppPrinterChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "inteshar/spp_printer"

        /** The Serial Port Profile service. Fixed by the Bluetooth spec. */
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        /**
         * Cheap printers have small input buffers and drop bytes when a whole
         * receipt lands at once; a chunk-and-breathe write is the standard
         * remedy (the same shape the BLE path uses, just with a bigger window).
         */
        private const val CHUNK = 256
        private const val CHUNK_PAUSE_MS = 15L
        private const val CONNECT_SETTLE_MS = 150L
    }

    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var socket: BluetoothSocket? = null
    private var connectedAddress: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(adapter()?.isEnabled == true && hasConnectPermission())

            "bondedDevices" -> result.success(bondedDevices())

            "connect" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) {
                    result.error("ARG", "address missing", null)
                } else {
                    offMain(result) { synchronized(lock) { openSocket(address) } }
                }
            }

            "write" -> {
                val address = call.argument<String>("address")
                val bytes = call.argument<ByteArray>("bytes")
                if (address.isNullOrBlank() || bytes == null) {
                    result.error("ARG", "address/bytes missing", null)
                } else {
                    offMain(result) {
                        synchronized(lock) {
                            openSocket(address)
                            writeBytes(bytes)
                        }
                    }
                }
            }

            "disconnect" -> {
                offMain(result) { synchronized(lock) { closeSocket() } }
            }

            else -> result.notImplemented()
        }
    }

    /** Close any open socket — called when the activity goes away. */
    fun dispose() {
        synchronized(lock) { closeSocket() }
    }

    // ------------------------------------------------------------------ lookup

    private fun adapter(): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** Android 12+ gates every Classic call behind a runtime permission. */
    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Every bonded Classic device, with the real `getName()` — headsets and
     * phones included. Deciding which of these is a printer is the Dart side's
     * job; this just reports what the stack knows, plus the imaging-class hint.
     */
    private fun bondedDevices(): List<Map<String, Any?>> {
        if (!hasConnectPermission()) return emptyList()
        val bonded = try {
            adapter()?.bondedDevices ?: emptySet<BluetoothDevice>()
        } catch (e: SecurityException) {
            emptySet<BluetoothDevice>()
        }
        return bonded.map { device ->
            val cls = try { device.bluetoothClass } catch (e: SecurityException) { null }
            mapOf(
                "address" to device.address,
                "name" to (try { device.name } catch (e: SecurityException) { null } ?: ""),
                // Major class IMAGING is what a printer that bothers to declare
                // itself reports. Most cheap ESC/POS units declare nothing
                // useful, so this is a hint the Dart name heuristic backs up.
                "isPrinterClass" to (cls?.majorDeviceClass == BluetoothClass.Device.Major.IMAGING),
            )
        }
    }

    // ------------------------------------------------------------------ socket

    /** Opens a socket to [address], reusing the live one when it already matches. */
    private fun openSocket(address: String) {
        val existing = socket
        if (existing != null && existing.isConnected && connectedAddress == address) return
        closeSocket()

        if (!hasConnectPermission()) throw IOException("Bluetooth permission not granted")
        val adapter = adapter() ?: throw IOException("No Bluetooth adapter")
        if (!adapter.isEnabled) throw IOException("Bluetooth is off")
        val device = adapter.getRemoteDevice(address)

        // Discovery starves the RFCOMM connect and is the usual cause of a
        // hanging pair-and-print.
        try { adapter.cancelDiscovery() } catch (e: SecurityException) { }

        var lastError: Exception? = null
        for (factory in socketFactories(device)) {
            try {
                val s = factory() ?: continue
                s.connect()
                socket = s
                connectedAddress = address
                Thread.sleep(CONNECT_SETTLE_MS)
                return
            } catch (e: Exception) {
                lastError = e
                closeSocket()
            }
        }
        throw IOException(lastError?.message ?: "Could not open a print channel to $address")
    }

    /**
     * Three ways to get an RFCOMM socket, in descending order of politeness.
     * The secure path is correct and works on most printers; the insecure one
     * covers units that never negotiate a link key; the reflection channel-1
     * call is the long-standing workaround for cheap modules whose SDP record is
     * wrong or missing — without it those printers simply never connect.
     */
    private fun socketFactories(device: BluetoothDevice): List<() -> BluetoothSocket?> = listOf(
        { device.createRfcommSocketToServiceRecord(SPP_UUID) },
        { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
        {
            try {
                val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                m.invoke(device, 1) as? BluetoothSocket
            } catch (e: Exception) {
                null
            }
        },
    )

    private fun writeBytes(bytes: ByteArray) {
        val s = socket ?: throw IOException("Printer not connected")
        val out = s.outputStream
        var offset = 0
        while (offset < bytes.size) {
            val len = minOf(CHUNK, bytes.size - offset)
            out.write(bytes, offset, len)
            out.flush()
            offset += len
            if (offset < bytes.size) Thread.sleep(CHUNK_PAUSE_MS)
        }
        // Let the head finish before anything else touches the socket; cutting a
        // receipt short is worse than a 120 ms wait per sale.
        Thread.sleep(120)
    }

    private fun closeSocket() {
        try { socket?.outputStream?.flush() } catch (e: Exception) { }
        try { socket?.close() } catch (e: Exception) { }
        socket = null
        connectedAddress = null
    }

    // ---------------------------------------------------------------- threading

    /** Runs blocking Bluetooth work off the UI thread and replies exactly once. */
    private fun offMain(result: MethodChannel.Result, block: () -> Unit) {
        Thread {
            try {
                block()
                main.post { result.success(true) }
            } catch (e: Exception) {
                main.post { result.error("SPP_FAIL", e.message ?: e.toString(), null) }
            }
        }.start()
    }
}
