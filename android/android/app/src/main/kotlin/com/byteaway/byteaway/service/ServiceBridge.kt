package com.ospab.byteaway.service

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Platform Channel bridge between Flutter and ByteAwayForegroundService.
 *
 * MethodChannel "com.byteaway.service":
 *   - startVpn(config: String) → bool
 *   - stopVpn() → bool
 *   - startNode(token, deviceId, country, speedMbps) → bool
 *   - stopNode() → bool
 *   - getStatus() → Map
 *
 * EventChannel "com.byteaway.service/events":
 *   - Stream of status maps broadcast from the Foreground Service
 */
object ServiceBridge {

    private const val METHOD_CHANNEL = "com.byteaway.service"
    private const val EVENT_CHANNEL = "com.byteaway.service/events"

    private var eventSink: EventChannel.EventSink? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        // ── MethodChannel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVpn" -> {
                        val config = call.argument<String>("config") ?: "{}"
                        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                            action = ByteAwayForegroundService.ACTION_START_VPN
                            putExtra("config", config)
                        }
                        context.startForegroundService(intent)
                        result.success(true)
                    }

                    "stopVpn" -> {
                        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                            action = ByteAwayForegroundService.ACTION_STOP_VPN
                        }
                        context.startService(intent)
                        result.success(true)
                    }

                    "startNode" -> {
                        val token = call.argument<String>("token") ?: ""
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        val country = call.argument<String>("country") ?: "auto"
                        val speedMbps = call.argument<Int>("speedMbps") ?: 50

                        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
                            action = ByteAwayForegroundService.ACTION_START_NODE
                            putExtra("token", token)
                            putExtra("deviceId", deviceId)
                            putExtra("country", country)
                            putExtra("speedMbps", speedMbps)
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
                        // Return current status map
                        // In a real implementation, query the service directly
                        result.success(mapOf(
                            "vpnConnected" to false,
                            "nodeActive" to false,
                            "bytesShared" to 0L,
                            "activeSessions" to 0,
                            "uptime" to 0L,
                            "currentSpeed" to 0.0
                        ))
                    }

                    else -> result.notImplemented()
                }
            }

        // ── EventChannel ───────────────────────────────────
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

    /**
     * Send status event to Flutter from the Foreground Service.
     * Called from [ByteAwayForegroundService.broadcastState].
     */
    fun sendEvent(data: Map<String, Any>) {
        // Must dispatch on main thread for EventChannel
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }
}
