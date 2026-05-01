package com.ospab.byteaway.service

import android.net.VpnService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.io.InputStream
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class OstpProxy(
    private val vpnService: VpnService,
    private val serverHost: String,
    private val serverPort: Int,
    private val token: String,
    private val country: String,
    private val connType: String,
    private val hwid: String,
    private val localPort: Int,
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val running = AtomicBoolean(false)
    private val nextStreamId = AtomicInteger(1)
    private val streamChannels = ConcurrentHashMap<Int, Channel<ProxyMsg>>()

    private var clientId: Long = -1
    private var socket: DatagramSocket? = null

    fun start() {
        if (running.getAndSet(true)) return

        val sessionId = (System.currentTimeMillis() and 0xFFFFFFFF).toInt()
        val privateKey = ByteArray(32) { 0 }
        clientId = OstpJni.createClient(
            "$serverHost:$serverPort",
            sessionId,
            privateKey,
            token,
            country,
            connType,
            hwid,
        )

        if (clientId <= 0) {
            running.set(false)
            return
        }

        val udp = DatagramSocket(null)
        udp.reuseAddress = true
        udp.bind(InetSocketAddress(0))
        vpnService.protect(udp)
        udp.connect(InetSocketAddress(serverHost, serverPort))
        socket = udp

        OstpJni.startClient(clientId)
        drainOutbound()

        scope.launch { udpReadLoop() }
        scope.launch { keepAliveLoop() }
        scope.launch { socksServerLoop() }
    }

    fun stop() {
        if (!running.getAndSet(false)) return
        try {
            socket?.close()
        } catch (_: Throwable) {
        }
        socket = null
        OstpJni.closeClient(clientId)
        streamChannels.values.forEach { it.close() }
        streamChannels.clear()
    }

    private suspend fun keepAliveLoop() {
        while (running.get()) {
            delay(10_000)
            sendRelay(0, RelayMessage.KeepAlive)
        }
    }

    private suspend fun udpReadLoop() {
        val buf = ByteArray(8192)
        while (running.get()) {
            try {
                val pkt = DatagramPacket(buf, buf.size)
                socket?.receive(pkt) ?: break
                if (!running.get()) break
                val data = pkt.data.copyOfRange(0, pkt.length)
                OstpJni.receiveData(clientId, data)
                drainOutbound()
                drainAppMessages()
            } catch (_: Throwable) {
                if (!running.get()) break
            }
        }
    }

    private fun drainOutbound() {
        val udp = socket ?: return
        while (true) {
            val out = OstpJni.getSendData(clientId)
            if (out == null || out.isEmpty()) return
            try {
                val pkt = DatagramPacket(out, out.size)
                udp.send(pkt)
            } catch (_: Throwable) {
                return
            }
        }
    }

    private fun drainAppMessages() {
        while (true) {
            val raw = OstpJni.getAppData(clientId)
            if (raw == null || raw.isEmpty()) return
            if (raw.size < 2) continue
            val streamId = ((raw[0].toInt() and 0xFF) shl 8) or (raw[1].toInt() and 0xFF)
            val payload = raw.copyOfRange(2, raw.size)
            val msg = RelayMessage.decode(payload) ?: continue
            val channel = streamChannels[streamId] ?: continue
            when (msg) {
                is RelayMessage.ConnectOk -> channel.trySend(ProxyMsg.ConnectOk)
                is RelayMessage.Data -> channel.trySend(ProxyMsg.Data(msg.payload))
                is RelayMessage.Close -> channel.trySend(ProxyMsg.Close)
                is RelayMessage.Error -> channel.trySend(ProxyMsg.Error(msg.message))
                else -> {}
            }
        }
    }

    private fun sendRelay(streamId: Int, message: RelayMessage) {
        val payload = message.encode()
        OstpJni.sendData(clientId, streamId, payload)
        drainOutbound()
    }

    private suspend fun socksServerLoop() {
        val server = ServerSocket()
        server.reuseAddress = true
        server.bind(InetSocketAddress("127.0.0.1", localPort))
        while (running.get()) {
            try {
                val socket = server.accept()
                scope.launch { handleSocksClient(socket) }
            } catch (_: Throwable) {
                if (!running.get()) break
            }
        }
        try { server.close() } catch (_: Throwable) {}
    }

    private suspend fun handleSocksClient(client: Socket) {
        client.tcpNoDelay = true
        val input = client.getInputStream()
        val output = client.getOutputStream()

        try {
            if (!readSocksGreeting(input, output)) {
                client.close()
                return
            }

            val target = readSocksConnectTarget(input)
            if (target == null) {
                sendSocksReply(output, 0x01)
                client.close()
                return
            }

            val streamId = nextStreamId.getAndIncrement().coerceAtMost(65534)
            val channel = Channel<ProxyMsg>(Channel.BUFFERED)
            streamChannels[streamId] = channel

            sendRelay(streamId, RelayMessage.Connect(target))
            val connectOk = withTimeoutOrNull(8_000) {
                when (val msg = channel.receive()) {
                    ProxyMsg.ConnectOk -> true
                    is ProxyMsg.Error -> false
                    else -> false
                }
            } ?: false

            if (!connectOk) {
                sendSocksReply(output, 0x05)
                streamChannels.remove(streamId)
                client.close()
                return
            }

            sendSocksReply(output, 0x00)

            val readerJob = scope.launch {
                val buffer = ByteArray(8192)
                while (running.get()) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    sendRelay(streamId, RelayMessage.Data(buffer.copyOf(read)))
                }
                sendRelay(streamId, RelayMessage.Close)
            }

            val writerJob = scope.launch {
                while (running.get()) {
                    when (val msg = channel.receive()) {
                        is ProxyMsg.Data -> output.write(msg.bytes)
                        is ProxyMsg.Close -> break
                        is ProxyMsg.Error -> break
                        ProxyMsg.ConnectOk -> {}
                    }
                }
            }

            readerJob.join()
            writerJob.cancel()
        } catch (_: Throwable) {
            // ignored
        } finally {
            try { client.close() } catch (_: Throwable) {}
        }
    }

    private fun readSocksGreeting(input: InputStream, output: OutputStream): Boolean {
        val header = input.readExact(2) ?: return false
        if (header[0].toInt() != 0x05) return false
        val methods = input.readExact(header[1].toInt()) ?: return false
        if (!methods.contains(0x00.toByte())) {
            output.write(byteArrayOf(0x05, 0xFF.toByte()))
            return false
        }
        output.write(byteArrayOf(0x05, 0x00))
        return true
    }

    private fun readSocksConnectTarget(input: InputStream): String? {
        val req = input.readExact(4) ?: return null
        if (req[0].toInt() != 0x05 || req[1].toInt() != 0x01) return null
        val atyp = req[3].toInt() and 0xFF
        val host = when (atyp) {
            0x01 -> {
                val ip = input.readExact(4) ?: return null
                ip.joinToString(".") { (it.toInt() and 0xFF).toString() }
            }
            0x03 -> {
                val len = input.readExact(1)?.get(0)?.toInt() ?: return null
                val domain = input.readExact(len) ?: return null
                String(domain)
            }
            0x04 -> {
                val ip = input.readExact(16) ?: return null
                val buf = ByteBuffer.wrap(ip)
                val parts = IntArray(8) { buf.short.toInt() and 0xFFFF }
                parts.joinToString(":") { it.toString(16) }
            }
            else -> return null
        }
        val portBytes = input.readExact(2) ?: return null
        val port = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
        return "$host:$port"
    }

    private fun sendSocksReply(output: OutputStream, code: Int) {
        output.write(byteArrayOf(0x05, code.toByte(), 0x00, 0x01, 0, 0, 0, 0, 0, 0))
    }

    private sealed class ProxyMsg {
        object ConnectOk : ProxyMsg()
        data class Data(val bytes: ByteArray) : ProxyMsg()
        object Close : ProxyMsg()
        data class Error(val message: String) : ProxyMsg()
    }

    private sealed class RelayMessage {
        object KeepAlive : RelayMessage()
        object Close : RelayMessage()
        object ConnectOk : RelayMessage()
        data class Connect(val target: String) : RelayMessage()
        data class Data(val payload: ByteArray) : RelayMessage()
        data class Error(val message: String) : RelayMessage()

        fun encode(): ByteArray {
            return when (this) {
                is Connect -> encodeWithLen(1, target.toByteArray())
                is Data -> encodeWithLen(2, payload)
                KeepAlive -> byteArrayOf(3)
                Close -> byteArrayOf(4)
                ConnectOk -> byteArrayOf(5)
                is Error -> encodeWithLen(6, message.toByteArray())
            }
        }

        companion object {
            fun decode(input: ByteArray): RelayMessage? {
                if (input.isEmpty()) return null
                return when (input[0].toInt()) {
                    1 -> decodeWithLen(input, 1)?.let { Connect(String(it)) }
                    2 -> decodeWithLen(input, 1)?.let { Data(it) }
                    3 -> KeepAlive
                    4 -> Close
                    5 -> ConnectOk
                    6 -> decodeWithLen(input, 1)?.let { Error(String(it)) }
                    else -> null
                }
            }

            private fun decodeWithLen(input: ByteArray, offset: Int): ByteArray? {
                if (input.size < offset + 2) return null
                val len = ((input[offset].toInt() and 0xFF) shl 8) or (input[offset + 1].toInt() and 0xFF)
                if (input.size < offset + 2 + len) return null
                return input.copyOfRange(offset + 2, offset + 2 + len)
            }

            private fun encodeWithLen(tag: Int, payload: ByteArray): ByteArray {
                val len = payload.size.coerceAtMost(0xFFFF)
                val out = ByteArray(1 + 2 + len)
                out[0] = tag.toByte()
                out[1] = (len shr 8).toByte()
                out[2] = len.toByte()
                System.arraycopy(payload, 0, out, 3, len)
                return out
            }
        }
    }
}

private fun InputStream.readExact(len: Int): ByteArray? {
    val buf = ByteArray(len)
    var off = 0
    while (off < len) {
        val r = this.read(buf, off, len - off)
        if (r <= 0) return null
        off += r
    }
    return buf
}
