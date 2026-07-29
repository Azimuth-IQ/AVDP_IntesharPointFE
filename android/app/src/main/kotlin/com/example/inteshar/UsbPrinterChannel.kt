package com.example.inteshar

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * USB (OTG) printing — a counter-attached thermal printer plugged into the
 * terminal.
 *
 * Same contract as every other transport in this app: it takes the ESC/POS bytes
 * built in Dart and pushes them, unmodified, down the printer's bulk-OUT
 * endpoint. Nothing re-renders the receipt on the way.
 */
class UsbPrinterChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "inteshar/usb_printer"

        /** bulkTransfer's practical ceiling is 16 KB; stay well inside it. */
        private const val CHUNK = 8192
        private const val TRANSFER_TIMEOUT_MS = 5000

        /** A permission dialog nobody answers must not hang the Dart future forever. */
        private const val PERMISSION_TIMEOUT_MS = 60_000L
    }

    private val main = Handler(Looper.getMainLooper())
    private val permissionAction = "${context.packageName}.USB_PERMISSION"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(listDevices())

            "hasPermission" -> {
                val device = findDevice(call.argument<String>("id"))
                result.success(device != null && manager().hasPermission(device))
            }

            "requestPermission" -> requestPermission(call.argument<String>("id"), result)

            "write" -> {
                val id = call.argument<String>("id")
                val bytes = call.argument<ByteArray>("bytes")
                if (id.isNullOrBlank() || bytes == null) {
                    result.error("ARG", "id/bytes missing", null)
                } else {
                    Thread {
                        try {
                            write(id, bytes)
                            main.post { result.success(true) }
                        } catch (e: Exception) {
                            main.post { result.error("USB_FAIL", e.message ?: e.toString(), null) }
                        }
                    }.start()
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun manager(): UsbManager =
        context.getSystemService(Context.USB_SERVICE) as UsbManager

    /** `vendorId:productId` — stable across replugs of the same model. */
    private fun idOf(device: UsbDevice) = "${device.vendorId}:${device.productId}"

    private fun findDevice(id: String?): UsbDevice? {
        if (id.isNullOrBlank()) return null
        return manager().deviceList.values.firstOrNull { idOf(it) == id }
    }

    private fun listDevices(): List<Map<String, Any?>> {
        val usb = manager()
        return usb.deviceList.values.map { device ->
            mapOf(
                "id" to idOf(device),
                "name" to (deviceLabel(device)),
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "isPrinterClass" to (printerInterface(device) != null),
                "hasPermission" to usb.hasPermission(device),
            )
        }
    }

    private fun deviceLabel(device: UsbDevice): String {
        val product = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try { device.productName } catch (e: Exception) { null }
        } else null
        val manufacturer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try { device.manufacturerName } catch (e: Exception) { null }
        } else null
        return listOfNotNull(manufacturer, product)
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .ifBlank { device.deviceName }
    }

    // -------------------------------------------------------------- permission

    private fun requestPermission(id: String?, result: MethodChannel.Result) {
        val device = findDevice(id)
        if (device == null) {
            result.error("NOT_FOUND", "USB device not attached", null)
            return
        }
        val usb = manager()
        if (usb.hasPermission(device)) {
            result.success(true)
            return
        }

        // MethodChannel results may be delivered exactly once; a receiver plus a
        // watchdog can both fire, so gate them.
        val replied = AtomicBoolean(false)
        fun reply(granted: Boolean) {
            if (replied.compareAndSet(false, true)) main.post { result.success(granted) }
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != permissionAction) return
                try { context.unregisterReceiver(this) } catch (e: Exception) { }
                reply(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        val filter = IntentFilter(permissionAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }

        // FLAG_MUTABLE is mandatory from API 31: the system fills the granted
        // device into the intent it sends back.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            Intent(permissionAction).setPackage(context.packageName),
            flags,
        )
        usb.requestPermission(device, pending)

        main.postDelayed({
            if (!replied.get()) {
                try { context.unregisterReceiver(receiver) } catch (e: Exception) { }
                reply(usb.hasPermission(device))
            }
        }, PERMISSION_TIMEOUT_MS)
    }

    // ------------------------------------------------------------------- write

    /** The USB printer class (0x07) interface, if this device has one. */
    private fun printerInterface(device: UsbDevice): UsbInterface? {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return iface
        }
        return null
    }

    private fun bulkOut(iface: UsbInterface): UsbEndpoint? {
        for (i in 0 until iface.endpointCount) {
            val ep = iface.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                ep.direction == UsbConstants.USB_DIR_OUT
            ) {
                return ep
            }
        }
        return null
    }

    private fun write(id: String, bytes: ByteArray) {
        val device = findDevice(id) ?: throw IOException("USB device not attached")
        val usb = manager()
        if (!usb.hasPermission(device)) throw IOException("USB permission not granted")

        // Prefer the declared printer interface; fall back to any interface with
        // a bulk-OUT endpoint, which is how vendor-class ESC/POS units present.
        var iface = printerInterface(device)
        var endpoint = iface?.let { bulkOut(it) }
        if (endpoint == null) {
            for (i in 0 until device.interfaceCount) {
                val candidate = device.getInterface(i)
                val ep = bulkOut(candidate)
                if (ep != null) {
                    iface = candidate
                    endpoint = ep
                    break
                }
            }
        }
        val target = iface ?: throw IOException("No printable USB interface")
        val out = endpoint ?: throw IOException("No bulk endpoint on the USB printer")

        val connection = usb.openDevice(device) ?: throw IOException("Cannot open the USB device")
        try {
            if (!connection.claimInterface(target, true)) {
                throw IOException("Another app holds the USB printer")
            }
            var offset = 0
            while (offset < bytes.size) {
                val len = minOf(CHUNK, bytes.size - offset)
                val slice = bytes.copyOfRange(offset, offset + len)
                val sent = connection.bulkTransfer(out, slice, slice.size, TRANSFER_TIMEOUT_MS)
                if (sent < 0) throw IOException("USB transfer failed at byte $offset")
                offset += len
            }
        } finally {
            try { connection.releaseInterface(target) } catch (e: Exception) { }
            connection.close()
        }
    }
}
