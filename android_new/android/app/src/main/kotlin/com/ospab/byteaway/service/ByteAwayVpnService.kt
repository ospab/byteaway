package com.ospab.byteaway.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import boxwrapper.Boxwrapper
import boxwrapper.SocketProtector
import com.ospab.byteaway.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

class ByteAwayVpnService : VpnService(), SocketProtector {
    companion object {
        const val ACTION_START_VPN = "com.byteaway.START_VPN"
        const val ACTION_STOP_VPN = "com.byteaway.STOP_VPN"
        const val ACTION_ADD_EXCLUDE = "com.byteaway.ADD_EXCLUDE"
        const val ACTION_REMOVE_EXCLUDE = "com.byteaway.REMOVE_EXCLUDE"

        const val EXTRA_VPN_CONFIG = "com.byteaway.EXTRA_VPN_CONFIG"
        const val EXTRA_EXCLUDE_PKG = "com.byteaway.EXTRA_EXCLUDE_PKG"

        private const val CHANNEL_ID = "byteaway_vpn"
        private const val NOTIFICATION_ID = 1001
        private const val PREFS = "byteaway_prefs"
        private const val PREFS_EXCLUDED = "excluded_apps"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var tunInterface: ParcelFileDescriptor? = null
    private var currentConfigJson: String? = null
    private var ostpProxy: OstpProxy? = null

    private val isRunning = AtomicBoolean(false)
    private val isConnecting = AtomicBoolean(false)
    private var startAtMillis: Long = 0L

    override fun onCreate() {
        super.onCreate()
        Boxwrapper.setSocketProtector(this)
        createNotificationChannel()
    }

    override fun protect(fd: Int): Boolean = super.protect(fd)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_VPN -> {
                val cfg = intent.getStringExtra(EXTRA_VPN_CONFIG) ?: "{}"
                startVpn(cfg)
            }
            ACTION_STOP_VPN -> stopVpn()
            ACTION_ADD_EXCLUDE -> {
                val pkg = intent.getStringExtra(EXTRA_EXCLUDE_PKG)
                if (!pkg.isNullOrBlank()) {
                    updateExcluded(pkg, true)
                }
            }
            ACTION_REMOVE_EXCLUDE -> {
                val pkg = intent.getStringExtra(EXTRA_EXCLUDE_PKG)
                if (!pkg.isNullOrBlank()) {
                    updateExcluded(pkg, false)
                }
            }
        }
        return START_STICKY
    }

    private fun startVpn(config: String) {
        if (config.isBlank() || config == "{}") return
        if (isConnecting.get()) return

        currentConfigJson = config
        isConnecting.set(true)
        broadcastState(error = "")

        scope.launch {
            try {
                stopVpnInternal(silent = true)

                val parsed = if (config.trim().startsWith("{")) JSONObject(config) else JSONObject()
                val protocol = parsed.optString("protocol", if (config.startsWith("vless://")) "vless" else "vless")
                val mtu = parsed.optInt("mtu", 1500).coerceIn(1280, 1500)

                val assignedIp = parsed.optString("assigned_ip", "10.8.0.2")
                val subnet = parsed.optString("subnet", "10.8.0.0/24")
                val gateway = parsed.optString("gateway", "10.8.0.1")
                val dnsArray = parsed.optJSONArray("dns")
                val dnsServers = mutableListOf<String>()
                if (dnsArray != null) {
                    for (i in 0 until dnsArray.length()) {
                        dnsServers.add(dnsArray.optString(i))
                    }
                }
                if (dnsServers.isEmpty()) {
                    dnsServers.add("8.8.8.8")
                    dnsServers.add("1.1.1.1")
                }

                val builder = Builder()
                    .setSession("ByteAway VPN")
                    .setMtu(mtu)
                    .addAddress(assignedIp, subnet.substringAfter('/').toIntOrNull() ?: 24)
                    .addRoute("0.0.0.0", 0)

                dnsServers.forEach { builder.addDnsServer(it) }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    builder.setMetered(false)
                }

                applyExclusions(builder)

                tunInterface = builder.establish()
                if (tunInterface == null) {
                    throw IllegalStateException("Failed to establish TUN interface")
                }

                val tunFd = tunInterface!!.fd.toLong()

                val singboxConfig = when (protocol.lowercase()) {
                    "ostp" -> {
                        startOstpProxy(parsed)
                        buildOstpSingboxConfig(assignedIp, subnet, mtu)
                    }
                    else -> {
                        val vlessLink = parsed.optString("vless_link", config)
                        val tier = parsed.optString("tier", "free")
                        val maxSpeed = parsed.optInt("max_speed_mbps", 10)
                        buildVlessSingboxConfig(vlessLink, tier, maxSpeed, assignedIp, subnet, mtu, gateway, dnsServers)
                    }
                }

                Boxwrapper.startSingBox(singboxConfig, tunFd)

                isRunning.set(true)
                isConnecting.set(false)
                startAtMillis = System.currentTimeMillis()
                startForeground(NOTIFICATION_ID, buildNotification("VPN подключен"))
                broadcastState(error = "")
            } catch (t: Throwable) {
                isRunning.set(false)
                isConnecting.set(false)
                stopVpnInternal(silent = true)
                broadcastState(error = t.message ?: "VPN start failed")
            }
        }
    }

    private fun startOstpProxy(parsed: JSONObject) {
        val host = parsed.optString("ostp_host", "byteaway.xyz")
        val port = parsed.optInt("ostp_port", 8443)
        val token = parsed.optString("token", "")
        val deviceId = parsed.optString("device_id", "")
        val country = parsed.optString("country", "RU")
        val connType = parsed.optString("conn_type", "wifi")
        val hwid = parsed.optString("hwid", deviceId)
        val localPort = parsed.optInt("ostp_local_port", 1088)

        val proxy = OstpProxy(
            vpnService = this,
            serverHost = host,
            serverPort = port,
            token = token,
            country = country,
            connType = connType,
            hwid = hwid,
            localPort = localPort,
        )
        proxy.start()
        ostpProxy = proxy
    }

    private fun stopVpn() {
        scope.launch {
            stopVpnInternal(silent = false)
        }
    }

    private fun stopVpnInternal(silent: Boolean) {
        try {
            ostpProxy?.stop()
            ostpProxy = null
        } catch (_: Throwable) {
        }

        try {
            Boxwrapper.stopSingBox()
        } catch (_: Throwable) {
        }

        try {
            tunInterface?.close()
            tunInterface = null
        } catch (_: Throwable) {
        }

        isRunning.set(false)
        isConnecting.set(false)
        if (!silent) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        broadcastState(error = "")
    }

    private fun updateExcluded(pkg: String, add: Boolean) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = prefs.getStringSet(PREFS_EXCLUDED, emptySet())?.toMutableSet() ?: mutableSetOf()
        if (add) {
            current.add(pkg)
        } else {
            current.remove(pkg)
        }
        prefs.edit().putStringSet(PREFS_EXCLUDED, current).apply()

        if (isRunning.get() && currentConfigJson != null) {
            startVpn(currentConfigJson!!)
        }
    }

    private fun applyExclusions(builder: Builder) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val excluded = prefs.getStringSet(PREFS_EXCLUDED, emptySet()) ?: emptySet()
        excluded.forEach { pkg ->
            try {
                builder.addDisallowedApplication(pkg)
            } catch (_: Throwable) {
            }
        }
    }

    private fun broadcastState(error: String) {
        val uptime = if (isRunning.get() && startAtMillis > 0) {
            (System.currentTimeMillis() - startAtMillis) / 1000
        } else 0L

        ServiceBridge.sendEvent(
            mapOf(
                "vpnConnected" to isRunning.get(),
                "vpnConnecting" to isConnecting.get(),
                "bytesIn" to 0L,
                "bytesOut" to 0L,
                "uptime" to uptime,
                "errorMessage" to error,
            )
        )
    }

    private fun buildVlessSingboxConfig(
        vlessLink: String,
        tier: String,
        maxSpeedMbps: Int,
        assignedIp: String,
        subnet: String,
        mtu: Int,
        gateway: String,
        dnsServers: List<String>,
    ): String {
        val uri = vlessLink.removePrefix("vless://")
        val atIndex = uri.indexOf('@')
        val queryIndex = uri.indexOf('?')
        val uuid = if (atIndex != -1) uri.substring(0, atIndex) else ""
        val hostAndPort = if (atIndex != -1) {
            if (queryIndex != -1) uri.substring(atIndex + 1, queryIndex) else uri.substring(atIndex + 1)
        } else "byteaway.xyz:443"
        val hostParts = hostAndPort.split(":")
        val host = hostParts[0]
        val port = hostParts.getOrNull(1)?.toIntOrNull() ?: 443

        val params = mutableMapOf<String, String>()
        if (queryIndex != -1) {
            val query = uri.substring(queryIndex + 1).split("#")[0]
            query.split("&").forEach { part ->
                val pair = part.split("=")
                if (pair.size == 2) params[pair[0]] = pair[1]
            }
        }
        val sni = params["sni"] ?: "google.com"
        val pubKey = params["pbk"] ?: ""
        val shortId = params["sid"] ?: ""

        val isFree = tier.lowercase() == "free" || tier.isBlank()
        val speedLimitKbps = if (isFree && maxSpeedMbps > 0) maxSpeedMbps * 1000 else 0
        val bandwidth = if (speedLimitKbps > 0) {
            """,
            "bandwidth": {
                "enabled": true,
                "up": "${speedLimitKbps} kbps",
                "down": "${speedLimitKbps} kbps"
            }"""
        } else ""

        val dnsJson = dnsServers.joinToString(separator = ",") { "{\"type\": \"udp\", \"server\": \"$it\"}" }

        return """
        {
          "log": { "level": "info" },
          "dns": {
            "servers": [ $dnsJson ],
            "strategy": "ipv4_only"
          },
          "inbounds": [
            {
              "type": "tun",
              "tag": "tun-in",
              "interface_name": "tun0",
              "inet4_address": "${assignedIp}/${subnet.substringAfter('/').toIntOrNull() ?: 24}",
              "mtu": $mtu,
              "auto_route": true,
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
              }$bandwidth
            },
            { "type": "direct", "tag": "direct-out" }
          ],
          "route": {
            "final": "vless-out",
            "rules": [ { "protocol": "dns", "action": "hijack-dns" } ]
          }
        }
        """.trimIndent()
    }

    private fun buildOstpSingboxConfig(
        assignedIp: String,
        subnet: String,
        mtu: Int,
    ): String {
        return """
        {
          "log": { "level": "info" },
          "inbounds": [
            {
              "type": "tun",
              "tag": "tun-in",
              "interface_name": "tun0",
              "inet4_address": "${assignedIp}/${subnet.substringAfter('/').toIntOrNull() ?: 24}",
              "mtu": $mtu,
              "auto_route": true,
              "strict_route": false,
              "stack": "system"
            }
          ],
          "outbounds": [
            {
              "type": "socks",
              "tag": "ostp-out",
              "server": "127.0.0.1",
              "server_port": 1088
            },
            { "type": "direct", "tag": "direct-out" }
          ],
          "route": {
            "final": "ostp-out"
          }
        }
        """.trimIndent()
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ByteAway")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(pending)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ByteAway VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "VPN connection status"
            channel.setShowBadge(false)
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopVpnInternal(silent = true)
        scope.cancel()
        super.onDestroy()
    }
}
