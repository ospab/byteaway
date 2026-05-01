package com.ospab.byteaway.utils

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.TelephonyManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

object DeviceInfoChannel {
    private const val CHANNEL = "com.ospab.byteaway/device_info"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCountryCode" -> {
                    val country = getCountryCode(context)
                    result.success(country)
                }
                "getConnectionType" -> {
                    val connType = getConnectionType(context)
                    result.success(connType)
                }
                "getHardwareId" -> {
                    val hwid = getHardwareId(context)
                    result.success(hwid)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations(context))
                }
                "openBatteryOptimizationSettings" -> {
                    val opened = openBatteryOptimizationSettings(context)
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun openBatteryOptimizationSettings(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false

        return try {
            // First try to open the app-specific battery optimization page
            val packageUri = Uri.parse("package:${context.packageName}")
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = packageUri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            try {
                // Fallback: open general battery optimization settings
                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallbackIntent)
                true
            } catch (_: Throwable) {
                try {
                    // Last resort: open app settings
                    val appIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(appIntent)
                    true
                } catch (_: Throwable) {
                    false
                }
            }
        }
    }

    private fun getHardwareId(context: Context): String {
        val androidId = try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (_: Throwable) {
            null
        }

        if (!androidId.isNullOrBlank() && androidId.lowercase(Locale.ROOT) != "9774d56d682e549c") {
            return "android-$androidId"
        }

        // Fallback for rare devices with broken ANDROID_ID
        val fallback = listOfNotNull(Build.BRAND, Build.MODEL, Build.DEVICE, Build.FINGERPRINT)
            .joinToString("|")
            .ifBlank { "unknown-device" }
        return "fp-${fallback.hashCode()}"
    }

    private fun getCountryCode(context: Context): String {
        // Try SIM first
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        val simCountry = tm?.simCountryIso?.uppercase(Locale.ROOT)
        if (!simCountry.isNullOrBlank()) return simCountry

        // Fallback to network country
        val networkCountry = tm?.networkCountryIso?.uppercase(Locale.ROOT)
        if (!networkCountry.isNullOrBlank()) return networkCountry

        // Fallback to locale
        val localeCountry = Locale.getDefault().country?.uppercase(Locale.ROOT)
        if (!localeCountry.isNullOrBlank() && localeCountry != "US") return localeCountry

        // Last resort: TimeZone hint (e.g. Europe/Moscow -> RU)
        val tzId = java.util.TimeZone.getDefault().id
        if (tzId.contains("Moscow") || tzId.contains("Samara") || tzId.contains("Yekaterinburg")) return "RU"
        if (tzId.contains("London") || tzId.contains("Europe")) return "EU"
        
        return localeCountry ?: "UNKNOWN"
    }

    private fun getConnectionType(context: Context): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "unknown"

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return "unknown"
            val capabilities = cm.getNetworkCapabilities(network) ?: return "unknown"

            when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "unknown"
            }
        } else {
            @Suppress("DEPRECATION")
            val activeNetwork = cm.activeNetworkInfo
            @Suppress("DEPRECATION")
            when (activeNetwork?.type) {
                ConnectivityManager.TYPE_WIFI -> "wifi"
                ConnectivityManager.TYPE_MOBILE -> "cellular"
                ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                else -> "unknown"
            }
        }
    }
}
