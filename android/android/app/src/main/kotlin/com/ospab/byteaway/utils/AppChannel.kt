package com.ospab.byteaway.utils

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import com.ospab.byteaway.service.ByteAwayForegroundService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

object AppChannel {
    private const val CHANNEL = "com.ospab.byteaway/app"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    Thread {
                        try {
                            val apps = getInstalledApps(context)
                            context.mainExecutor.execute {
                                result.success(apps)
                            }
                        } catch (e: Exception) {
                            context.mainExecutor.execute {
                                result.error("ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "getExcludedApps" -> {
                    val prefs = context.getSharedPreferences("byteaway_prefs", Context.MODE_PRIVATE)
                    result.success(prefs.getStringSet("excluded_apps", emptySet())?.toList())
                }
                "addExclude" -> {
                    val pkg = call.argument<String>("pkg")
                    if (pkg != null) {
                        sendIntentToService(context, ByteAwayForegroundService.ACTION_ADD_EXCLUDE, pkg)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "removeExclude" -> {
                    val pkg = call.argument<String>("pkg")
                    if (pkg != null) {
                        sendIntentToService(context, ByteAwayForegroundService.ACTION_REMOVE_EXCLUDE, pkg)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getInstalledApps(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        // In Android 11+ (API 30+), we need the <queries> tag in AndroidManifest.xml to see other apps.
        val flags = PackageManager.GET_META_DATA or PackageManager.GET_SHARED_LIBRARY_FILES
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(flags.toLong()))
        } else {
            pm.getInstalledApplications(flags)
        }

        return packages.mapNotNull { appInfo ->
            try {
                // Show all apps including system apps for comprehensive split-tunnel control
                // Similar to NekoBox approach
                val label = pm.getApplicationLabel(appInfo).toString()
                val iconDrawable = pm.getApplicationIcon(appInfo)
                
                val bitmap = if (iconDrawable is BitmapDrawable) {
                    iconDrawable.bitmap
                } else {
                    val bmp = Bitmap.createBitmap(
                        iconDrawable.intrinsicWidth.coerceAtLeast(1),
                        iconDrawable.intrinsicHeight.coerceAtLeast(1),
                        Bitmap.Config.ARGB_8888
                    )
                    val canvas = Canvas(bmp)
                    iconDrawable.setBounds(0, 0, canvas.width, canvas.height)
                    iconDrawable.draw(canvas)
                    bmp
                }

                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                val iconBytes = stream.toByteArray()
                
                mapOf(
                    "package" to appInfo.packageName,
                    "label" to label,
                    "icon" to iconBytes,
                    "isSystem" to (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM != 0),
                    "uid" to appInfo.uid
                )
            } catch (e: Exception) {
                null
            }
        }.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun sendIntentToService(context: Context, action: String, pkg: String) {
        val intent = Intent(context, ByteAwayForegroundService::class.java).apply {
            this.action = action
            putExtra(ByteAwayForegroundService.EXTRA_EXCLUDE_PKG, pkg)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
}
