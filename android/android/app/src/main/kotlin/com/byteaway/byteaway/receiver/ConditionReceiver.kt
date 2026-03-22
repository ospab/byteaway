package com.ospab.byteaway.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager
import com.ospab.byteaway.service.ByteAwayForegroundService

/**
 * Monitors WiFi + Charging conditions for node sharing.
 *
 * Node sharing is allowed only when:
 * 1. Device is connected to WiFi (always required)
 * 2. Device is charging (required unless user enables mobile sharing)
 *
 * Registers a NetworkCallback for real-time WiFi state detection
 * and listens for power state changes via ACTION_POWER_CONNECTED / DISCONNECTED.
 */
class ConditionReceiver : BroadcastReceiver() {

    companion object {
        private var isWifiConnected = false
        private var isCharging = false
        private var networkCallback: ConnectivityManager.NetworkCallback? = null

        /**
         * Check current conditions synchronously.
         */
        fun areConditionsMet(context: Context): Boolean {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val activeNetwork = cm.activeNetwork
            val caps = cm.getNetworkCapabilities(activeNetwork)
            isWifiConnected = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true

            val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            isCharging = bm.isCharging

            return isWifiConnected && isCharging
        }

        /**
         * Register a live NetworkCallback for WiFi state changes.
         */
        fun registerNetworkCallback(context: Context) {
            if (networkCallback != null) return

            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    isWifiConnected = true
                    checkAndNotify(context)
                }

                override fun onLost(network: Network) {
                    isWifiConnected = false
                    checkAndNotify(context)
                }
            }

            cm.registerNetworkCallback(request, networkCallback!!)
        }

        /**
         * Unregister the NetworkCallback.
         */
        fun unregisterNetworkCallback(context: Context) {
            networkCallback?.let {
                val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(it)
                networkCallback = null
            }
        }

        private fun checkAndNotify(context: Context) {
            if (isWifiConnected && isCharging) {
                // Conditions met — could auto-start node
                // For now, just update state via ServiceBridge
                com.ospab.byteaway.service.ServiceBridge.sendEvent(mapOf(
                    "conditionsMet" to true,
                    "wifiConnected" to true,
                    "charging" to true
                ))
            } else {
                // Conditions lost — should pause node
                com.ospab.byteaway.service.ServiceBridge.sendEvent(mapOf(
                    "conditionsMet" to false,
                    "wifiConnected" to isWifiConnected,
                    "charging" to isCharging
                ))
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_POWER_CONNECTED -> {
                isCharging = true
                checkAndNotify(context)
            }
            Intent.ACTION_POWER_DISCONNECTED -> {
                isCharging = false
                checkAndNotify(context)
            }
            Intent.ACTION_BOOT_COMPLETED -> {
                // Re-register callbacks after boot
                registerNetworkCallback(context)
            }
        }
    }
}
