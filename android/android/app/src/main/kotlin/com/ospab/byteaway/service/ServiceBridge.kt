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

    private const val METHOD_CHANNEL = "com.byteaway.service"
    private const val EVENT_CHANNEL = "com.byteaway.service/events"
    private const val VPN_PERMISSION_REQUEST_CODE = 9471

    private var eventSink: EventChannel.EventSink? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingVpnConfig: String? = null
    private var pendingVpnMtu: Int? = null
    private var vpnConnected: Boolean = false
    private var vpnConnecting: Boolean = false
    private var nodeActive: Boolean = false
    private var nodeConnecting: Boolean = false
    private var bytesShared: Long = 0L
    private var activeSessions: Int = 0
    private var uptime: Long = 0L
    private var currentSpeed: Double = 0.0
    private var bytesIn: Long = 0L
    private var bytesOut: Long = 0L
    private var currentVpnConfig: String = ""

    // Публичные методы для доступа из VpnChannel
    fun isVpnConnected(): Boolean = vpnConnected
    fun getVpnConfig(): String = currentVpnConfig

    private fun resolveResult(result: MethodChannel.Result?, value: Boolean) {
        if (result == null) return
        try {
            result.success(value)
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to resolve MethodChannel result", t)
        }
    }

    fun emitNativeLog(message: String) {
        sendEvent(mapOf("nativeLog" to message))
    }

    private fun sanitizeMtu(raw: Int?): Int {
        val fallback = 1280
        val value = raw ?: fallback
        return value.coerceIn(1280, 1480)
    }

    fun startVpnService(context: Context, config: String, mtu: Int? = null): Boolean {
        Log.i("ByteAway", "startVpnService: config length=${config.length}")
        Log.d("ByteAway", "startVpnService cfg start=${config.take(300).replace("\n", "\\n")}")
        val safeMtu = sanitizeMtu(mtu)
        Log.i("ByteAway", "startVpnService: mtu=$safeMtu")
        
        currentVpnConfig = config

        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
            action = ByteAwayForegroundService.ACTION_START_VPN
            putExtra(ByteAwayForegroundService.EXTRA_VPN_CONFIG, config)
            putExtra(ByteAwayForegroundService.EXTRA_VPN_MTU, safeMtu)
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
            sendEvent(mapOf("vpnConnected" to false, "errorMessage" to reason))
            false
        }
    }

    fun stopVpnService(context: Context): Boolean {
        return try {
            val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                action = ByteAwayForegroundService.ACTION_STOP_VPN
            }
            context.startService(intent)

            vpnConnected = false
            currentVpnConfig = ""
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                    "startVpn" -> {
                        val config = call.argument<String>("config") ?: "{}"
                        val mtu = call.argument<Int>("mtu")

                        val prepareIntent = VpnService.prepare(context)
                        if (prepareIntent != null) {
                            if (context !is Activity) {
                                Log.w("ByteAway", "Cannot request VPN permission without Activity context")
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            pendingVpnResult = result
                            pendingVpnConfig = config
                            pendingVpnMtu = mtu
                            context.startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE)
                            return@setMethodCallHandler
                        }

                        result.success(startVpnService(context, config, mtu))
                    }

                    "stopVpn" -> {
                        result.success(stopVpnService(context))
                    }

                    "startNode" -> {
                        val token = call.argument<String>("token") ?: ""
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        val country = call.argument<String>("country") ?: "auto"
                        val transportMode = call.argument<String>("transportMode") ?: "quic"
                        val connType = call.argument<String>("connType") ?: "wifi"
                        val speedMbps = call.argument<Int>("speedMbps") ?: 50
                        val mtu = call.argument<Int>("mtu") ?: 1280
                        val xrayConfigJson = call.argument<String>("xrayConfigJson")

                        if (token.isBlank() || deviceId.isBlank()) {
                            Log.w("ByteAway", "startNode rejected: token/deviceId is blank")
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val masterWsUrl = call.argument<String>("masterWsUrl")
                        Log.i("ByteAway", "startNode invoke: token=${token.take(8)}..., deviceId=${deviceId.take(8)}..., country=$country, transport=$transportMode, connType=$connType, speed=$speedMbps, masterWsUrl=${masterWsUrl ?: "default"}")

                        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                            action = ByteAwayForegroundService.ACTION_START_NODE
                            putExtra("token", token)
                            putExtra("deviceId", deviceId)
                            putExtra("country", country)
                            putExtra("transportMode", transportMode)
                            putExtra("connType", connType)
                            putExtra("speedMbps", speedMbps)
                            putExtra("mtu", mtu)
                            putExtra("masterWsUrl", masterWsUrl)
                            putExtra("xrayConfigJson", xrayConfigJson)
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
                            "vpnConnecting" to vpnConnecting,
                            "nodeActive" to nodeActive,
                            "nodeConnecting" to nodeConnecting,
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
                    emitNativeLog(msg)
                    try { result.success(false) } catch (_: Throwable) {}
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

    fun handleActivityResult(context: Context, requestCode: Int, resultCode: Int) {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) {
            return
        }

        val result = pendingVpnResult
        val config = pendingVpnConfig
        val mtu = pendingVpnMtu
        pendingVpnResult = null
        pendingVpnConfig = null
        pendingVpnMtu = null

        if (resultCode == Activity.RESULT_OK && !config.isNullOrBlank()) {
            Log.i("ByteAway", "VPN permission granted")
            val started = startVpnService(context, config, mtu)
            resolveResult(result, started)
        } else {
            Log.w("ByteAway", "VPN permission denied")
            resolveResult(result, false)
        }
    }

    fun sendEvent(data: Map<String, Any>) {
        vpnConnected = data["vpnConnected"] as? Boolean ?: vpnConnected
        vpnConnecting = data["vpnConnecting"] as? Boolean ?: vpnConnecting
        nodeActive = data["nodeActive"] as? Boolean ?: nodeActive
        nodeConnecting = data["nodeConnecting"] as? Boolean ?: nodeConnecting
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
}
