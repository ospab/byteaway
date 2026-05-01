package com.ospab.byteaway

import android.content.Context
import androidx.multidex.MultiDex
import com.ospab.byteaway.utils.DeviceInfoChannel
import com.ospab.byteaway.utils.ApkUpdateChannel
import com.ospab.byteaway.utils.AppChannel
import com.ospab.byteaway.receiver.ConditionReceiver
import com.ospab.byteaway.service.ServiceBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.annotation.NonNull

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            // Register platform channel bridge
            ServiceBridge.register(flutterEngine, this)
            
            // Register device info channel
            DeviceInfoChannel.register(this, flutterEngine)

            // Register APK updater channel
            ApkUpdateChannel.register(this, flutterEngine)

            // Register AppChannel for split tunnel
            AppChannel.register(this, flutterEngine)
        } catch (t: Throwable) {
            android.util.Log.e("ByteAway", "Failed to register ServiceBridge", t)
        }

        // Register a global uncaught exception handler and forward to in-app logs
        try {
            val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                try {
                    val trace = android.util.Log.getStackTraceString(throwable)
                    val msg = "Uncaught exception in thread ${thread.name}: ${throwable::class.java.simpleName}: ${throwable.message ?: ""}\n$trace"
                    android.util.Log.e("ByteAway", msg)
                    ServiceBridge.emitNativeLog(msg)
                } catch (_: Throwable) {}
                defaultHandler?.uncaughtException(thread, throwable)
            }
        } catch (t: Throwable) {
            android.util.Log.e("ByteAway", "Failed to register global uncaught exception handler", t)
        }

        // Start monitoring WiFi + charging conditions
        ConditionReceiver.registerNetworkCallback(applicationContext)
    }

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase)
        MultiDex.install(this)
    }

    override fun onDestroy() {
        ConditionReceiver.unregisterNetworkCallback(applicationContext)
        ServiceBridge.clearActivity()
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        ServiceBridge.handleActivityResult(this, requestCode, resultCode)
    }
}
