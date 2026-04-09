package com.ospab.byteaway.service

import android.app.Activity
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONArray

object VpnChannel {
    private const val CHANNEL = "com.ospab.byteaway/vpn"
    private var activity: Activity? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        if (context is Activity) {
            activity = context
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "startVpn" -> {
                            val configStr = call.argument<String>("config")
                            val dns = call.argument<List<String>>("dns")
                            val mtu = call.argument<Int>("mtu")
                            
                            Log.i("ByteAway", "VPN start requested: DNS=$dns, MTU=$mtu")
                            
                            if (configStr != null) {
                                // Используем существующий ServiceBridge для запуска VPN
                                val success = startVpnWithConfig(context, configStr, dns, mtu)
                                result.success(success)
                            } else {
                                result.error("INVALID_CONFIG", "Config is null", null)
                            }
                        }
                        
                        "stopVpn" -> {
                            Log.i("ByteAway", "VPN stop requested")
                            val success = stopVpnService(context)
                            result.success(success)
                        }
                        
                        "getVpnStatus" -> {
                            val status = getVpnStatus()
                            result.success(status)
                        }
                        
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e("ByteAway", "VPN Channel error: ${e.message}", e)
                    result.error("VPN_ERROR", e.message, null)
                }
            }
    }

    private fun startVpnWithConfig(context: Context, config: String, dns: List<String>?, mtu: Int?): Boolean {
        return try {
            Log.i("ByteAway", "Starting VPN with config")
            
            // Используем существующий ServiceBridge для запуска VPN
            val success = ServiceBridge.startVpnService(context, config, mtu)
            
            if (success) {
                Log.i("ByteAway", "VPN started successfully")
            } else {
                Log.e("ByteAway", "Failed to start VPN")
            }
            
            success
        } catch (e: Exception) {
            Log.e("ByteAway", "Failed to start VPN: ${e.message}", e)
            false
        }
    }

    private fun stopVpnService(context: Context): Boolean {
        return try {
            ServiceBridge.stopVpnService(context)
        } catch (e: Exception) {
            Log.e("ByteAway", "Failed to stop VPN: ${e.message}", e)
            false
        }
    }

    private fun getVpnStatus(): Map<String, Any> {
        return mapOf(
            "connected" to ServiceBridge.isVpnConnected(),
            "config" to ServiceBridge.getVpnConfig()
        )
    }
}
