package com.ospab.byteaway.service

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
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
    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfigJson: String? = null
    private var activity: Activity? = null

    private var vpnConnected: Boolean = false
    private var vpnConnecting: Boolean = false
    private var bytesIn: Long = 0L
    private var bytesOut: Long = 0L
    private var uptimeSec: Long = 0L
    private var errorMessage: String? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        if (context is Activity) {
            activity = context
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVpn" -> {
                        val configJson = call.argument<String>("config") ?: "{}"
                        val prepareIntent = VpnService.prepare(context)
                        if (prepareIntent != null) {
                            val currentActivity = activity
                            if (currentActivity == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            pendingResult = result
                            pendingConfigJson = configJson
                            currentActivity.startActivityForResult(
                                prepareIntent,
                                VPN_PERMISSION_REQUEST_CODE
                            )
                            return@setMethodCallHandler
                        }
                        result.success(startVpnService(context, configJson))
                    }
                    "stopVpn" -> result.success(stopVpnService(context))
                    "getStatus" -> result.success(
                        mapOf(
                            "vpnConnected" to vpnConnected,
                            "vpnConnecting" to vpnConnecting,
                            "bytesIn" to bytesIn,
                            "bytesOut" to bytesOut,
                            "uptime" to uptimeSec,
                            "errorMessage" to (errorMessage ?: "")
                        )
                    )
                    else -> result.notImplemented()
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

    private fun startVpnService(context: Context, configJson: String): Boolean {
        return try {
            val intent = Intent(context, ByteAwayVpnService::class.java).apply {
                action = ByteAwayVpnService.ACTION_START_VPN
                putExtra(ByteAwayVpnService.EXTRA_VPN_CONFIG, configJson)
            }
            ContextCompat.startForegroundService(context, intent)
            true
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to start VPN service", t)
            sendEvent(mapOf(
                "vpnConnected" to false,
                "vpnConnecting" to false,
                "errorMessage" to (t.message ?: "Failed to start VPN")
            ))
            false
        }
    }

    private fun stopVpnService(context: Context): Boolean {
        return try {
            val intent = Intent(context, ByteAwayVpnService::class.java).apply {
                action = ByteAwayVpnService.ACTION_STOP_VPN
            }
            context.startService(intent)
            true
        } catch (t: Throwable) {
            Log.e("ByteAway", "Failed to stop VPN service", t)
            sendEvent(mapOf(
                "vpnConnected" to false,
                "vpnConnecting" to false,
                "errorMessage" to (t.message ?: "Failed to stop VPN")
            ))
            false
        }
    }

    fun handleActivityResult(context: Context, requestCode: Int, resultCode: Int) {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) return

        val result = pendingResult
        val config = pendingConfigJson
        pendingResult = null
        pendingConfigJson = null

        if (resultCode == Activity.RESULT_OK && !config.isNullOrBlank()) {
            result?.success(startVpnService(context, config))
        } else {
            result?.success(false)
        }
    }

    fun sendEvent(data: Map<String, Any>) {
        vpnConnected = data["vpnConnected"] as? Boolean ?: vpnConnected
        vpnConnecting = data["vpnConnecting"] as? Boolean ?: vpnConnecting
        bytesIn = data["bytesIn"] as? Long ?: bytesIn
        bytesOut = data["bytesOut"] as? Long ?: bytesOut
        uptimeSec = data["uptime"] as? Long ?: uptimeSec
        errorMessage = data["errorMessage"] as? String ?: errorMessage

        Handler(Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }

    fun clearActivity() {
        activity = null
    }
}
