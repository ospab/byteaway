package com.ospab.byteaway.service

import android.app.*
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.io.IOException
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.*
import okhttp3.*
import okio.ByteString
import okio.ByteString.Companion.toByteString

import java.io.FileOutputStream
import java.nio.charset.StandardCharsets

import com.ospab.byteaway.service.ServiceBridge

import android.net.VpnService
import android.os.ParcelFileDescriptor
import boxwrapper.Boxwrapper
import boxwrapper.SocketProtector

class ByteAwayForegroundService : VpnService(), SocketProtector {

    private var tunInterface: ParcelFileDescriptor? = null

    override fun protect(fd: Int): Boolean {
        return super.protect(fd)
    }

    companion object {
        const val ACTION_TOGGLE_VPN = "com.byteaway.TOGGLE_VPN"
        const val CHANNEL_ID = "byteaway_service"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START_VPN = "com.byteaway.START_VPN"
        const val ACTION_STOP_VPN = "com.byteaway.STOP_VPN"
        const val ACTION_START_NODE = "com.byteaway.START_NODE"
        const val ACTION_STOP_NODE = "com.byteaway.STOP_NODE"

        // Exclude app management actions
        const val ACTION_ADD_EXCLUDE = "com.byteaway.ADD_EXCLUDE"
        const val ACTION_REMOVE_EXCLUDE = "com.byteaway.REMOVE_EXCLUDE"
        const val EXTRA_EXCLUDE_PKG = "com.byteaway.EXTRA_EXCLUDE_PKG"

        const val EXTRA_VPN_CONFIG = "com.byteaway.EXTRA_VPN_CONFIG"
        const val DEFAULT_NODE_WS_URL = "wss://byteaway.xyz/ws"

        // Wire protocol constants (match master_node/ws_tunnel.rs)
        const val CMD_CONNECT: Byte = 0x01
        const val CMD_DATA: Byte = 0x02
        const val CMD_CLOSE: Byte = 0x03

        // sing-box intent/extra keys (used when starting the embedded AAR service)
        const val SINGBOX_ACTION_KEY = "com.tim.singBox.action"
        const val SINGBOX_ACTION_START = "start"
        const val SINGBOX_ACTION_STOP = "stop"
        const val SINGBOX_CONFIGURATION_KEY = "com.tim.singBox.config"

        // Global State
        @JvmStatic
        val isVpnRunning = AtomicBoolean(false)
        @JvmStatic
        val isNodeActive = AtomicBoolean(false)
        @JvmStatic
        val isVpnConnecting = AtomicBoolean(false)
        @JvmStatic
        val isNodeConnecting = AtomicBoolean(false)
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var webSocket: WebSocket? = null
    private val httpClient = OkHttpClient.Builder()
        .pingInterval(java.time.Duration.ofSeconds(60))
        .socketFactory(object : javax.net.SocketFactory() {
            override fun createSocket(): java.net.Socket {
                val s = java.net.Socket()
                protect(s)
                return s
            }
            override fun createSocket(host: String?, port: Int): java.net.Socket = createSocket()
            override fun createSocket(host: String?, port: Int, localHost: java.net.InetAddress?, localPort: Int): java.net.Socket = createSocket()
            override fun createSocket(host: java.net.InetAddress?, port: Int): java.net.Socket = createSocket()
            override fun createSocket(address: java.net.InetAddress?, port: Int, localAddress: java.net.InetAddress?, localPort: Int): java.net.Socket = createSocket()
        })
        .build()

    private val totalBytesShared = AtomicLong(0)
    private var nodeStartTime: Long = 0
    private var nodeErrorMessage: String? = null
    private var reconnectAttempts: Int = 0

    // Active tunnel sessions: session_id -> SocketChannel
    private val sessions = ConcurrentHashMap<UUID, SocketChannel>()

    // Wake lock to prevent CPU sleep during sharing
    private var wakeLock: PowerManager.WakeLock? = null

    // Simple file logger for emulator environments without easy logcat access
    private fun appendLog(message: String) {
        try {
            val ts = java.time.Instant.now().toString()
            val entry = "[$ts] $message\n"
            val fos: FileOutputStream = openFileOutput("byteaway_error.log", Context.MODE_APPEND)
            fos.write(entry.toByteArray(StandardCharsets.UTF_8))
            fos.close()
        } catch (t: Throwable) {
            android.util.Log.e("ByteAway", "Failed to write internal log", t)
        }
    }

    private fun appendExternalLog(message: String) {
        try {
            val ts = java.time.Instant.now().toString()
            val entry = "[$ts] $message\n"
            val dir = getExternalFilesDir(null)
                if (dir != null) {
                    val outFile = java.io.File(dir, "byteaway_error_external.txt")
                val fos = FileOutputStream(outFile, true)
                fos.write(entry.toByteArray(StandardCharsets.UTF_8))
                fos.flush()
                fos.close()
            } else {
                // Fallback to internal
                appendLog(message)
            }
        } catch (t: Throwable) {
            android.util.Log.e("ByteAway", "Failed to write external log", t)
            try { appendLog("Failed to write external log: ${t.message}") } catch (_: Throwable) {}
        }
    }

    override fun onCreate() {
        super.onCreate()
        Boxwrapper.setSocketProtector(this)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("ByteAway сервис запущен"))
        // Ensure any uncaught exceptions are logged
        registerUncaughtExceptionHandler()
        // Migrate any old .log external file to .txt for easier access
        migrateExternalLogIfNeeded()
    }

    private fun migrateExternalLogIfNeeded() {
        try {
            val dir = getExternalFilesDir(null) ?: return
            val oldFile = java.io.File(dir, "byteaway_error_external.log")
            val newFile = java.io.File(dir, "byteaway_error_external.txt")
            if (oldFile.exists() && !newFile.exists()) {
                oldFile.copyTo(newFile)
                oldFile.delete()
            }
        } catch (t: Throwable) {
            android.util.Log.e("ByteAway", "Failed to migrate external log file", t)
        }
    }

    private fun registerUncaughtExceptionHandler() {
        try {
            val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                try {
                    val trace = android.util.Log.getStackTraceString(throwable)
                    val msg = "Uncaught exception in thread ${thread.name}: ${throwable::class.java.simpleName}: ${throwable.message ?: ""}\n$trace"
                    android.util.Log.e("ByteAway", msg)
                    appendLog(msg)
                    appendExternalLog(msg)
                } catch (_: Throwable) {}
                // Delegate to previous handler to let system handle the crash
                defaultHandler?.uncaughtException(thread, throwable)
            }
        } catch (t: Throwable) {
            android.util.Log.e("ByteAway", "Failed to register uncaught exception handler", t)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            android.util.Log.i("ByteAway", "onStartCommand action=${intent?.action}")

            when (intent?.action) {
            ACTION_START_VPN -> {
                val cfg = intent.getStringExtra(EXTRA_VPN_CONFIG) ?: "{}"
                android.util.Log.i("ByteAway", "action START_VPN cfgLen=${cfg.length}")
                startVpn(cfg)
            }
            ACTION_STOP_VPN -> {
                android.util.Log.i("ByteAway", "action STOP_VPN")
                stopVpn()
            }
            ACTION_START_NODE -> {
                val token = intent.getStringExtra("token") ?: ""
                val deviceId = intent.getStringExtra("deviceId") ?: ""
                val country = intent.getStringExtra("country") ?: "auto"
                val connType = intent.getStringExtra("connType") ?: "wifi"
                val transportMode = intent.getStringExtra("transportMode") ?: "quic"
                val speedMbps = intent.getIntExtra("speedMbps", 50)
                val mtu = intent.getIntExtra("mtu", 1280)
                val masterWsUrl = intent.getStringExtra("masterWsUrl")
                startNode(
                    token = token,
                    deviceId = deviceId,
                    country = country,
                    connType = connType,
                    transportMode = transportMode,
                    speedMbps = speedMbps,
                    mtu = mtu,
                    masterWsUrl = masterWsUrl,
                )
            }
            ACTION_STOP_NODE -> stopNode()
            }
        } catch (t: Throwable) {
            val trace = android.util.Log.getStackTraceString(t).lineSequence().take(20).joinToString(" | ")
            val msg = "onStartCommand error: ${t::class.java.simpleName}: ${t.message ?: ""} [${trace}]"
            android.util.Log.e("ByteAway", msg, t)
            appendLog(msg)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ──────────────────────────────────────────────────────
    // VPN Management (sing-box)
    // ──────────────────────────────────────────────────────

    private fun startVpn(config: String) {
        if (config.isEmpty() || config == "{}") {
            android.util.Log.w("ByteAway", "startVpn skipped: empty config")
            return
        }

        android.util.Log.i("ByteAway", "startVpn invoked, config length=${config.length}")
        isVpnConnecting.set(true)
        broadcastState()

        // Parse JSON config from Flutter (contains vless_link, tier, max_speed_mbps)
        var vlessLink = config
        var tier = "free"
        var maxSpeedMbps = 10
        
        if (config.startsWith("{")) {
            try {
                val json = org.json.JSONObject(config)
                vlessLink = json.optString("vless_link", config)
                tier = json.optString("tier", "free")
                maxSpeedMbps = json.optInt("max_speed_mbps", 10)
                android.util.Log.i("ByteAway", "Parsed config: tier=$tier, maxSpeed=${maxSpeedMbps}Mbps")
            } catch (e: Exception) {
                android.util.Log.w("ByteAway", "Failed to parse JSON config, using defaults: ${e.message}")
            }
        }

        // Call startForeground immediately to prevent ForegroundServiceStartNotAllowedException or ANR crashes
        startForeground(NOTIFICATION_ID, buildNotification("Подключение VPN..."))

        scope.launch {
            try {
                // 1. Establish TUN interface
                val builder = Builder()
                    .setSession("ByteAway VPN")
                    .setMtu(1500)
                    .addAddress("172.19.0.1", 30)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer("8.8.8.8")
                    .addDnsServer("1.1.1.1")
                
                // Set blocking to false for better performance with sing-box 1.11+
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    builder.setMetered(false)
                }

                // Ensure ByteAway itself is excluded from the VPN tunnel (per docs)
                try {
                    val selfPkg = applicationContext.packageName
                    try {
                        builder.addDisallowedApplication(selfPkg)
                        android.util.Log.i("ByteAway", "Added self to VPN disallowed apps: $selfPkg")
                    } catch (e: Throwable) {
                        // Some platform versions or OEMs may throw when manipulating app lists
                        android.util.Log.w("ByteAway", "addDisallowedApplication failed: ${e.message}")
                    }
                } catch (_: Throwable) {
                    // ignore
                }
                
                tunInterface = builder.establish()
                if (tunInterface == null) {
                    throw Exception("Failed to establish TUN interface (permission denied or another VPN active)")
                }

                val fd = tunInterface!!.fd
                android.util.Log.i("ByteAway", "TUN established with FD: $fd")

                val finalConfig = if (vlessLink.startsWith("vless://")) {
                    wrapVlessToJson(vlessLink, tier, maxSpeedMbps, fd)
                } else if (vlessLink.startsWith("hy2://")) {
                    wrapHy2ToJson(vlessLink, tier, maxSpeedMbps, fd)
                } else {
                    vlessLink.replace("\"interface_name\": \"tun0\",", "\"interface_name\": \"tun0\",\n              \"file_descriptor\": $fd,")
                }

                android.util.Log.i("ByteAway", "startVpn final singbox config length=${finalConfig.length}")

                // 2. Start sing-box via Go core
                Boxwrapper.startSingBox(finalConfig, fd.toLong())

                isVpnRunning.set(true)
                isVpnConnecting.set(false)
                nodeErrorMessage = null
                android.util.Log.i("ByteAway", "SingBox VPN started successfully via Go core")
                
                // Keep service alive with updated notification
                val manager = getSystemService(NotificationManager::class.java)
                manager?.notify(NOTIFICATION_ID, buildNotification("VPN соединение активно"))
                
                broadcastState()
            } catch (e: Exception) {
                val trace = android.util.Log.getStackTraceString(e).lineSequence().take(10).joinToString(" | ")
                val err = "${e::class.java.simpleName}: ${e.message ?: "unknown"} [${trace}]"
                android.util.Log.e("ByteAway", "Failed to start singBox VPN: $err")
                
                tunInterface?.close()
                tunInterface = null
                
                isVpnRunning.set(false)
                isVpnConnecting.set(false)
                nodeErrorMessage = err
                appendLog("startVpn error: $err")
                updateNotification()
                broadcastState()
            }
        }
    }


    private fun wrapVlessToJson(vlessLink: String, tier: String = "free", maxSpeedMbps: Int = 10, fd: Int = -1): String {
        // Simple VLESS -> sing-box JSON wrapper
        val uriStr = vlessLink.removePrefix("vless://")
        val atIndex = uriStr.indexOf('@')
        val queryIndex = uriStr.indexOf('?')
        
        val uuid = if (atIndex != -1) uriStr.substring(0, atIndex) else ""
        val hostAndPort = if (atIndex != -1) {
            if (queryIndex != -1) uriStr.substring(atIndex + 1, queryIndex) else uriStr.substring(atIndex + 1)
        } else "byteaway.xyz:443"

        val hostParts = hostAndPort.split(":")
        val host = hostParts[0]
        val port = if (hostParts.size > 1) hostParts[1].toIntOrNull() ?: 443 else 443

        // Extract params from query string (security=reality&pbk=...&sid=...)
        val params = mutableMapOf<String, String>()
        if (queryIndex != -1) {
            val query = uriStr.substring(queryIndex + 1).split("#")[0]
            query.split("&").forEach { part ->
                val pair = part.split("=")
                if (pair.size == 2) params[pair[0]] = pair[1]
            }
        }

        val pubKey = params["pbk"] ?: ""
        val shortId = params["sid"] ?: ""
        val sni = params["sni"] ?: "google.com"
        
        android.util.Log.i(
            "ByteAway",
            "Parsed VLESS: host=$host port=$port sni=$sni tier=$tier maxSpeed=${maxSpeedMbps}Mbps pubKeySet=${pubKey.isNotEmpty()} fd=$fd"
        )
        
        val fdConfig = if (fd > 0) ",\n              \"file_descriptor\": $fd" else ""

        return """
        {
          "log": { "level": "info" },
          "inbounds": [
            {
              "type": "tun",
              "tag": "tun-in",
              "interface_name": "tun0",
              "address": [ "172.19.0.1/30" ]$fdConfig,
              "mtu": 1500,
              "auto_route": false,
              "strict_route": false,
              "stack": "system"
            }
          ],
          "outbounds": [
            {
              "type": "vless",
              "tag": "vless-out",
              "server": "$host",
              "server_port": $port,
              "uuid": "$uuid",
              "flow": "xtls-rprx-vision",
              "tls": {
                "enabled": true,
                "server_name": "$sni",
                "utls": { "enabled": true, "fingerprint": "chrome" },
                "reality": {
                  "enabled": true,
                  "public_key": "$pubKey",
                  "short_id": "$shortId"
                }
              }
            },
            { "type": "direct", "tag": "direct-out" }
          ],
          "dns": {
            "servers": [
              {
                "tag": "dns-remote",
                "type": "udp",
                "server": "1.1.1.1"
              }
            ]
          },
          "route": {
             "auto_detect_interface": false,
             "final": "vless-out",
             "rules": [
               { "action": "sniff" },
               { "protocol": "dns", "action": "hijack-dns" },
               { "action": "sniff" }
             ]
          }
        }
        """.trimIndent()

    }

    private fun wrapHy2ToJson(hy2Link: String, tier: String = "free", maxSpeedMbps: Int = 10, fd: Int = -1): String {
        val uriStr = hy2Link.removePrefix("hy2://")
        val atIndex = uriStr.indexOf('@')
        val queryIndex = uriStr.indexOf('?')
        
        val password = if (atIndex != -1) uriStr.substring(0, atIndex) else ""
        val hostAndPort = if (atIndex != -1) {
            if (queryIndex != -1) uriStr.substring(atIndex + 1, queryIndex) else uriStr.substring(atIndex + 1)
        } else "byteaway.xyz:4433"

        val hostParts = hostAndPort.split(":")
        val host = hostParts[0]
        val port = if (hostParts.size > 1) hostParts[1].toIntOrNull() ?: 4433 else 4433

        val params = mutableMapOf<String, String>()
        if (queryIndex != -1) {
            val query = uriStr.substring(queryIndex + 1).split("#")[0]
            query.split("&").forEach { part ->
                val pair = part.split("=")
                if (pair.size == 2) params[pair[0]] = pair[1]
            }
        }
        val sni = params["sni"] ?: host
        
        android.util.Log.i(
            "ByteAway",
            "Parsed HY2: host=$host port=$port sni=$sni tier=$tier maxSpeed=${maxSpeedMbps}Mbps fd=$fd"
        )
        
        val fdConfig = if (fd > 0) ",\n              \"file_descriptor\": $fd" else ""

        return """
        {
          "log": { "level": "info" },
          "inbounds": [
            {
              "type": "tun",
              "tag": "tun-in",
              "interface_name": "tun0",
              "address": [ "172.19.0.1/30" ]$fdConfig,
              "mtu": 1500,
              "auto_route": false,
              "strict_route": false,
              "stack": "system"
            }
          ],
          "outbounds": [
            {
              "type": "hysteria2",
              "tag": "hy2-out",
              "server": "$host",
              "server_port": $port,
              "password": "$password",
              "tls": {
                "enabled": true,
                "server_name": "$sni",
                "insecure": true
              }
            },
            { "type": "direct", "tag": "direct-out" }
          ],
          "dns": {
            "servers": [
              {
                "tag": "dns-remote",
                "type": "udp",
                "server": "1.1.1.1"
              }
            ]
          },
          "route": {
             "auto_detect_interface": false,
             "final": "hy2-out",
             "rules": [
               { "action": "sniff" },
               { "protocol": "dns", "action": "hijack-dns" },
               { "action": "sniff" }
             ]
          }
        }
        """.trimIndent()
    }

    private fun stopVpn() {
        scope.launch {
            try {
                // 1. Stop sing-box Go core
                try {
                    Boxwrapper.stopSingBox()
                    android.util.Log.i("ByteAway", "SingBox VPN stopped via Go core")
                } catch (e: Exception) {
                    android.util.Log.w("ByteAway", "Failed to stop sing-box via Go core: ${e.message}")
                }

                // 2. Close TUN interface
                try {
                    tunInterface?.close()
                    tunInterface = null
                    android.util.Log.i("ByteAway", "TUN interface closed")
                } catch (e: Exception) {
                    android.util.Log.e("ByteAway", "Failed to close TUN interface", e)
                }

                isVpnRunning.set(false)
                if (!isNodeActive.get()) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    // stopSelf()
                } else {
                    updateNotification()
                }
                broadcastState()
            } catch (e: Exception) {
                android.util.Log.e("ByteAway", "Failed to stop VPN", e)
                isVpnRunning.set(false)
                appendLog("stopVpn error: ${e::class.java.simpleName}: ${e.message ?: ""}")
                broadcastState()
            }
        }
    }

    // ──────────────────────────────────────────────────────
    // Node (traffic sharing) Management
    // ──────────────────────────────────────────────────────

    private fun startNode(
        token: String,
        deviceId: String,
        country: String,
        connType: String,
        transportMode: String,
        speedMbps: Int,
        mtu: Int,
        masterWsUrl: String? = null,
    ) {
        try {
            if (isNodeActive.get() || isNodeConnecting.get()) {
                android.util.Log.d("ByteAway", "Node already active or connecting, skipping startNode")
                return
            }

            android.util.Log.i(
                "ByteAway",
                "startNode invoked: deviceId=$deviceId country=$country connType=$connType transport=$transportMode speed=$speedMbps mtu=$mtu"
            )

            isNodeConnecting.set(true)
            startForeground(NOTIFICATION_ID, buildNotification("Подключение к мастер ноде..."))
            acquireWakeLock()
            nodeStartTime = System.currentTimeMillis()

            val baseWsUrl = masterWsUrl?.takeIf { it.isNotBlank() } ?: DEFAULT_NODE_WS_URL
            val normalizedConnType = when (connType.trim().lowercase(Locale.ROOT)) {
                "cellular", "mobile", "lte", "5g", "4g", "3g" -> "mobile"
                else -> "wifi"
            }

            scope.launch(Dispatchers.IO) {
                try {
                    val host = try {
                        val uri = java.net.URI(baseWsUrl)
                        uri.host ?: "byteaway.xyz"
                    } catch (_: Exception) {
                        "byteaway.xyz"
                    }

                    android.util.Log.i("ByteAway", "Connecting node transport via Go core: mode=$transportMode host=$host")
                    
                    when (transportMode.lowercase(Locale.ROOT)) {
                        "quic" -> {
                            val endpoint = "$host:31280"
                            Boxwrapper.startNodeQuic(endpoint, deviceId, token, country, normalizedConnType, speedMbps.toLong(), mtu.toLong())
                        }
                        "ws" -> {
                            val wsUrl = (if (baseWsUrl.startsWith("ws")) baseWsUrl else "wss://$host/ws") + 
                                "?device_id=$deviceId&token=$token&country=$country&conn_type=$normalizedConnType&speed_mbps=$speedMbps"
                            Boxwrapper.startNodeWs(wsUrl, deviceId, token, country, normalizedConnType, speedMbps.toLong(), "")
                        }
                        "tuic" -> {
                            val endpoint = "$host:31280"
                            Boxwrapper.startNodeTuic(endpoint, deviceId, token, country, normalizedConnType, speedMbps.toLong(), mtu.toLong())
                        }
                        "ostp" -> {
                            val endpoint = "$host:31280"
                            Boxwrapper.startNodeOstp(endpoint, deviceId, token, country, normalizedConnType, speedMbps.toLong(), mtu.toLong())
                        }
                        else -> {
                            val endpoint = "$host:31280"
                            Boxwrapper.startNodeQuic(endpoint, deviceId, token, country, normalizedConnType, speedMbps.toLong(), mtu.toLong())
                        }
                    }

                    isNodeActive.set(true)
                    isNodeConnecting.set(false)
                    nodeErrorMessage = null
                    reconnectAttempts = 0
                    withContext(Dispatchers.Main) {
                        broadcastState()
                        updateNotification()
                    }
                    android.util.Log.i("ByteAway", "Node connected successfully via Go core ($transportMode)")

                    // Polling reader loop for Go core
                    while (isNodeActive.get()) {
                        try {
                            val frame = Boxwrapper.readNodeFrame()
                            if (frame == null || frame.isEmpty()) {
                                delay(10)
                                continue
                            }
                            withContext(Dispatchers.Main) {
                                handleIncomingFrame(frame)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("ByteAway", "Read error from Go core", e)
                            break
                        }
                    }
                } catch (t: Throwable) {
                    val trace = android.util.Log.getStackTraceString(t).lineSequence().take(20).joinToString(" | ")
                    val msg = "startNode error: ${t::class.java.simpleName}: ${t.message ?: ""} [${trace}]"
                    android.util.Log.e("ByteAway", msg, t)
                    appendLog(msg)
                    isNodeConnecting.set(false)
                    withContext(Dispatchers.Main) {
                        onNodeDisconnected()
                    }
                }
            }
        } catch (t: Throwable) {
            val trace = android.util.Log.getStackTraceString(t).lineSequence().take(20).joinToString(" | ")
            val msg = "startNode error outer: ${t::class.java.simpleName}: ${t.message ?: ""} [${trace}]"
            android.util.Log.e("ByteAway", msg, t)
            appendLog(msg)
            isNodeConnecting.set(false)
            onNodeDisconnected()
        }
    }

    private fun stopNode() {
        try {
            isNodeActive.set(false)
            try {
                Boxwrapper.stopNodeTransport()
            } catch (_: Exception) {}
            webSocket?.close(1000, "User stopped sharing")
            webSocket = null

            // Close all active sessions
            sessions.values.forEach { channel ->
                try { channel.close() } catch (_: Exception) {}
            }
            sessions.clear()
            releaseWakeLock()

            if (!isVpnRunning.get()) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            } else {
                updateNotification()
            }
            broadcastState()
        } catch (t: Throwable) {
            val trace = android.util.Log.getStackTraceString(t).lineSequence().take(10).joinToString(" | ")
            val msg = "stopNode error: ${t::class.java.simpleName}: ${t.message ?: ""} [${trace}]"
            android.util.Log.e("ByteAway", msg, t)
            appendLog(msg)
        }
    }

    private fun onNodeDisconnected() {
        isNodeActive.set(false)
        isNodeConnecting.set(false)
        nodeErrorMessage = nodeErrorMessage ?: "Node disconnected"
        sessions.values.forEach { channel ->
            try { channel.close() } catch (_: Exception) {}
        }
        sessions.clear()
        releaseWakeLock()
        updateNotification()
        broadcastState()
    }

    private fun scheduleReconnect(
        token: String,
        deviceId: String,
        country: String,
        connType: String,
        transportMode: String,
        speedMbps: Int,
        mtu: Int,
        masterWsUrl: String?,
    ) {
        scope.launch {
            if (isNodeActive.get() || isNodeConnecting.get()) return@launch

            reconnectAttempts = (reconnectAttempts + 1).coerceAtMost(12)
            val delayMs = (5000L * (1 shl (reconnectAttempts - 1))).coerceAtMost(60_000L)

            android.util.Log.i("ByteAway", "Scheduling node reconnect in ${delayMs / 1000} sec (attempt $reconnectAttempts)")
            delay(delayMs)

            if (!isNodeActive.get() && !isNodeConnecting.get()) {
                android.util.Log.i("ByteAway", "Reconnecting node attempt $reconnectAttempts")
                startNode(
                    token = token,
                    deviceId = deviceId,
                    country = country,
                    connType = connType,
                    transportMode = transportMode,
                    speedMbps = speedMbps,
                    mtu = mtu,
                    masterWsUrl = masterWsUrl,
                )
            }
        }
    }

    // ──────────────────────────────────────────────────────
    // Wire Protocol Handler
    // ──────────────────────────────────────────────────────

    /**
     * Decode incoming WebSocket binary frame:
     * [1 byte: cmd][16 bytes: session_uuid][N bytes: payload]
     */
    private fun handleIncomingFrame(data: ByteArray) {
        if (data.size < 17) return

        val cmd = data[0]
        val sessionIdBytes = data.sliceArray(1..16)
        val sessionId = bytesToUUID(sessionIdBytes)
        val payload = data.sliceArray(17 until data.size)

        when (cmd) {
            CMD_CONNECT -> handleConnect(sessionId, String(payload))
            CMD_DATA -> handleData(sessionId, payload)
            CMD_CLOSE -> handleClose(sessionId)
        }
    }

    /**
     * CMD_CONNECT: Open TCP connection to target address.
     * Target format: "host:port"
     */
    private fun handleConnect(sessionId: UUID, targetAddr: String) {
        scope.launch {
            try {
                val parts = targetAddr.split(":")
                if (parts.size != 2) return@launch

                val host = parts[0]
                val port = parts[1].toIntOrNull() ?: return@launch

                val channel = SocketChannel.open()
                protect(channel.socket())
                channel.configureBlocking(false)
                channel.connect(InetSocketAddress(host, port))

                // Wait for connection
                while (!channel.finishConnect()) {
                    delay(10)
                }

                sessions[sessionId] = channel

                // Start reading from target and forwarding to WebSocket
                launch {
                    readFromTarget(sessionId, channel)
                }
            } catch (e: Exception) {
                // Send close back to master
                sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
            }
        }
    }

    /**
     * CMD_DATA: Forward data to target TCP connection.
     */
    private fun handleData(sessionId: UUID, payload: ByteArray) {
        val channel = sessions[sessionId] ?: return

        scope.launch {
            try {
                val buffer = ByteBuffer.wrap(payload)
                while (buffer.hasRemaining()) {
                    channel.write(buffer)
                }
                totalBytesShared.addAndGet(payload.size.toLong())
                withContext(Dispatchers.Main) {
                    broadcastState()
                }
            } catch (e: IOException) {
                handleClose(sessionId)
                sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
            }
        }
    }

    /**
     * CMD_CLOSE: Close session and release resources.
     */
    private fun handleClose(sessionId: UUID) {
        val channel = sessions.remove(sessionId)
        try { channel?.close() } catch (_: Exception) {}
    }

    /**
     * Read data from target TCP and send back through WebSocket.
     */
    private suspend fun readFromTarget(sessionId: UUID, channel: SocketChannel) {
        val buffer = ByteBuffer.allocate(32768) // 32KB read buffer

        try {
            while (channel.isOpen && isNodeActive.get()) {
                buffer.clear()
                val bytesRead = withContext(Dispatchers.IO) {
                    channel.read(buffer)
                }

                if (bytesRead == -1) {
                    // EOF
                    sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
                    sessions.remove(sessionId)
                    channel.close()
                    return
                }

                if (bytesRead > 0) {
                    buffer.flip()
                    val data = ByteArray(buffer.remaining())
                    buffer.get(data)
                    sendFrame(CMD_DATA, sessionId, data)
                    totalBytesShared.addAndGet(data.size.toLong())
                } else {
                    delay(10) // Non-blocking, wait a bit
                }
            }
        } catch (e: Exception) {
            sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
            sessions.remove(sessionId)
            try { channel.close() } catch (_: Exception) {}
        }
    }

    // ──────────────────────────────────────────────────────
    // Wire Protocol Encoder
    // ──────────────────────────────────────────────────────

    private fun sendFrame(cmd: Byte, sessionId: UUID, payload: ByteArray) {
        val frame = ByteArray(1 + 16 + payload.size)
        frame[0] = cmd
        uuidToBytes(sessionId).copyInto(frame, 1)
        payload.copyInto(frame, 17)
        if (webSocket != null) {
            webSocket?.send(frame.toByteString(0, frame.size))
        } else {
            val sent = Boxwrapper.sendNodeFrame(frame)
            if (!sent) {
                android.util.Log.w("ByteAway", "Failed to send frame via Go core")
            }
        }
    }

    // ──────────────────────────────────────────────────────
    // UUID ↔ ByteArray helpers
    // ──────────────────────────────────────────────────────

    private fun uuidToBytes(uuid: UUID): ByteArray {
        val buffer = ByteBuffer.allocate(16)
        buffer.putLong(uuid.mostSignificantBits)
        buffer.putLong(uuid.leastSignificantBits)
        return buffer.array()
    }

    private fun bytesToUUID(bytes: ByteArray): UUID {
        val buffer = ByteBuffer.wrap(bytes)
        return UUID(buffer.long, buffer.long)
    }

    // ──────────────────────────────────────────────────────
    // Notification
    // ──────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ByteAway Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN и шаринг трафика"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, com.ospab.byteaway.MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val statusText = when {
            isVpnRunning.get() && isNodeActive.get() -> "VPN + Sharing активны"
            isVpnRunning.get() -> "VPN активен"
            isNodeActive.get() -> "Bandwidth sharing активен"
            else -> text
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ByteAway")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun updateNotification() {
        val notification = buildNotification("ByteAway активен")
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    // ──────────────────────────────────────────────────────
    // State broadcasting to Flutter (via ServiceBridge)
    // ──────────────────────────────────────────────────────

    private fun broadcastState() {
        val map = mapOf(
            "vpnConnected" to isVpnRunning.get(),
            "vpnConnecting" to isVpnConnecting.get(),
            "nodeActive" to isNodeActive.get(),
            "nodeConnecting" to isNodeConnecting.get(),
            "errorMessage" to (if (isVpnRunning.get()) "" else (nodeErrorMessage ?: "")),
            "nodeErrorMessage" to (if (isNodeActive.get()) "" else (nodeErrorMessage ?: "")),
            "bytesShared" to totalBytesShared.get(),
            "activeSessions" to sessions.size,
            "uptime" to (if (isNodeActive.get() && nodeStartTime > 0) (System.currentTimeMillis() - nodeStartTime) / 1000 else 0L),
            "currentSpeed" to 0.0,
            "bytesIn" to 0L,
            "bytesOut" to 0L
        )
        ServiceBridge.sendEvent(map)
        updateNotification()
    }

    override fun onDestroy() {
        scope.cancel()
        stopNode()
        stopVpn()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "byteaway:node_sharing"
            )
            wakeLock?.acquire(10 * 60 * 60 * 1000L) 
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
