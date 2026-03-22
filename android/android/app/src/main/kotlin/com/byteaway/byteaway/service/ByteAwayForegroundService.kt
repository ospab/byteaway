package com.ospab.byteaway.service

import android.app.*
import android.content.Context
import android.content.Intent
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

/**
 * ByteAway Foreground Service — runs as a persistent Android foreground service.
 *
 * Responsibilities:
 * - Manages sing-box VPN core lifecycle (start/stop)
 * - Establishes WebSocket connection to master node
 * - Handles binary tunnel protocol (CMD_CONNECT/DATA/CLOSE)
 * - Maintains informative notification with sharing status
 * - Tracks traffic counters and broadcasts state to Flutter
 */
class ByteAwayForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "byteaway_service"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START_VPN = "com.byteaway.START_VPN"
        const val ACTION_STOP_VPN = "com.byteaway.STOP_VPN"
        const val ACTION_START_NODE = "com.byteaway.START_NODE"
        const val ACTION_STOP_NODE = "com.byteaway.STOP_NODE"

        // Wire protocol constants (match master_node/ws_tunnel.rs)
        const val CMD_CONNECT: Byte = 0x01
        const val CMD_DATA: Byte = 0x02
        const val CMD_CLOSE: Byte = 0x03
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var webSocket: WebSocket? = null
    private val httpClient = OkHttpClient.Builder()
        .pingInterval(java.time.Duration.ofSeconds(30))
        .build()

    // State
    private val isVpnRunning = AtomicBoolean(false)
    private val isNodeActive = AtomicBoolean(false)
    private val totalBytesShared = AtomicLong(0)
    private var nodeStartTime: Long = 0

    // Active tunnel sessions: session_id -> SocketChannel
    private val sessions = ConcurrentHashMap<UUID, SocketChannel>()

    // Wake lock to prevent CPU sleep during sharing
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_VPN -> startVpn(intent.getStringExtra("config") ?: "{}")
            ACTION_STOP_VPN -> stopVpn()
            ACTION_START_NODE -> {
                val token = intent.getStringExtra("token") ?: ""
                val deviceId = intent.getStringExtra("deviceId") ?: ""
                val country = intent.getStringExtra("country") ?: "auto"
                val speedMbps = intent.getIntExtra("speedMbps", 50)
                startNode(token, deviceId, country, speedMbps)
            }
            ACTION_STOP_NODE -> stopNode()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ──────────────────────────────────────────────────────
    // VPN Management (sing-box)
    // ──────────────────────────────────────────────────────

    private fun startVpn(config: String) {
        startForeground(NOTIFICATION_ID, buildNotification("VPN подключается..."))
        
        scope.launch {
            try {
                // TODO: Load libsingbox.so and call SingBox.start(config)
                // For now, simulate VPN startup
                isVpnRunning.set(true)
                updateNotification()
                broadcastState()
            } catch (e: Exception) {
                isVpnRunning.set(false)
                updateNotification()
                broadcastState()
            }
        }
    }

    private fun stopVpn() {
        scope.launch {
            try {
                // TODO: Call SingBox.stop()
                isVpnRunning.set(false)
                if (!isNodeActive.get()) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    updateNotification()
                }
                broadcastState()
            } catch (e: Exception) {
                // Force stop on error
                isVpnRunning.set(false)
                broadcastState()
            }
        }
    }

    // ──────────────────────────────────────────────────────
    // Node (traffic sharing) Management
    // ──────────────────────────────────────────────────────

    private fun startNode(token: String, deviceId: String, country: String, speedMbps: Int) {
        if (isNodeActive.get()) return

        startForeground(NOTIFICATION_ID, buildNotification("Подключение к мастер ноде..."))
        acquireWakeLock()
        nodeStartTime = System.currentTimeMillis()

        val wsUrl = "wss://byteaway.ospab.host/ws" +
            "?device_id=$deviceId" +
            "&token=$token" +
            "&country=$country" +
            "&conn_type=wifi" +
            "&speed_mbps=$speedMbps"

        val request = Request.Builder()
            .url(wsUrl)
            .build()

        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                isNodeActive.set(true)
                updateNotification()
                broadcastState()
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                handleIncomingFrame(bytes.toByteArray())
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
                onNodeDisconnected()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                onNodeDisconnected()
                // Auto-reconnect after delay
                scope.launch {
                    delay(5000)
                    if (!isNodeActive.get()) {
                        startNode(token, deviceId, country, speedMbps)
                    }
                }
            }
        })
    }

    private fun stopNode() {
        isNodeActive.set(false)
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
    }

    private fun onNodeDisconnected() {
        isNodeActive.set(false)
        sessions.values.forEach { channel ->
            try { channel.close() } catch (_: Exception) {}
        }
        sessions.clear()
        releaseWakeLock()
        updateNotification()
        broadcastState()
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
        webSocket?.send(frame.toByteString(0, frame.size))
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
        val pendingIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.let { intent ->
                PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ByteAway")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: custom icon
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun updateNotification() {
        val vpnState = if (isVpnRunning.get()) "VPN ✓" else "VPN ✗"
        val nodeState = if (isNodeActive.get()) "Узел ✓" else "Узел ✗"
        val sharedMb = totalBytesShared.get() / (1024.0 * 1024.0)
        val sharedText = if (sharedMb > 1024) {
            String.format("%.2f GB", sharedMb / 1024.0)
        } else {
            String.format("%.1f MB", sharedMb)
        }

        val uptimeMin = if (isNodeActive.get() && nodeStartTime > 0) {
            (System.currentTimeMillis() - nodeStartTime) / 60000
        } else 0

        val text = "$vpnState | $nodeState | Отдано: $sharedText | ${uptimeMin}мин"

        val notification = buildNotification(text)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    // ──────────────────────────────────────────────────────
    // State broadcasting to Flutter (via ServiceBridge)
    // ──────────────────────────────────────────────────────

    private fun broadcastState() {
        val uptimeSeconds = if (isNodeActive.get() && nodeStartTime > 0) {
            (System.currentTimeMillis() - nodeStartTime) / 1000
        } else 0

        ServiceBridge.sendEvent(mapOf(
            "vpnConnected" to isVpnRunning.get(),
            "nodeActive" to isNodeActive.get(),
            "bytesShared" to totalBytesShared.get(),
            "activeSessions" to sessions.size,
            "uptime" to uptimeSeconds,
            "currentSpeed" to 0.0 // TODO: calculate rolling speed
        ))
    }

    // ──────────────────────────────────────────────────────
    // Wake Lock
    // ──────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "byteaway:node_sharing"
            )
            wakeLock?.acquire(10 * 60 * 60 * 1000L) // 10 hours max
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    override fun onDestroy() {
        scope.cancel()
        stopNode()
        stopVpn()
        releaseWakeLock()
        super.onDestroy()
    }
}
