package com.ospab.byteaway

import android.content.Context
import com.ospab.byteaway.service.ServiceBridge
import com.ospab.byteaway.utils.ApkUpdateChannel
import com.ospab.byteaway.utils.AppChannel
import com.ospab.byteaway.utils.DeviceInfoChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		ServiceBridge.register(flutterEngine, this)
		DeviceInfoChannel.register(this, flutterEngine)
		ApkUpdateChannel.register(this, flutterEngine)
		AppChannel.register(this, flutterEngine)
	}

	override fun attachBaseContext(newBase: Context) {
		super.attachBaseContext(newBase)
	}

	@Deprecated("Deprecated in Java")
	override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		ServiceBridge.handleActivityResult(this, requestCode, resultCode)
	}

	override fun onDestroy() {
		ServiceBridge.clearActivity()
		super.onDestroy()
	}
}
