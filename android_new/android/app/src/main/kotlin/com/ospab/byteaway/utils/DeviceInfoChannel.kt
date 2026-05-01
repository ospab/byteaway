package com.ospab.byteaway.utils

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object DeviceInfoChannel {
    private const val CHANNEL = "com.ospab.byteaway/device"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceId" -> {
                        val id = Settings.Secure.getString(
                            context.contentResolver,
                            Settings.Secure.ANDROID_ID
                        ) ?: ""
                        result.success(id)
                    }
                    "getDeviceInfo" -> {
                        result.success(
                            mapOf(
                                "model" to Build.MODEL,
                                "brand" to Build.BRAND,
                                "sdk" to Build.VERSION.SDK_INT
                            )
                        )
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
                    }
                    "openBatteryOptimizationSettings" -> {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
