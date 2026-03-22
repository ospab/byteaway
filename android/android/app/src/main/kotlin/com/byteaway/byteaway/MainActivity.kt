package com.ospab.byteaway

import com.ospab.byteaway.receiver.ConditionReceiver
import com.ospab.byteaway.service.ServiceBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.annotation.NonNull

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register platform channel bridge
        ServiceBridge.register(flutterEngine, applicationContext)

        // Start monitoring WiFi + charging conditions
        ConditionReceiver.registerNetworkCallback(applicationContext)
    }

    override fun onDestroy() {
        ConditionReceiver.unregisterNetworkCallback(applicationContext)
        super.onDestroy()
    }
}

