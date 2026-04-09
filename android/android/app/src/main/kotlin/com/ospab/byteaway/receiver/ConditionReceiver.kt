package com.ospab.byteaway.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager

class ConditionReceiver : BroadcastReceiver() {

    companion object {
        private var isWifiConnected = false
        private var isCharging = false
        private var networkCallback: ConnectivityManager.NetworkCallback? = null

        fun areConditionsMet(context: Context): Boolean {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val activeNetwork = cm.activeNetwork
            val caps = cm.getNetworkCapabilities(activeNetwork)
            isWifiConnected = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true

            val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            isCharging = bm.isCharging

            return isWifiConnected && isCharging
        }

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

        fun unregisterNetworkCallback(context: Context) {
            networkCallback?.let {
                val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(it)
                networkCallback = null
            }
        }

        private fun checkAndNotify(context: Context) {
            com.ospab.byteaway.service.ServiceBridge.sendEvent(mapOf(
                "conditionsMet" to (isWifiConnected && isCharging),
                "wifiConnected" to isWifiConnected,
                "charging" to isCharging
            ))
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
                registerNetworkCallback(context)
            }
        }
    }
}
