package com.ospab.byteaway.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.io.InputStream
import java.io.IOException
import java.nio.channels.AsynchronousCloseException
import java.nio.channels.ClosedChannelException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.*

class ByteAwayForegroundService : VpnService() {

    companion object {
        const val CHANNEL_ID = "byteaway_service"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START_VPN = "com.byteaway.START_VPN"
        const val ACTION_STOP_VPN = "com.byteaway.STOP_VPN"
        const val ACTION_START_NODE = "com.byteaway.START_NODE"
        const val ACTION_STOP_NODE = "com.byteaway.STOP_NODE"
        const val ACTION_TOGGLE_VPN = "com.byteaway.TOGGLE_VPN"
        const val ACTION_TOGGLE_NODE = "com.byteaway.TOGGLE_NODE"

        const val EXTRA_VPN_CONFIG = "com.byteaway.EXTRA_VPN_CONFIG"
        const val EXTRA_VPN_MTU = "com.byteaway.EXTRA_VPN_MTU"
        const val DEFAULT_NODE_QUIC_ENDPOINT = "quic://byteaway.xyz:3443"
        const val DEFAULT_NODE_WS_ENDPOINT = "wss://byteaway.xyz/ws"
        const val NODE_RELAY_HY2_HOST = "byteaway.xyz"
        const val NODE_RELAY_HY2_PORT = 9443
        const val NODE_RELAY_HY2_PASSWORD = "G8k3vQ9pLm2sT7xY4nR6cD1hW5jZ0aFp"

        // Wire protocol constants
        const val CMD_CONNECT: Byte = 0x01
        const val CMD_DATA: Byte = 0x02
        const val CMD_CLOSE: Byte = 0x03

        // State shared across service and system UI
        val isVpnRunning = AtomicBoolean(false)
        val isVpnConnecting = AtomicBoolean(false)
        val isNodeActive = AtomicBoolean(false)
        val isNodeConnecting = AtomicBoolean(false)
        var lastConfig: String = "{}"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var nodeReadJob: Job? = null

    // State
    private val totalBytesShared = AtomicLong(0)
    private val totalBytesIn = AtomicLong(0)
    private val totalBytesOut = AtomicLong(0)
    private val quicFramesIn = AtomicLong(0)
    private val quicFramesOut = AtomicLong(0)
    private val quicBytesIn = AtomicLong(0)
    private val quicBytesOut = AtomicLong(0)
    private var lastBytesShared: Long = 0
    // Tracks combined bytes (node shared + vpn forwarder) for speed calc
    private var lastBytesCombined: Long = 0
    private var currentSpeedMbps: Double = 0.0
    private var nodeStartTime: Long = 0
    private var nodeErrorMessage: String? = null
    private var reconnectAttempts: Int = 0
    private var reconnectJob: Job? = null
    private val reconnectScheduled = AtomicBoolean(false)
    @Volatile private var manualNodeStop: Boolean = false
    @Volatile private var nodeOwnsBox: Boolean = false
    @Volatile private var activeNodeTransport: String = "quic"
    @Volatile private var forceNodeSocksProxy: Boolean = false
    private var statsJob: Job? = null
    private var lastBroadcastState: Map<String, Any>? = null

    // Native VPN TUN interface
    private var vpnInterface: ParcelFileDescriptor? = null

    // TUN packet forwarding engine
    private var tunForwarder: TunForwarder? = null

    // Local Xray SOCKS5 proxy endpoint
    private val socksHost = "127.0.0.1"
    private val socksPort = 10808
    private val socksProxyAddress = "$socksHost:$socksPort"

    // Active tunnel sessions: session_id -> SocketChannel
    private val sessions = ConcurrentHashMap<UUID, SocketChannel>()
    // Sessions currently connecting: session_id -> boolean
    private val connectingSessions = ConcurrentHashMap.newKeySet<UUID>()
    // Sessions closed by peer CMD_CLOSE; avoids false read-failure logs.
    private val peerClosedSessions = ConcurrentHashMap.newKeySet<UUID>()
    // Data waiting for connection: session_id -> list of payload segments
    private val pendingData = ConcurrentHashMap<UUID, MutableList<ByteArray>>()
    // Per-session data channels for ordered, non-leaking writes
    private val sessionChannels = ConcurrentHashMap<UUID, kotlinx.coroutines.channels.Channel<ByteArray>>()
    private val maxPendingFramesPerSession = 256



    // Wake lock to prevent CPU sleep during sharing
    private var wakeLock: PowerManager.WakeLock? = null

    // In-app logger (via ServiceBridge event stream). No file logging.
    private fun appendLog(message: String) {
        ServiceBridge.emitNativeLog(message)
    }

    private fun appendExternalLog(message: String) {
        ServiceBridge.emitNativeLog(message)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("ByteAway сервис запущен"))
        registerUncaughtExceptionHandler()
        startStatsJob()
        broadcastState()
    }

    private fun startStatsJob() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isActive) {
                // Combine node-shared counters with VPN forwarder counters (if running)
                val vpnBytes = tunForwarder?.let { it.totalBytesIn.get() + it.totalBytesOut.get() } ?: 0L
                val current = totalBytesShared.get() + vpnBytes
                val diff = current - lastBytesCombined
                lastBytesCombined = current
                // diff is bytes/sec. (diff * 8 / 1_000_000) = Mbps
                currentSpeedMbps = (diff * 8.0) / 1_000_000.0


                if (isNodeActive.get() || isVpnRunning.get() || isNodeConnecting.get() || isVpnConnecting.get()) {
                    if (isNodeActive.get() && (System.currentTimeMillis() / 1000L) % 15L == 0L) {
                        appendExternalLog(
                            "QUIC stats in=${quicBytesIn.get()}B/${quicFramesIn.get()}f out=${quicBytesOut.get()}B/${quicFramesOut.get()}f sessions=${sessions.size}"
                        )
                    }
                    broadcastState()
                }
                delay(1000)
            }
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
            android.util.Log.i("ByteAway", "onStartCommand action=${intent?.action} flags=$flags")

            if (intent == null) {
                // Service restarted by system (START_STICKY)
                android.util.Log.w("ByteAway", "Service restarted without intent, checking if we should restore VPN/Node")
                restoreFromSticky()
                return START_STICKY
            }

            when (intent.action) {
            ACTION_START_VPN -> {
                val cfg = intent.getStringExtra(EXTRA_VPN_CONFIG) ?: "{}"
                val mtuHint = if (intent.hasExtra(EXTRA_VPN_MTU)) intent.getIntExtra(EXTRA_VPN_MTU, 1280) else null
                android.util.Log.i("ByteAway", "action START_VPN cfgLen=${cfg.length}")
                startVpn(cfg, mtuHint)
            }
            ACTION_STOP_VPN -> {
                android.util.Log.i("ByteAway", "action STOP_VPN")
                stopVpn()
            }
            ACTION_TOGGLE_VPN -> {
                if (isVpnRunning.get()) stopVpn() else {
                    val cfg = intent.getStringExtra(EXTRA_VPN_CONFIG) ?: "{}"
                    val mtuHint = if (intent.hasExtra(EXTRA_VPN_MTU)) intent.getIntExtra(EXTRA_VPN_MTU, 1280) else null
                    startVpn(cfg, mtuHint)
                }
            }
            ACTION_TOGGLE_NODE -> {
                if (isNodeActive.get()) stopNode() else {
                    // Can't start node from notification without credentials
                    android.util.Log.w("ByteAway", "Cannot start node from notification")
                }
            }
            ACTION_START_NODE -> {
                val token = intent.getStringExtra("token") ?: ""
                val deviceId = intent.getStringExtra("deviceId") ?: ""
                val country = intent.getStringExtra("country") ?: "auto"
                val transportMode = intent.getStringExtra("transportMode") ?: "quic"
                val connType = intent.getStringExtra("connType") ?: "wifi"
                val speedMbps = intent.getIntExtra("speedMbps", 50)
                val mtu = intent.getIntExtra("mtu", 1280)
                val masterWsUrl = intent.getStringExtra("masterWsUrl")
                val coreConfigJson = intent.getStringExtra("coreConfigJson")
                scope.launch {
                    startNode(token, deviceId, country, transportMode, connType, speedMbps, mtu, masterWsUrl, coreConfigJson)
                }
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

    private fun restoreFromSticky() {
        val pref = getSharedPreferences("vpn_prefs", MODE_PRIVATE)
        val wasVpnRunning = pref.getBoolean("was_vpn_running", false)
        val lastConfig = pref.getString("last_vpn_config", null)

        if (wasVpnRunning && lastConfig != null) {
            android.util.Log.i("ByteAway", "Restoring VPN after sticky restart")
            appendExternalLog("System restarted process, restoring VPN connection...")
            startVpn(lastConfig)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onRevoke() {
        android.util.Log.w("ByteAway", "VPN permissions revoked (another VPN started). Stopping...")
        appendExternalLog("VPN connection lost to another application.")
        stopVpn()
        stopNode()
        super.onRevoke()
    }
    // ──────────────────────────────────────────────────────
    // VPN Management (Native Android VpnService)
    // ──────────────────────────────────────────────────────

    private fun stopVpn() {
        if (!isVpnRunning.get()) {
            isVpnConnecting.set(false)
            broadcastState()
            return
        }
        
        getSharedPreferences("vpn_prefs", MODE_PRIVATE).edit()
            .putBoolean("was_vpn_running", false)
            .apply()

        isVpnRunning.set(false)
        
        scope.launch {
            try {
                // Stop local sing-box core
                try {
                    boxwrapper.Boxwrapper.stopBox()
                } catch (e: Exception) {
                    android.util.Log.e("ByteAway", "Failed to stop sing-box: ${e.message}")
                }

                tunForwarder?.stop()
                tunForwarder = null

                vpnInterface?.close()
                vpnInterface = null

                isVpnRunning.set(false)
                isVpnConnecting.set(false)
                android.util.Log.i("ByteAway", "VPN stopped")
                appendExternalLog("VPN stopped")

                if (!isNodeActive.get()) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    updateNotification()
                }
                broadcastState()
            } catch (e: Exception) {
                android.util.Log.e("ByteAway", "Failed to stop VPN", e)
                isVpnRunning.set(false)
                isVpnConnecting.set(false)
                appendLog("stopVpn error: ${e::class.java.simpleName}: ${e.message ?: ""}")
                broadcastState()
            }
        }
    }

    private fun startVpn(config: String, mtuHint: Int? = null) {
        if (isVpnRunning.get() || isVpnConnecting.get()) return
        isVpnConnecting.set(true)
        broadcastState()
        lastConfig = config

        val vpnMtu = (mtuHint ?: 1280).coerceIn(1280, 1480)
        
        // Save state for sticky recovery
        getSharedPreferences("vpn_prefs", MODE_PRIVATE).edit()
            .putBoolean("was_vpn_running", true)
            .putString("last_vpn_config", config)
            .apply()

        scope.launch {
            try {
                acquireWakeLock()

                // If node mode started a standalone sing-box process, recycle it before VPN mode.
                if (nodeOwnsBox) {
                    try {
                        boxwrapper.Boxwrapper.stopBox()
                    } catch (_: Exception) {}
                    nodeOwnsBox = false
                }
                
                // Initialize sing-box Core BEFORE establishing the tunnel to avoid deadlock
                try {
                    android.util.Log.i("ByteAway", "Starting sing-box core...")
                    boxwrapper.Boxwrapper.startBox(config)
                    android.util.Log.i("ByteAway", "sing-box core started successfully")
                } catch (e: Exception) {
                    val msg = "Failed to start sing-box core: ${e.message}"
                    android.util.Log.e("ByteAway", msg, e)
                    appendExternalLog(msg)
                    isVpnRunning.set(false)
                    isVpnConnecting.set(false)
                    nodeErrorMessage = msg
                    broadcastState()
                    return@launch
                }

                val builder = Builder()
                    .setSession("ByteAway VPN")
                    .addAddress("10.0.0.2", 32)
                    .addRoute("0.0.0.0", 0)
                    .addRoute("::", 0) // Capture IPv6 to prevent leaks or bypasses
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("1.0.0.1")
                    .addDnsServer("8.8.8.8")
                    .addDnsServer("9.9.9.9")
                    .addDnsServer("77.88.8.8")
                    .setMtu(vpnMtu)
                    .setBlocking(true)

                try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}

                val iface = builder.establish()

                if (iface == null) {
                    val msg = "VPN permission not granted"
                    android.util.Log.e("ByteAway", msg)
                    appendExternalLog(msg)
                    isVpnConnecting.set(false)
                    nodeErrorMessage = msg
                    broadcastState()
                    return@launch
                }

                vpnInterface = iface
                
                isVpnRunning.set(true)
                isVpnConnecting.set(false)
                android.util.Log.i("ByteAway", "VPN TUN established, starting TunForwarder")
                appendExternalLog("VPN TUN established, forwarding via SOCKS5 $socksHost:$socksPort")

                // Start packet forwarding engine
                val forwarder = TunForwarder(this@ByteAwayForegroundService, iface, socksHost, socksPort, vpnMtu)
                tunForwarder = forwarder
                forwarder.start()

                updateNotification()
                broadcastState()
            } catch (e: Exception) {
                val msg = "Failed to establish VPN: ${e::class.java.simpleName}: ${e.message}"
                android.util.Log.e("ByteAway", msg, e)
                appendExternalLog(msg)
                isVpnRunning.set(false)
                isVpnConnecting.set(false)
                nodeErrorMessage = msg
                updateNotification()
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
        transportMode: String,
        connType: String,
        speedMbps: Int,
        mtu: Int,
        masterWsUrl: String? = null,
        coreConfigJson: String? = null,
    ) {
        try {
            if (isNodeActive.get() || isNodeConnecting.get()) {
            android.util.Log.d("ByteAway", "Node already active or connecting, skipping startNode")
            return
        }

            manualNodeStop = false
            reconnectScheduled.set(false)
            reconnectJob?.cancel()

            val normalizedTransport = when (transportMode.lowercase(Locale.US)) {
                "quic", "ws", "hy2" -> transportMode.lowercase(Locale.US)
                else -> "quic"
            }

            android.util.Log.i("ByteAway", "startNode invoked: deviceId=$deviceId country=$country transport=$normalizedTransport connType=$connType speed=$speedMbps")

            // Reset path policy on each start to avoid stale mode across restarts.
            forceNodeSocksProxy = false

            when (normalizedTransport) {
                "ws" -> {
                    forceNodeSocksProxy = true
                    val proxyReady = ensureNodeVpnTunnelReady(coreConfigJson)
                    if (!proxyReady) {
                        nodeErrorMessage = "WS mode requires local proxy config"
                        appendExternalLog("WS init failed: local SOCKS proxy is not ready")
                        isNodeActive.set(false)
                        isNodeConnecting.set(false)
                        broadcastState()
                        return
                    }
                    appendExternalLog("Node transport WS selected (forced local SOCKS)")
                }
                "hy2" -> {
                    forceNodeSocksProxy = true
                    val proxyReady = ensureNodeBoxReady(coreConfigJson)
                    if (!proxyReady) {
                        nodeErrorMessage = "HY2 mode requires local proxy config"
                        appendExternalLog("HY2 init failed: local SOCKS proxy is not ready")
                        isNodeActive.set(false)
                        isNodeConnecting.set(false)
                        broadcastState()
                        return
                    }
                    appendExternalLog("Node transport HY2 selected (forced local SOCKS)")
                }
                else -> {
                    // QUIC node relay is stable with direct outbound sockets and should
                    // not depend on local SOCKS anti-block chain by default.
                    // This avoids premature TLS EOF caused by local proxy path issues.
                    forceNodeSocksProxy = false
                    appendExternalLog("Node transport QUIC selected (direct connect mode)")
                }
            }

        isNodeConnecting.set(true)
        broadcastState()
        acquireWakeLock()

        val quicEndpoint = toQuicEndpoint(masterWsUrl)

        val normalizedConnType = when (connType.lowercase(Locale.US)) {
            "wifi", "mobile" -> connType.lowercase(Locale.US)
            "cellular" -> "mobile"
            else -> "wifi"
        }

            when (normalizedTransport) {
                "quic" -> connectNodeQuic(
                    quicEndpoint = quicEndpoint,
                    token = token,
                    deviceId = deviceId,
                    country = country,
                    transportMode = normalizedTransport,
                    connType = normalizedConnType,
                    speedMbps = speedMbps,
                    mtu = mtu,
                    masterWsUrl = masterWsUrl,
                    coreConfigJson = coreConfigJson,
                )
                "ws" -> connectNodeWs(
                    wsEndpoint = toWsEndpoint(masterWsUrl),
                    socksProxy = socksProxyAddress,
                    token = token,
                    deviceId = deviceId,
                    country = country,
                    transportMode = normalizedTransport,
                    connType = normalizedConnType,
                    speedMbps = speedMbps,
                    mtu = mtu,
                    masterWsUrl = masterWsUrl,
                    coreConfigJson = coreConfigJson,
                )
                "hy2" -> connectNodeWs(
                    wsEndpoint = toWsEndpoint(masterWsUrl),
                    socksProxy = socksProxyAddress,
                    token = token,
                    deviceId = deviceId,
                    country = country,
                    transportMode = normalizedTransport,
                    connType = normalizedConnType,
                    speedMbps = speedMbps,
                    mtu = mtu,
                    masterWsUrl = masterWsUrl,
                    coreConfigJson = coreConfigJson,
                )
                else -> connectNodeQuic(
                    quicEndpoint = quicEndpoint,
                    token = token,
                    deviceId = deviceId,
                    country = country,
                    transportMode = "quic",
                    connType = normalizedConnType,
                    speedMbps = speedMbps,
                    mtu = mtu,
                    masterWsUrl = masterWsUrl,
                    coreConfigJson = coreConfigJson,
                )
            }
        } catch (t: Throwable) {
            val trace = android.util.Log.getStackTraceString(t).lineSequence().take(20).joinToString(" | ")
            val msg = "startNode error: ${t::class.java.simpleName}: ${t.message ?: ""} [$trace]"
            android.util.Log.e("ByteAway", msg, t)
            appendLog(msg)
            isNodeConnecting.set(false)
            onNodeDisconnected()
        }
    }

    private fun connectNodeQuic(
        quicEndpoint: String,
        token: String,
        deviceId: String,
        country: String,
        transportMode: String,
        connType: String,
        speedMbps: Int,
        mtu: Int,
        masterWsUrl: String?,
        coreConfigJson: String?,
    ) {
        try {
            android.util.Log.i("ByteAway", "Connecting node QUIC transport: $quicEndpoint")
            appendExternalLog("QUIC connect start endpoint=$quicEndpoint country=$country conn=$connType speed=${speedMbps}Mbps")
            boxwrapper.Boxwrapper.startNodeQuic(
                quicEndpoint,
                deviceId,
                token,
                country,
                connType,
                speedMbps.toLong(),
                mtu.toLong(),
            )
            activeNodeTransport = "quic"

            isNodeActive.set(true)
            isNodeConnecting.set(false)
            nodeStartTime = System.currentTimeMillis()
            nodeErrorMessage = null
            reconnectAttempts = 0
            reconnectScheduled.set(false)
            reconnectJob?.cancel()
            broadcastState()
            android.util.Log.i("ByteAway", "QUIC connected successfully")
            appendExternalLog("QUIC connected endpoint=$quicEndpoint")

            nodeReadJob?.cancel()
            nodeReadJob = scope.launch {
                try {
                    while (isActive && isNodeActive.get() && !manualNodeStop) {
                        val frame = withContext(Dispatchers.IO) {
                            boxwrapper.Boxwrapper.readNodeFrame()
                        }
                        if (frame == null || frame.isEmpty()) {
                            throw IOException("QUIC stream closed")
                        }
                        quicFramesIn.incrementAndGet()
                        quicBytesIn.addAndGet(frame.size.toLong())
                        handleIncomingFrame(frame)
                    }
                } catch (e: Exception) {
                    if (!manualNodeStop) {
                        nodeErrorMessage = e.message ?: "QUIC failure"
                        android.util.Log.e("ByteAway", "QUIC failure: ${e.message}", e)
                        appendExternalLog("QUIC reader failed: ${e.message ?: "unknown"}")
                        onNodeDisconnected()
                        scheduleReconnect(token, deviceId, country, transportMode, connType, speedMbps, mtu, masterWsUrl, coreConfigJson)
                    }
                }
            }
        } catch (t: Throwable) {
            nodeErrorMessage = t.message ?: "QUIC connect failure"
            android.util.Log.e("ByteAway", "QUIC connect failed: ${t.message}", t)
            appendExternalLog("QUIC connect failed: ${t.message ?: "unknown"}")
            onNodeDisconnected()
            scheduleReconnect(token, deviceId, country, transportMode, connType, speedMbps, mtu, masterWsUrl, coreConfigJson)
        }
    }

    private fun connectNodeWs(
        wsEndpoint: String,
        socksProxy: String?,
        token: String,
        deviceId: String,
        country: String,
        transportMode: String,
        connType: String,
        speedMbps: Int,
        mtu: Int,
        masterWsUrl: String?,
        coreConfigJson: String?,
    ) {
        try {
            android.util.Log.i("ByteAway", "Connecting node WS transport: $wsEndpoint proxy=${socksProxy ?: "none"}")
            val transportLabel = if (transportMode == "hy2") "HY2-over-SOCKS/WS" else "WS"
            appendExternalLog("$transportLabel connect start endpoint=$wsEndpoint proxy=${socksProxy ?: "none"} country=$country conn=$connType speed=${speedMbps}Mbps")

            boxwrapper.Boxwrapper.startNodeWs(
                wsEndpoint,
                deviceId,
                token,
                country,
                connType,
                speedMbps.toLong(),
                socksProxy ?: "",
            )

            activeNodeTransport = transportMode
            isNodeActive.set(true)
            isNodeConnecting.set(false)
            nodeStartTime = System.currentTimeMillis()
            nodeErrorMessage = null
            reconnectAttempts = 0
            reconnectScheduled.set(false)
            reconnectJob?.cancel()
            broadcastState()
            appendExternalLog("$transportLabel connected endpoint=$wsEndpoint")

            nodeReadJob?.cancel()
            nodeReadJob = scope.launch {
                try {
                    while (isActive && isNodeActive.get() && !manualNodeStop) {
                        val frame = withContext(Dispatchers.IO) {
                            boxwrapper.Boxwrapper.readNodeFrame()
                        }
                        if (frame == null || frame.isEmpty()) {
                            throw IOException("WS stream closed")
                        }
                        quicFramesIn.incrementAndGet()
                        quicBytesIn.addAndGet(frame.size.toLong())
                        handleIncomingFrame(frame)
                    }
                } catch (e: Exception) {
                    if (!manualNodeStop) {
                        nodeErrorMessage = e.message ?: "WS failure"
                        android.util.Log.e("ByteAway", "WS failure: ${e.message}", e)
                        appendExternalLog("WS reader failed: ${e.message ?: "unknown"}")
                        onNodeDisconnected()
                        scheduleReconnect(token, deviceId, country, transportMode, connType, speedMbps, mtu, masterWsUrl, coreConfigJson)
                    }
                }
            }
        } catch (t: Throwable) {
            nodeErrorMessage = t.message ?: "WS connect failure"
            android.util.Log.e("ByteAway", "WS connect failed: ${t.message}", t)
            appendExternalLog("WS connect failed: ${t.message ?: "unknown"}")
            onNodeDisconnected()
            scheduleReconnect(token, deviceId, country, transportMode, connType, speedMbps, mtu, masterWsUrl, coreConfigJson)
        }
    }

    private fun toQuicEndpoint(masterWsUrl: String?): String {
        val raw = masterWsUrl?.trim().orEmpty()
        if (raw.isEmpty()) return DEFAULT_NODE_QUIC_ENDPOINT

        return try {
            val uri = java.net.URI(raw)
            val host = uri.host ?: return DEFAULT_NODE_QUIC_ENDPOINT
            val port = if (uri.port > 0) uri.port else 3443
            "quic://$host:$port"
        } catch (_: Exception) {
            DEFAULT_NODE_QUIC_ENDPOINT
        }
    }

    private fun toWsEndpoint(masterWsUrl: String?): String {
        val raw = masterWsUrl?.trim().orEmpty()
        if (raw.isEmpty()) return DEFAULT_NODE_WS_ENDPOINT

        return try {
            val uri = java.net.URI(raw)
            val host = uri.host ?: return DEFAULT_NODE_WS_ENDPOINT
            val path = if (uri.path.isNullOrBlank()) "/ws" else uri.path
            val portPart = if (uri.port > 0) ":${uri.port}" else ""
            val scheme = when (uri.scheme?.lowercase(Locale.US)) {
                "ws", "wss" -> uri.scheme.lowercase(Locale.US)
                "http" -> "ws"
                else -> "wss"
            }
            "$scheme://$host$portPart$path"
        } catch (_: Exception) {
            DEFAULT_NODE_WS_ENDPOINT
        }
    }

    private fun stopNode() {
        try {
            manualNodeStop = true
            reconnectJob?.cancel()
            reconnectScheduled.set(false)
            isNodeActive.set(false)
            nodeReadJob?.cancel()
            nodeReadJob = null
            boxwrapper.Boxwrapper.stopNodeTransport()
            appendExternalLog("Node transport stopped by request: $activeNodeTransport")

        if (!isVpnRunning.get() && nodeOwnsBox) {
            try {
                boxwrapper.Boxwrapper.stopBox()
            } catch (_: Exception) {}
            nodeOwnsBox = false
        }

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
        reconnectScheduled.set(false)
        nodeReadJob?.cancel()
        nodeReadJob = null
        boxwrapper.Boxwrapper.stopNodeTransport()
        appendExternalLog("Node transport disconnected ($activeNodeTransport): ${nodeErrorMessage ?: "no reason"}")
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
        transportMode: String,
        connType: String,
        speedMbps: Int,
        mtu: Int,
        masterWsUrl: String?,
        coreConfigJson: String?,
    ) {
        if (manualNodeStop) return
        if (!reconnectScheduled.compareAndSet(false, true)) return

        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            if (manualNodeStop || isNodeActive.get() || isNodeConnecting.get()) {
                reconnectScheduled.set(false)
                return@launch
            }

            reconnectAttempts = (reconnectAttempts + 1).coerceAtMost(12)
            val delayMs = (5000L * (1 shl (reconnectAttempts - 1))).coerceAtMost(60_000L)

            android.util.Log.i("ByteAway", "Scheduling node reconnect in ${delayMs / 1000} sec (attempt $reconnectAttempts)")
            delay(delayMs)

            if (!manualNodeStop && !isNodeActive.get() && !isNodeConnecting.get()) {
                android.util.Log.i("ByteAway", "Reconnecting node attempt $reconnectAttempts")
                startNode(token, deviceId, country, transportMode, connType, speedMbps, mtu, masterWsUrl, coreConfigJson)
            }
            reconnectScheduled.set(false)
        }
    }

    // ──────────────────────────────────────────────────────
    // Wire Protocol Handler
    // ──────────────────────────────────────────────────────

    /**
        * Decode incoming QUIC binary frame:
     * [1 byte: cmd][16 bytes: session_uuid][N bytes: payload]
     */
    private suspend fun handleIncomingFrame(data: ByteArray) {
        if (data.size < 17) return

        val cmd = data[0]
        val sessionIdBytes = data.sliceArray(1..16)
        val sessionId = bytesToUUID(sessionIdBytes)
        val payload = data.sliceArray(17 until data.size)

        when (cmd) {
            CMD_CONNECT -> {
                appendExternalLog("NODE <= CONNECT sid=$sessionId target=${String(payload)}")
                connectingSessions.add(sessionId)
                handleConnect(sessionId, String(payload))
            }
            CMD_DATA -> handleData(sessionId, payload)
            CMD_CLOSE -> {
                appendExternalLog("NODE <= CLOSE sid=$sessionId")
                handleClose(sessionId)
            }
        }
    }

    /**
     * CMD_CONNECT: Open TCP connection to target address.
     * Target format: "host:port"
     */
    private fun handleConnect(sessionId: UUID, targetAddr: String) {
        scope.launch {
            try {
                val separator = targetAddr.lastIndexOf(':')
                if (separator <= 0 || separator >= targetAddr.length - 1) return@launch

                var host = targetAddr.substring(0, separator)
                if (host.startsWith("[") && host.endsWith("]") && host.length > 2) {
                    host = host.substring(1, host.length - 1)
                }
                val port = targetAddr.substring(separator + 1).toIntOrNull() ?: return@launch

                val modeLabel = if (forceNodeSocksProxy) "socks" else "direct"
                appendExternalLog("Node CONNECT request: $host:$port (session=$sessionId mode=$modeLabel)")

                val channel = tryConnectTarget(host, port)

                sessions[sessionId] = channel
                connectingSessions.remove(sessionId)
                appendExternalLog("Node CONNECT established: $host:$port (session=$sessionId mode=$modeLabel)")

                // Create a dedicated worker for this session's writers
                val dataChannel = kotlinx.coroutines.channels.Channel<ByteArray>(1024)
                sessionChannels[sessionId] = dataChannel
                
                // Start consumer for this session's data
                launch {
                    processSessionOutgoingData(sessionId, channel, dataChannel)
                }

                // Flush pending data if any
                pendingData.remove(sessionId)?.forEach { bufferedPayload ->
                    dataChannel.send(bufferedPayload)
                }

                // Start reading from target and forwarding to QUIC transport
                launch {
                    readFromTarget(sessionId, channel)
                }
            } catch (e: Exception) {
                android.util.Log.w("ByteAway", "CONNECT failed for $targetAddr: ${e.message}")
                appendExternalLog("CONNECT failed for $targetAddr: ${e.message}")
                connectingSessions.remove(sessionId)
                pendingData.remove(sessionId)
                sessionChannels.remove(sessionId)?.close()
                // Send close back to master
                sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
            }
        }
    }

    private fun ensureNodeBoxReady(coreConfigJson: String?): Boolean {
        if (isVpnRunning.get()) {
            nodeOwnsBox = false
            return waitForLocalSocksReady(2500)
        }

        try {
            boxwrapper.Boxwrapper.stopBox()
        } catch (_: Exception) {}

        val hy2Cfg = buildNodeHy2RelayConfig()
        try {
            boxwrapper.Boxwrapper.startBox(hy2Cfg)
            nodeOwnsBox = true
            android.util.Log.i("ByteAway", "Node start: sing-box started with Hysteria2 relay config")
            return waitForLocalSocksReady(8000)
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "Node start: HY2 relay config failed, fallback to legacy config: ${e.message}")
            try {
                waitForLocalSocksReady(8000)
            } catch (_: Exception) {}
        }

        val cfg = coreConfigJson?.takeIf { it.isNotBlank() } ?: lastConfig.takeIf { it.isNotBlank() }
        if (cfg.isNullOrBlank()) {
            android.util.Log.w("ByteAway", "Node start: no box config available for anti-block fallback")
            return false
        }

        return try {
            boxwrapper.Boxwrapper.startBox(cfg)
            nodeOwnsBox = true
            android.util.Log.i("ByteAway", "Node start: sing-box started for node-only anti-block mode")
            waitForLocalSocksReady(8000)
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "Node start: sing-box start failed, will rely on direct path: ${e.message}")
            false
        }
    }

    private fun ensureNodeVpnTunnelReady(coreConfigJson: String?): Boolean {
        if (isVpnRunning.get()) {
            nodeOwnsBox = false
            return waitForLocalSocksReady(2500)
        }

        val cfg = coreConfigJson?.takeIf { it.isNotBlank() } ?: lastConfig.takeIf { it.isNotBlank() }
        if (cfg.isNullOrBlank()) {
            android.util.Log.w("ByteAway", "Node start: no config available for WS-over-VPN tunnel")
            return false
        }

        try {
            boxwrapper.Boxwrapper.stopBox()
        } catch (_: Exception) {}

        return try {
            boxwrapper.Boxwrapper.startBox(cfg)
            nodeOwnsBox = true
            android.util.Log.i("ByteAway", "Node start: sing-box started for WS-over-VPN mode")
            waitForLocalSocksReady(8000)
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "Node start: failed to start sing-box for WS-over-VPN mode: ${e.message}")
            false
        }
    }

    private fun waitForLocalSocksReady(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (probeLocalSocks()) {
                appendExternalLog("Local SOCKS proxy ready at $socksHost:$socksPort")
                return true
            }
            Thread.sleep(200)
        }
        appendExternalLog("Local SOCKS proxy is not responding at $socksHost:$socksPort")
        return false
    }

    private fun probeLocalSocks(): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(socksHost, socksPort), 500)
                socket.soTimeout = 500
                val output = socket.getOutputStream()
                val input = socket.getInputStream()

                output.write(byteArrayOf(0x05, 0x01, 0x00))
                output.flush()

                val greetingResp = ByteArray(2)
                if (!readFully(input, greetingResp)) return false
                greetingResp[0] == 0x05.toByte() && greetingResp[1] == 0x00.toByte()
            }
        } catch (_: Exception) {
            false
        }
    }

        private fun buildNodeHy2RelayConfig(): String {
                return """
                {
                    "log": {
                        "level": "warn"
                    },
                    "inbounds": [
                        {
                            "type": "socks",
                            "tag": "socks-in",
                            "listen": "127.0.0.1",
                            "listen_port": 10808,
                            "sniff": true
                        }
                    ],
                    "outbounds": [
                        {
                            "type": "hysteria2",
                            "tag": "hy2-out",
                            "server": "$NODE_RELAY_HY2_HOST",
                            "server_port": $NODE_RELAY_HY2_PORT,
                            "password": "$NODE_RELAY_HY2_PASSWORD",
                            "tls": {
                                "enabled": true,
                                "server_name": "$NODE_RELAY_HY2_HOST",
                                "alpn": ["h3"],
                                "insecure": false
                            }
                        },
                        {
                            "type": "direct",
                            "tag": "direct"
                        }
                    ],
                    "route": {
                        "rules": [
                            {
                                "inbound": ["socks-in"],
                                "outbound": "hy2-out"
                            }
                        ]
                    }
                }
                """.trimIndent()
        }

    private fun tryConnectTarget(host: String, port: Int): SocketChannel {
        val channel = SocketChannel.open()
        channel.configureBlocking(true)
        val socket = channel.socket()
        socket.tcpNoDelay = true
        socket.keepAlive = true
        socket.soTimeout = 0

        if (forceNodeSocksProxy) {
            val ok = connectViaLocalSocks(channel, host, port)
            if (ok) {
                return channel
            }

            // If local anti-block SOCKS failed for this destination, fallback to direct TCP
            // to keep QUIC tunnel sessions alive instead of closing immediately.
            appendExternalLog("SOCKS connect failed for $host:$port, fallback to direct TCP")
            try {
                channel.close()
            } catch (_: Exception) {}

            val directChannel = SocketChannel.open()
            directChannel.configureBlocking(true)
            val directSocket = directChannel.socket()
            directSocket.tcpNoDelay = true
            directSocket.keepAlive = true
            directSocket.soTimeout = 0
            directSocket.connect(InetSocketAddress(host, port), 12000)
            return directChannel
        }

        socket.connect(InetSocketAddress(host, port), 12000)
        return channel
    }

    private fun connectViaLocalSocks(channel: SocketChannel, host: String, port: Int): Boolean {
        try {
            val socket = channel.socket()
            socket.connect(InetSocketAddress(socksHost, socksPort), 5000)
            socket.soTimeout = 5000
            val output = socket.getOutputStream()
            val input = socket.getInputStream()

            // Greeting: no-auth SOCKS5
            output.write(byteArrayOf(0x05, 0x01, 0x00))
            output.flush()
            val greetingResp = ByteArray(2)
            if (!readFully(input, greetingResp) || greetingResp[0] != 0x05.toByte() || greetingResp[1] != 0x00.toByte()) {
                return false
            }

            val hostBytes = host.toByteArray()
            if (hostBytes.isEmpty() || hostBytes.size > 255) return false

            // CONNECT request with domain name ATYP to avoid local DNS resolution issues.
            val req = ByteArray(7 + hostBytes.size)
            req[0] = 0x05
            req[1] = 0x01
            req[2] = 0x00
            req[3] = 0x03
            req[4] = hostBytes.size.toByte()
            hostBytes.copyInto(req, 5)
            req[5 + hostBytes.size] = ((port shr 8) and 0xFF).toByte()
            req[6 + hostBytes.size] = (port and 0xFF).toByte()
            output.write(req)
            output.flush()

            val head = ByteArray(4)
            if (!readFully(input, head)) return false
            if (head[0] != 0x05.toByte() || head[1] != 0x00.toByte()) return false

            val atyp = head[3].toInt() and 0xFF
            val skip = when (atyp) {
                0x01 -> 4
                0x03 -> {
                    val n = input.read()
                    if (n < 0) return false
                    n
                }
                0x04 -> 16
                else -> return false
            }

            val rest = ByteArray(skip + 2)
            if (!readFully(input, rest)) return false

            socket.soTimeout = 0
            return true
        } catch (e: SocketTimeoutException) {
            android.util.Log.w("ByteAway", "SOCKS connect timeout for $host:$port")
            return false
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "SOCKS connect failed for $host:$port: ${e.message}")
            return false
        }
    }

    private fun readFully(input: InputStream, target: ByteArray): Boolean {
        var off = 0
        while (off < target.size) {
            val n = input.read(target, off, target.size - off)
            if (n <= 0) return false
            off += n
        }
        return true
    }

    /**
     * Sequential worker that pulls from a Channel and writes to SocketChannel.
     * This prevents coroutine explosion and memory overflow on large transfers.
     */
    private suspend fun processSessionOutgoingData(
        sessionId: UUID,
        socket: SocketChannel,
        channel: kotlinx.coroutines.channels.Channel<ByteArray>
    ) {
        try {
            for (payload in channel) {
                val buffer = ByteBuffer.wrap(payload)
                while (buffer.hasRemaining()) {
                    val written = withContext(Dispatchers.IO) {
                        socket.write(buffer)
                    }
                    if (written == 0) {
                        yield() // Let other coroutines run
                        if (!socket.isOpen) break
                    }
                }
                totalBytesShared.addAndGet(payload.size.toLong())
                totalBytesIn.addAndGet(payload.size.toLong())
            }
        } catch (e: Exception) {
            handleClose(sessionId)
            sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
        } finally {
            channel.close()
        }
    }

    /**
     * CMD_DATA: Forward data to target TCP connection.
     */
    private suspend fun handleData(sessionId: UUID, payload: ByteArray) {
        val dataChannel = sessionChannels[sessionId]
        if (dataChannel == null) {
            if (connectingSessions.contains(sessionId)) {
                // Buffer the data until connection is established
                val list = pendingData.getOrPut(sessionId) { java.util.Collections.synchronizedList(mutableListOf()) }
                synchronized(list) {
                    if (list.size >= maxPendingFramesPerSession) {
                        android.util.Log.w("ByteAway", "Pending queue overflow for session=$sessionId")
                        handleClose(sessionId)
                        sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
                        return
                    }
                    list.add(payload)
                }
            }
            return
        }

        // Fast-path for most traffic, avoiding coroutine explosion under heavy load.
        val queued = dataChannel.trySend(payload)
        if (queued.isSuccess) {
            return
        }

        // Apply natural backpressure in the node reader path instead of spawning
        // one coroutine per frame when channel is temporarily full.
        try {
            withTimeout(5000) {
                dataChannel.send(payload)
            }
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "Backpressure overflow for session=$sessionId: ${e.message}")
            handleClose(sessionId)
            sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
        }
    }

    /**
     * CMD_CLOSE: Close session and release resources.
     */
    private fun handleClose(sessionId: UUID) {
        peerClosedSessions.add(sessionId)
        connectingSessions.remove(sessionId)
        pendingData.remove(sessionId)
        sessionChannels.remove(sessionId)?.close()
        val channel = sessions.remove(sessionId)
        try { channel?.close() } catch (_: Exception) {}
    }

    /**
     * Read data from target TCP and send back through QUIC transport.
     */
    private suspend fun readFromTarget(sessionId: UUID, channel: SocketChannel) {
        val buffer = ByteBuffer.allocate(32768) // 32KB read buffer
        var bytesForwarded = 0L

        try {
            while (channel.isOpen && isNodeActive.get()) {
                buffer.clear()
                val bytesRead = withContext(Dispatchers.IO) {
                    channel.read(buffer)
                }

                if (bytesRead == -1) {
                    // EOF
                    appendExternalLog("Node session EOF: session=$sessionId")
                    sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
                    sessions.remove(sessionId)
                    channel.close()
                    return
                }

                if (bytesRead > 0) {
                    buffer.flip()
                    val data = ByteArray(buffer.remaining())
                    buffer.get(data)

                    val sent = sendFrame(CMD_DATA, sessionId, data)
                    if (!sent) {
                        throw IOException("node transport send returned false")
                    }
                    bytesForwarded += data.size.toLong()
                    totalBytesShared.addAndGet(data.size.toLong())
                    totalBytesOut.addAndGet(data.size.toLong())
                }
            }
        } catch (e: Exception) {
            val expectedStop = manualNodeStop || !isNodeActive.get()
            val peerClosed = peerClosedSessions.remove(sessionId)
            val expectedIoClose = e is ClosedChannelException ||
                e is AsynchronousCloseException ||
                (e is SocketException && (
                    (e.message?.contains("closed", ignoreCase = true) == true) ||
                    (e.message?.contains("Software caused connection abort", ignoreCase = true) == true)
                )) ||
                (e.message?.contains("closed", ignoreCase = true) == true)

            if (expectedStop || peerClosed || expectedIoClose) {
                android.util.Log.i("ByteAway", "Node session closed during shutdown: session=$sessionId")
                appendExternalLog("Node session closed: session=$sessionId bytes=$bytesForwarded")
            } else {
                android.util.Log.w("ByteAway", "Read failed for session=$sessionId: ${e.message}")
                appendExternalLog("Node session read failed: session=$sessionId error=${e.message ?: "closed"}")
            }
            sendFrame(CMD_CLOSE, sessionId, ByteArray(0))
            sessions.remove(sessionId)
            try { channel.close() } catch (_: Exception) {}
        } finally {
            peerClosedSessions.remove(sessionId)
        }
    }

    // ──────────────────────────────────────────────────────
    // Wire Protocol Encoder
    // ──────────────────────────────────────────────────────

    private fun sendFrame(cmd: Byte, sessionId: UUID, payload: ByteArray): Boolean {
        val frame = ByteArray(1 + 16 + payload.size)
        frame[0] = cmd
        uuidToBytes(sessionId).copyInto(frame, 1)
        payload.copyInto(frame, 17)
        return try {
            val ok = boxwrapper.Boxwrapper.sendNodeFrame(frame)
            if (ok) {
                quicFramesOut.incrementAndGet()
                quicBytesOut.addAndGet(frame.size.toLong())
                if (cmd == CMD_CONNECT || cmd == CMD_CLOSE) {
                    val cmdName = if (cmd == CMD_CONNECT) "CONNECT" else "CLOSE"
                    appendExternalLog("${activeNodeTransport.uppercase(Locale.US)} => $cmdName sid=$sessionId")
                }
            } else {
                appendExternalLog("${activeNodeTransport.uppercase(Locale.US)} send returned false cmd=$cmd sid=$sessionId payload=${payload.size}B")
            }
            ok
        } catch (e: Exception) {
            appendExternalLog("${activeNodeTransport.uppercase(Locale.US)} send exception cmd=$cmd sid=$sessionId err=${e.message ?: "unknown"}")
            false
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
                "VPN Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN и шаринг трафика (повышенный приоритет)"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val openAppIntent = Intent(this, com.ospab.byteaway.MainActivity::class.java)
        val openAppPending = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Status text: VPN line + Node line
        val vpnLine = when {
            isVpnRunning.get() -> "🔒 VPN: активен"
            isVpnConnecting.get() -> "⏳ VPN: подключение..."
            else -> "🔓 VPN: отключен"
        }
        val nodeLine = when {
            isNodeActive.get() -> "📡 Узел: активен (${sessions.size} сессий)"
            isNodeConnecting.get() -> "📡 Узел: подключение..."
            else -> ""
        }
        val statusText = if (nodeLine.isNotEmpty()) "$vpnLine  •  $nodeLine" else vpnLine

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ByteAway")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppPending)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        if (isVpnRunning.get() || isVpnConnecting.get()) {
            val stopIntent = Intent(this, ByteAwayForegroundService::class.java).apply {
                action = ACTION_STOP_VPN
            }
            val stopPendingIntent = PendingIntent.getService(
                this, 1, stopIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "STOP", stopPendingIntent)
        }

        // VPN action button
        val vpnToggleIntent = Intent(this, ByteAwayForegroundService::class.java).apply {
            action = if (isVpnRunning.get()) ACTION_STOP_VPN else ACTION_TOGGLE_VPN
        }
        val vpnTogglePending = PendingIntent.getService(
            this, 100, vpnToggleIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        builder.addAction(
            NotificationCompat.Action.Builder(
                0,
                if (isVpnRunning.get()) "⏹ VPN" else "▶ VPN",
                vpnTogglePending
            ).build()
        )

        // Node action button (only show stop if active)
        if (isNodeActive.get()) {
            val nodeStopIntent = Intent(this, ByteAwayForegroundService::class.java).apply {
                action = ACTION_STOP_NODE
            }
            val nodeStopPending = PendingIntent.getService(
                this, 101, nodeStopIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.addAction(
                NotificationCompat.Action.Builder(0, "⏹ Узел", nodeStopPending).build()
            )
        }

        return builder.build()
    }

    private fun updateNotification() {
        if (!isVpnRunning.get() && !isVpnConnecting.get() && !isNodeActive.get() && !isNodeConnecting.get()) return
        val notification = buildNotification("ByteAway активен")
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
    // ──────────────────────────────────────────────────────
    // State broadcasting to Flutter (via ServiceBridge)
    // ──────────────────────────────────────────────────────

    private fun broadcastState() {
        val currentUptime = if (isNodeActive.get() && nodeStartTime > 0) {
            (System.currentTimeMillis() - nodeStartTime) / 1000
        } else 0L

        // Aggregate VPN tun-forwarder counters into reported bytesIn/bytesOut
        val vpnIn = tunForwarder?.totalBytesIn?.get() ?: 0L
        val vpnOut = tunForwarder?.totalBytesOut?.get() ?: 0L

        val bytesInCombined = totalBytesIn.get() + vpnIn
        val bytesOutCombined = totalBytesOut.get() + vpnOut

        val map: Map<String, Any> = mapOf(
            "vpnConnected" to isVpnRunning.get(),
            "vpnConnecting" to isVpnConnecting.get(),
            "nodeActive" to isNodeActive.get(),
            "nodeConnecting" to isNodeConnecting.get(),
            "errorMessage" to (if (isVpnRunning.get() || isVpnConnecting.get()) "" else (nodeErrorMessage ?: "")),
            "nodeErrorMessage" to (if (isNodeActive.get() || isNodeConnecting.get()) "" else (nodeErrorMessage ?: "")),
            // bytesShared remains node-sharing specific
            "bytesShared" to totalBytesShared.get(),
            "activeSessions" to sessions.size,
            "uptime" to currentUptime,
            "currentSpeed" to currentSpeedMbps,
            "bytesIn" to bytesInCombined,
            "bytesOut" to bytesOutCombined
        )
        if (lastBroadcastState == map) {
            return
        }
        lastBroadcastState = map
        ServiceBridge.sendEvent(map)
        updateNotification()
        
        // Sync Quick Settings Tile
        ByteAwayTileService.requestUpdate(this)
    }

    override fun onDestroy() {
        android.util.Log.w("ByteAway", "Service onDestroy() called.")
        
        // Synchronous part of stopping to ensure ports are freed
        try {
            boxwrapper.Boxwrapper.stopBox()
        } catch (_: Exception) {}

        stopVpn()
        stopNode()
        
        tunForwarder?.stop()
        tunForwarder = null
        vpnInterface?.close()
        vpnInterface = null
        
        scope.cancel()
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
