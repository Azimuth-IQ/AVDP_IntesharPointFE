package com.example.inteshar

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * The built-in thermal head on Centerm-based terminals — the ROVOO MTHD-M1 in
 * this fleet — driven natively with **raw ESC/POS**.
 *
 * This is the Rovo equivalent of Sunmi's `IWoyouService.sendRAWData`, and it is
 * what makes a Rovo receipt identical to a Sunmi one: our own byte stream goes
 * to the head untouched. No third-party app re-renders it, no operator has to
 * tap anything, no app switch.
 *
 * Measured on the device (ROVOO MTHD-M1, Android 13): the print service exports
 * action `aidl.com.centerm.IPrinterService`; its binder
 * (`core.PrintServer extends IPrinterService$Stub`) answers to the descriptor
 * `com.centerm.printerservice.IPrinterService` with
 * `void sendEscPrintCommand(byte[])` at transaction **76**.
 *
 * Confirmed reaching the physical head: the vendor logs
 * `PrinterService#EscPrintTask: ESC_SET_CHAR_SIZE` (it parses OUR command
 * stream) followed by `Printer_HAL: prtdev get SIGIO!`.
 *
 * We deliberately do NOT generate an AIDL stub for it. Reconstructing a
 * 100-method vendor interface just to reach one call would be a large surface to
 * get subtly wrong; a hand-written `transact()` with the documented descriptor is
 * the whole contract, and it fails loudly if the vendor ever renumbers.
 */
class CentermPrinterChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "inteshar/centerm_printer"

        private const val SERVICE_PACKAGE = "com.centerm.printerservice"
        private const val SERVICE_ACTION = "aidl.com.centerm.IPrinterService"

        /**
         * What `Parcel.writeInterfaceToken` must carry, or the binder rejects the
         * call outright: the service logs
         * `enforceInterface() expected '…IPrinterService' but read '…IPrint'`
         * and throws SecurityException. Both interfaces exist in the vendor APK
         * with DIFFERENT numbering — `PrintServer extends IPrinterService$Stub`,
         * so this is the one that counts.
         */
        private const val DESCRIPTOR = "com.centerm.printerservice.IPrinterService"

        // Transaction codes read out of IPrinterService$Stub with dexdump.
        // (IPrint$Stub numbers sendEscPrintCommand as 74 — using that against this
        // binder is a silent wrong-method call, so keep these two straight.)
        private const val TX_OPEN = 2
        private const val TX_SEND_ESC_PRINT_COMMAND = 76

        private const val BIND_WAIT_MS = 4000L
    }

    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var binder: IBinder? = null
    private var bindRequested = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            synchronized(lock) { binder = service }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            synchronized(lock) { binder = null }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())

            "printRaw" -> {
                val data = call.argument<ByteArray>("bytes")
                if (data == null) {
                    result.error("ARG", "bytes missing", null)
                    return
                }
                if (!isAvailable()) {
                    result.error("UNSUPPORTED", "No Centerm print service on this device", null)
                    return
                }
                bind()
                Thread {
                    try {
                        printRaw(data)
                        main.post { result.success(true) }
                    } catch (e: Exception) {
                        main.post { result.error("PRINT_FAIL", e.message ?: e.toString(), null) }
                    }
                }.start()
            }

            else -> result.notImplemented()
        }
    }

    /** True only where the vendor print service is actually installed. */
    private fun isAvailable(): Boolean = try {
        context.packageManager.getPackageInfo(SERVICE_PACKAGE, 0)
        true
    } catch (e: Exception) {
        false
    }

    private fun bind() {
        synchronized(lock) {
            if (bindRequested && binder != null) return
            bindRequested = true
        }
        val intent = Intent(SERVICE_ACTION).apply { setPackage(SERVICE_PACKAGE) }
        try {
            context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        } catch (e: Exception) {
            synchronized(lock) { bindRequested = false }
        }
    }

    private fun awaitBinder(): IBinder {
        var waited = 0L
        while (waited < BIND_WAIT_MS) {
            synchronized(lock) { binder }?.let { return it }
            Thread.sleep(100)
            waited += 100
        }
        throw IOException("Centerm print service did not bind")
    }

    private fun printRaw(bytes: ByteArray) {
        val service = awaitBinder()
        // open() is idempotent in practice and the service is normally already
        // open; a refusal here is not fatal, so it must not block the receipt.
        try {
            callOpen(service)
        } catch (e: Exception) {
            // fall through to the write — it reports the real failure
        }
        sendEsc(service, bytes)
    }

    private fun callOpen(service: IBinder) {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(DESCRIPTOR)
            service.transact(TX_OPEN, data, reply, 0)
            reply.readException()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    private fun sendEsc(service: IBinder, bytes: ByteArray) {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(DESCRIPTOR)
            data.writeByteArray(bytes)
            service.transact(TX_SEND_ESC_PRINT_COMMAND, data, reply, 0)
            // Surfaces a vendor-side error as an exception rather than letting the
            // POS believe a voucher printed when it did not.
            reply.readException()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    fun dispose() {
        synchronized(lock) {
            if (!bindRequested) return
            bindRequested = false
            binder = null
        }
        try {
            context.unbindService(connection)
        } catch (e: Exception) {
        }
    }
}
