package com.example.inteshar

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import woyou.aidlservice.jiuiv5.ICallback
import woyou.aidlservice.jiuiv5.IWoyouService

class MainActivity : FlutterActivity() {
    private val channelName = "inteshar/sunmi_printer"
    private var woyouService: IWoyouService? = null
    private var bindRequested = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            woyouService = IWoyouService.Stub.asInterface(service)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            woyouService = null
        }
    }

    // No-op callback: completion is reported back via the MethodChannel result
    // once the (synchronous) AIDL calls return; per-job status isn't needed here.
    private val noop = object : ICallback.Stub() {
        override fun onRunResult(isSuccess: Boolean) {}
        override fun onReturnString(result: String?) {}
        override fun onRaiseException(code: Int, msg: String?) {}
        override fun onPrintResult(code: Int, msg: String?) {}
    }

    private fun isSunmi(): Boolean = Build.MANUFACTURER.equals("SUNMI", ignoreCase = true)

    private fun bindPrinter() {
        if (bindRequested || !isSunmi()) return
        bindRequested = true
        val intent = Intent().apply {
            setPackage("woyou.aidlservice.jiuiv5")
            action = "woyou.aidlservice.jiuiv5.IWoyouService"
        }
        try {
            bindService(intent, connection, Context.BIND_AUTO_CREATE)
        } catch (e: Exception) {
            bindRequested = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bindPrinter()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isSunmi())
                    "printRaw" -> {
                        val data = call.argument<ByteArray>("bytes")
                        if (data == null) {
                            result.error("ARG", "bytes missing", null)
                            return@setMethodCallHandler
                        }
                        if (!isSunmi()) {
                            result.error("UNSUPPORTED", "Not a Sunmi device", null)
                            return@setMethodCallHandler
                        }
                        if (woyouService == null) bindPrinter()
                        Thread {
                            try {
                                // The bind is async; give onServiceConnected a moment.
                                var svc = woyouService
                                var waited = 0
                                while (svc == null && waited < 3000) {
                                    Thread.sleep(100)
                                    waited += 100
                                    svc = woyouService
                                }
                                if (svc == null) {
                                    runOnUiThread { result.error("NO_SERVICE", "Printer service not bound", null) }
                                } else {
                                    svc.printerInit(noop)
                                    svc.sendRAWData(data, noop)
                                    svc.lineWrap(3, noop)
                                    runOnUiThread { result.success(true) }
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PRINT_FAIL", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (bindRequested) {
            try {
                unbindService(connection)
            } catch (e: Exception) {
            }
            bindRequested = false
        }
        super.onDestroy()
    }
}
