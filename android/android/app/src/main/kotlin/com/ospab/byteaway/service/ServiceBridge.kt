package com.ospab.byteaway.service

import android.app.Activity
import android.net.VpnService
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object ServiceBridge {

    // Emit native log for Flutter (used in MainActivity)
    @JvmStatic
    fun emitNativeLog(msg: String) {
        Log.e("ByteAway", msg)
        eventSink?.success(mapOf("nativeLog" to msg))
    }

    private const val METHOD_CHANNEL = "com.byteaway.service"
    private const val EVENT_CHANNEL = "com.byteaway.service/events"
    private const val VPN_PERMISSION_REQUEST_CODE = 9471

    private var eventSink: EventChannel.EventSink? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingVpnConfig: String? = null
    private var vpnConnected: Boolean = false
    private var nodeActive: Boolean = false
    private var bytesShared: Long = 0L
    private var activeSessions: Int = 0
    private var uptime: Long = 0L
    private var currentSpeed: Double = 0.0
    private var bytesIn: Long = 0L
    private var bytesOut: Long = 0L
    private var activity: Activity? = null

    private fun resolveResult(result: MethodChannel.Result?, value: Boolean) {
        if (result == null) return
        try {
            result.success(value)
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to resolve MethodChannel result", t)
        }
    }

    private fun appendLog(context: Context, message: String) {
        try {
            val ts = java.time.Instant.now().toString()
            val entry = "[$ts] $message\n"
            context.openFileOutput("byteaway_error.log", Context.MODE_APPEND).use { fos ->
                fos.write(entry.toByteArray())
            }
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to write bridge log", t)
        }
    }

    private fun appendExternalLog(context: Context, message: String) {
        try {
            val ts = java.time.Instant.now().toString()
            val entry = "[$ts] $message\n"
            val dir = context.getExternalFilesDir(null)
            if (dir != null) {
                val outFile = java.io.File(dir, "byteaway_error_external.txt")
                // write directly to external file for easier retrieval
                java.io.FileOutputStream(outFile, true).use { fos ->
                    fos.write(entry.toByteArray())
                }
            } else {
                appendLog(context, message)
            }
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to write bridge external log", t)
            appendLog(context, "Failed to write bridge external log: ${t.message}")
        }
    }

    @JvmStatic
    fun startVpnService(context: Context, config: String): Boolean {
        Log.i("ByteAway", "startVpnService: config length=${config.length}")
        Log.d("ByteAway", "startVpnService cfg start=${config.take(300).replace("\n", "\\n")}")

        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
            action = ByteAwayForegroundService.ACTION_START_VPN
            putExtra(ByteAwayForegroundService.EXTRA_VPN_CONFIG, config)
        }

        return try {
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (inner: Throwable) {
                Log.w("ByteAway", "startForegroundService failed, fallback to startService", inner)
                context.startService(intent)
            }
            true
        } catch (t: Throwable) {
            val trace = Log.getStackTraceString(t).lineSequence().take(8).joinToString(" | ")
            val reason = "${t::class.java.simpleName}: ${t.message ?: "unknown"} [${trace}]"
            Log.e("ByteAway", "Failed to start VPN service: $reason", t)
            vpnConnected = false
            sendEvent(mapOf("vpnConnected" to false, "errorMessage" to reason))
            false
        }
    }

    @JvmStatic
    fun stopVpnService(context: Context): Boolean {
        return try {
            val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                action = ByteAwayForegroundService.ACTION_STOP_VPN
            }
            context.startService(intent)

            vpnConnected = false
            sendEvent(mapOf("vpnConnected" to false, "errorMessage" to ""))
            true
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to stop VPN service", t)
            val reason = "${t::class.java.simpleName}: ${t.message ?: "unknown"}"
            sendEvent(mapOf("vpnConnected" to false, "errorMessage" to reason))
            false
        }
    }

    fun register(flutterEngine: FlutterEngine, context: Context) {
        if (context is Activity) {
            activity = context
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                    "startVpn" -> {
                        val config = call.argument<String>("config") ?: "{}"

                        val prepareIntent = VpnService.prepare(context)
                        if (prepareIntent != null) {
                            val act = activity
                            if (act == null) {
                                Log.w("ByteAway", "Cannot request VPN permission without Activity reference")
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            pendingVpnResult = result
                            pendingVpnConfig = config
                            act.startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE)
                            return@setMethodCallHandler
                        }

                        result.success(startVpnService(context, config))
                    }

                    "stopVpn" -> {
                        result.success(stopVpnService(context))
                    }

                    "startNode" -> {
                        val token = call.argument<String>("token") ?: ""
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        val country = call.argument<String>("country") ?: "auto"
                        val connType = call.argument<String>("connType") ?: "wifi"
                        val transportMode = call.argument<String>("transportMode") ?: "quic"
                        val speedMbps = call.argument<Int>("speedMbps") ?: 50
                        val mtu = call.argument<Int>("mtu") ?: 1280

                        if (token.isBlank() || deviceId.isBlank()) {
                            Log.w("ByteAway", "startNode rejected: token/deviceId is blank")
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val masterWsUrl = call.argument<String>("masterWsUrl")
                        Log.i("ByteAway", "startNode invoke: token=${token.take(8)}..., deviceId=${deviceId.take(8)}..., country=$country, connType=$connType, transport=$transportMode, speed=$speedMbps, mtu=$mtu, masterWsUrl=${masterWsUrl ?: "default"}")

                        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                            action = ByteAwayForegroundService.ACTION_START_NODE
                            putExtra("token", token)
                            putExtra("deviceId", deviceId)
                            putExtra("country", country)
                            putExtra("connType", connType)
                            putExtra("transportMode", transportMode)
                            putExtra("speedMbps", speedMbps)
                            putExtra("mtu", mtu)
                            putExtra("masterWsUrl", masterWsUrl)
                        }
                        context.startForegroundService(intent)
                        result.success(true)
                    }

                    "stopNode" -> {
                        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                            action = ByteAwayForegroundService.ACTION_STOP_NODE
                        }
                        context.startService(intent)
                        result.success(true)
                    }

                    "getStatus" -> {
                        result.success(mapOf(
                            "vpnConnected" to vpnConnected,
                            "nodeActive" to nodeActive,
                            "bytesShared" to bytesShared,
                            "activeSessions" to activeSessions,
                            "uptime" to uptime,
                            "currentSpeed" to currentSpeed,
                            "bytesIn" to bytesIn,
                            "bytesOut" to bytesOut
                        ))
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                val trace = Log.getStackTraceString(t).lineSequence().take(20).joinToString(" | ")
                val msg = "ServiceBridge handler error: ${t::class.java.simpleName}: ${t.message ?: ""} [${trace}]"
                Log.e("ByteAway", msg, t)
                appendLog(context, msg)
                try {
                    result.success(false)
                } catch (_: Throwable) {
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    @JvmStatic
    fun handleActivityResult(context: Context, requestCode: Int, resultCode: Int) {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) {
            return
        }

        val result = pendingVpnResult
        val config = pendingVpnConfig
        pendingVpnResult = null
        pendingVpnConfig = null

        if (resultCode == Activity.RESULT_OK && !config.isNullOrBlank()) {
            Log.i("ByteAway", "VPN permission granted")
            val started = startVpnService(context, config)
            resolveResult(result, started)
        } else {
            Log.w("ByteAway", "VPN permission denied")
            resolveResult(result, false)
        }
    }

    @JvmStatic
    fun sendEvent(data: Map<String, Any>) {
        vpnConnected = data["vpnConnected"] as? Boolean ?: vpnConnected
        nodeActive = data["nodeActive"] as? Boolean ?: nodeActive
        bytesShared = data["bytesShared"] as? Long ?: bytesShared
        activeSessions = data["activeSessions"] as? Int ?: activeSessions
        uptime = data["uptime"] as? Long ?: uptime
        currentSpeed = data["currentSpeed"] as? Double ?: currentSpeed
        bytesIn = data["bytesIn"] as? Long ?: bytesIn
        bytesOut = data["bytesOut"] as? Long ?: bytesOut

        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }

    @JvmStatic
    fun isVpnConnected(): Boolean = vpnConnected

    @JvmStatic
    fun getVpnConfig(): String = pendingVpnConfig ?: "{}"

    @JvmStatic
    fun clearActivity() {
        activity = null
    }
}
