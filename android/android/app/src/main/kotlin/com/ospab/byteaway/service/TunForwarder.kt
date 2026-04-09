package com.ospab.byteaway.service

import android.util.Base64
import android.net.VpnService
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.nio.channels.SocketChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Userspace tun2socks engine.
 *
 * Reads IP packets from a TUN file-descriptor, parses IPv4 TCP/UDP headers,
 * and proxies traffic through a remote SOCKS5 gateway (master node).
 *
 * TCP  → SOCKS5 connect to destination via master node
 * UDP 53 (DNS) → forwarded via protected DatagramChannel to 8.8.8.8
 *
 * All outgoing real sockets are protect()-ed so they bypass the TUN.
 */
class TunForwarder(
    private val vpnService: VpnService,
    private val tunFd: ParcelFileDescriptor,
    private val socksHost: String,
    private val socksPort: Int = 1080,
    private val tunMtu: Int = 1280,
) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val isRunning = AtomicBoolean(false)

    val totalBytesIn = AtomicLong(0)
    val totalBytesOut = AtomicLong(0)

    // TCP sessions keyed by "srcIp:srcPort→dstIp:dstPort"
    private val tcpSessions = ConcurrentHashMap<String, TcpSession>()
    private val udpSessions = ConcurrentHashMap<String, UdpSession>()
    private val maxTcpPayloadPerPacket = (tunMtu.coerceIn(1280, 1480) - 40).coerceAtLeast(512)
    

    // TUN I/O
    private lateinit var tunIn: FileInputStream
    private lateinit var tunOut: FileOutputStream

    // Whether SOCKS5 is reachable (cached after first attempt)
    @Volatile private var socksReachable: Boolean? = null
    @Volatile private var lastSocksFailureAt: Long = 0L
    @Volatile private var lastDnsFailureLogAt: Long = 0L
    private val tunWriteLock = Any()

    // ─── Data classes ────────────────────────────────────

    data class TcpSession(
        val key: String,
        val srcIp: ByteArray,
        val srcPort: Int,
        val dstIp: ByteArray,
        val dstPort: Int,
        val socket: SocketChannel,
        var mySeq: Long,
        var theirSeq: Long,
        var readJob: Job? = null
    )

    data class UdpSession(
        val key: String,
        val channel: DatagramChannel,
        val lastActivity: AtomicLong,
        val job: Job
    )

    // ─── Lifecycle ───────────────────────────────────────

    fun start() {
        tunIn = FileInputStream(tunFd.fileDescriptor)
        tunOut = FileOutputStream(tunFd.fileDescriptor)

        android.util.Log.i("ByteAway", "TunForwarder started → SOCKS5 $socksHost:$socksPort")

        isRunning.set(true)
        scope.launch {
            readLoop()
        }
        scope.launch {
            udpCleanupLoop()
        }
    }

    private suspend fun readLoop() {
        val buf = ByteArray(32768)
        try {
            while (isRunning.get()) {
                val n = tunIn.read(buf)
                if (n > 0) {
                    processPacket(buf.copyOf(n), n)
                } else if (n == -1) {
                    break
                }
            }
        } catch (e: Exception) {
            if (isRunning.get()) {
                android.util.Log.e("ByteAway", "TUN read error: ${e.message}")
            }
        }
    }

    private suspend fun udpCleanupLoop() {
        while (isRunning.get()) {
            delay(30_000)
            val now = System.currentTimeMillis()
            val toRemove = mutableListOf<String>()
            udpSessions.forEach { (key, session) ->
                if (now - session.lastActivity.get() > 60_000) {
                    toRemove.add(key)
                }
            }
            toRemove.forEach { key ->
                val s = udpSessions.remove(key)
                s?.job?.cancel()
                try { s?.channel?.close() } catch (_: Exception) {}
            }
        }
    }

    fun stop() {
        isRunning.set(false)
        scope.cancel()
        tcpSessions.values.forEach { s ->
            s.readJob?.cancel()
            try { s.socket.close() } catch (_: Exception) {}
        }
        tcpSessions.clear()
        udpSessions.values.forEach { s ->
            s.job.cancel()
            try { s.channel.close() } catch (_: Exception) {}
        }
        udpSessions.clear()
    }

    // ─── Packet Dispatcher ───────────────────────────────

    private fun processPacket(pkt: ByteArray, len: Int) {
        if (len < 20) return
        val ver = (pkt[0].toInt() ushr 4) and 0xF
        if (ver != 4) return // IPv4 only

        val ihl = (pkt[0].toInt() and 0xF) * 4
        if (len < ihl) return

        val proto = pkt[9].toInt() and 0xFF
        val srcIp = pkt.copyOfRange(12, 16)
        val dstIp = pkt.copyOfRange(16, 20)

        when (proto) {
            1  -> handleIcmp(pkt, len, ihl, srcIp, dstIp)
            6  -> handleTcp(pkt, len, ihl, srcIp, dstIp)
            17 -> handleUdp(pkt, len, ihl, srcIp, dstIp)
        }
    }

    private fun handleIcmp(pkt: ByteArray, len: Int, ihl: Int, srcIp: ByteArray, dstIp: ByteArray) {
        if (len < ihl + 8) return
        val type = pkt[ihl].toInt() and 0xFF
        if (type == 8) { // Echo Request
            // Respond with Echo Reply (Type 0)
            val reply = pkt.copyOf(len)
            reply[ihl] = 0 // Type 0
            // Swap IPs
            System.arraycopy(dstIp, 0, reply, 12, 4)
            System.arraycopy(srcIp, 0, reply, 16, 4)
            // Recompute Checksum (Simple incremental change: 8 -> 0 is -8 in the big word)
            var cksum = u16(reply, ihl + 2)
            cksum += 0x0800
            if (cksum > 0xFFFF) cksum += 1
            reply[ihl + 2] = (cksum ushr 8).toByte()
            reply[ihl + 3] = (cksum and 0xFF).toByte()
            
            scope.launch {
                try {
                    writeTun(reply)
                } catch (_: Exception) {}
            }
        }
    }

    // ─── TCP Handler ─────────────────────────────────────

    private fun handleTcp(pkt: ByteArray, len: Int, ihl: Int, srcIp: ByteArray, dstIp: ByteArray) {
        if (len < ihl + 20) return

        val t = ihl // tcp offset
        val srcPort = u16(pkt, t)
        val dstPort = u16(pkt, t + 2)
        val seq = u32(pkt, t + 4)
        val ack = u32(pkt, t + 8)
        val dataOff = ((pkt[t + 12].toInt() ushr 4) and 0xF) * 4
        val flags = pkt[t + 13].toInt() and 0x3F

        val syn = flags and F_SYN != 0
        val ackF = flags and F_ACK != 0
        val fin = flags and F_FIN != 0
        val rst = flags and F_RST != 0

        val key = sessionKey(srcIp, srcPort, dstIp, dstPort)

        when {
            syn && !ackF -> onTcpSyn(key, srcIp, srcPort, dstIp, dstPort, seq)
            rst -> {
                tcpSessions.remove(key)?.let { s ->
                    s.readJob?.cancel()
                    try { s.socket.close() } catch (_: Exception) {}
                }
            }
            fin -> {
                val s = tcpSessions.remove(key)
                if (s != null) {
                    s.readJob?.cancel()
                    try { s.socket.close() } catch (_: Exception) {}
                    // Send FIN-ACK
                    sendTcp(dstIp, dstPort, srcIp, srcPort, s.mySeq, seq + 1, F_FIN or F_ACK, EMPTY)
                }
            }
            ackF -> {
                val s = tcpSessions[key] ?: return
                val payloadOff = t + dataOff
                val payloadLen = len - payloadOff
                if (payloadLen > 0) {
                    val payload = pkt.copyOfRange(payloadOff, payloadOff + payloadLen)
                    scope.launch {
                        try {
                            val buf = ByteBuffer.wrap(payload)
                            while (buf.hasRemaining()) s.socket.write(buf)
                            totalBytesOut.addAndGet(payloadLen.toLong())
                            s.theirSeq = seq + payloadLen
                            // ACK the data
                            sendTcp(dstIp, dstPort, srcIp, srcPort, s.mySeq, s.theirSeq, F_ACK, EMPTY)
                        } catch (_: Exception) {
                            tcpSessions.remove(key)
                            try { s.socket.close() } catch (_: Exception) {}
                            sendTcp(dstIp, dstPort, srcIp, srcPort, s.mySeq, seq + payloadLen, F_RST or F_ACK, EMPTY)
                        }
                    }
                }
            }
        }
    }

    private fun onTcpSyn(key: String, srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int, clientSeq: Long) {
        // Evict stale session
        tcpSessions.remove(key)?.let { old ->
            old.readJob?.cancel()
            try { old.socket.close() } catch (_: Exception) {}
        }

        scope.launch {
            try {
                val ch = SocketChannel.open()
                vpnService.protect(ch.socket())
                ch.socket().soTimeout = 0

                val useSocks = connectViaSocks(ch, InetAddress.getByAddress(dstIp), dstPort)

                if (!useSocks) {
                    android.util.Log.e("ByteAway", "SOCKS5 path unavailable for $key, sending RST")
                    sendTcp(dstIp, dstPort, srcIp, srcPort, 0, clientSeq + 1, F_RST or F_ACK, EMPTY)
                    return@launch
                }

                finishSynHandshake(key, srcIp, srcPort, dstIp, dstPort, clientSeq, ch)
            } catch (e: Exception) {
                android.util.Log.e("ByteAway", "onTcpSyn error for $key: ${e.message}")
                sendTcp(dstIp, dstPort, srcIp, srcPort, 0, clientSeq + 1, F_RST or F_ACK, EMPTY)
            }
        }
    }

    private fun finishSynHandshake(
        key: String, srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int,
        clientSeq: Long, ch: SocketChannel
    ) {
        val mySeq = System.nanoTime() and 0xFFFFFFFFL
        val session = TcpSession(
            key = key, srcIp = srcIp, srcPort = srcPort,
            dstIp = dstIp, dstPort = dstPort, socket = ch,
            mySeq = mySeq, theirSeq = clientSeq + 1
        )
        tcpSessions[key] = session

        // SYN-ACK
        sendTcp(dstIp, dstPort, srcIp, srcPort, mySeq, clientSeq + 1, F_SYN or F_ACK, EMPTY)
        session.mySeq = mySeq + 1 // SYN consumes 1 seq

        // Start reader
        session.readJob = scope.launch { readSocket(session) }
    }

    /** Connects [ch] through the SOCKS5 proxy. Returns true on success. */
    private fun connectViaSocks(ch: SocketChannel, dstAddr: InetAddress, dstPort: Int): Boolean {
        // Short cool-down for repeated failures, but allow auto-recovery.
        if (socksReachable == false && (System.currentTimeMillis() - lastSocksFailureAt) < 5000) {
            return false
        }

        try {
            ch.socket().connect(InetSocketAddress(socksHost, socksPort), 5_000)

            // Greeting
            ch.socket().getOutputStream().write(byteArrayOf(0x05, 0x01, 0x00))
            val greetResp = ByteArray(2)
            val r1 = readFully(ch.socket().getInputStream(), greetResp, 2)
            if (r1 != 2 || greetResp[0] != 0x05.toByte() || greetResp[1] != 0x00.toByte()) {
                socksReachable = false
                return false
            }

            // Connect request
            val addr = dstAddr.address
            val req = ByteArray(4 + addr.size + 2)
            req[0] = 0x05; req[1] = 0x01; req[2] = 0x00; req[3] = 0x01
            addr.copyInto(req, 4)
            req[4 + addr.size] = ((dstPort shr 8) and 0xFF).toByte()
            req[4 + addr.size + 1] = (dstPort and 0xFF).toByte()
            ch.socket().getOutputStream().write(req)

            val respHead = ByteArray(4)
            val r2 = readFully(ch.socket().getInputStream(), respHead, 4)
            if (r2 != 4 || respHead[1] != 0x00.toByte()) {
                // Proxy is reachable; this failure can be destination-specific.
                socksReachable = true
                return false
            }

            val atyp = respHead[3].toInt() and 0xFF
            val addrLen = when (atyp) {
                0x01 -> 4
                0x03 -> {
                    val n = ch.socket().getInputStream().read()
                    if (n < 0) return false
                    n
                }
                0x04 -> 16
                else -> return false
            }
            val tail = ByteArray(addrLen + 2)
            if (readFully(ch.socket().getInputStream(), tail, tail.size) != tail.size) {
                // Do not mark SOCKS dead for short/invalid destination reply.
                socksReachable = true
                return false
            }

            socksReachable = true
            ch.configureBlocking(true)
            return true
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "SOCKS5 connect failed: ${e.message}")
            socksReachable = false
            lastSocksFailureAt = System.currentTimeMillis()
            return false
        }
    }

    /** Background coroutine: read from real socket → write IP packets to TUN */
    private suspend fun readSocket(s: TcpSession) {
        val buf = ByteBuffer.allocate(16384)
        try {
            while (isRunning.get() && s.socket.isOpen) {
                buf.clear()
                val n = withContext(Dispatchers.IO) { s.socket.read(buf) }
                if (n == -1) {
                    sendTcp(s.dstIp, s.dstPort, s.srcIp, s.srcPort, s.mySeq, s.theirSeq, F_FIN or F_ACK, EMPTY)
                    s.mySeq++
                    break
                }
                if (n > 0) {
                    buf.flip()
                    val data = ByteArray(buf.remaining())
                    buf.get(data)
                    totalBytesIn.addAndGet(data.size.toLong())
                    val sentPayload = sendTcp(
                        s.dstIp,
                        s.dstPort,
                        s.srcIp,
                        s.srcPort,
                        s.mySeq,
                        s.theirSeq,
                        F_ACK or F_PSH,
                        data
                    )
                    s.mySeq += sentPayload
                }
            }
        } catch (_: Exception) {
            if (isRunning.get()) {
                sendTcp(s.dstIp, s.dstPort, s.srcIp, s.srcPort, s.mySeq, s.theirSeq, F_RST, EMPTY)
            }
        } finally {
            tcpSessions.remove(s.key)
            try { s.socket.close() } catch (_: Exception) {}
        }
    }

    // ─── UDP Handler (DNS only) ──────────────────────────

    private fun handleUdp(pkt: ByteArray, len: Int, ihl: Int, srcIp: ByteArray, dstIp: ByteArray) {
        if (len < ihl + 8) return
        val u = ihl
        val srcPort = u16(pkt, u)
        val dstPort = u16(pkt, u + 2)
        val udpLen = u16(pkt, u + 4)

        val payOff = u + 8
        val payLen = udpLen - 8
        if (payLen <= 0 || payOff + payLen > len) return
        val payload = pkt.copyOfRange(payOff, payOff + payLen)

        // Special handling for DNS: single flow via DNS-over-HTTPS.
        if (dstPort == 53 || (dstIp[0].toInt() == 1 && dstIp[1].toInt() == 1 && dstIp[2].toInt() == 1 && dstIp[3].toInt() == 1)) {
            scope.launch {
                handleDnsOverTcp(srcIp, srcPort, dstIp, dstPort, payload)
            }
            return
        }

        // UDP session key: srcPort -> dstHost:dstPort
        val key = "$srcPort:${InetAddress.getByAddress(dstIp).hostAddress}:$dstPort"
        
        var s = udpSessions[key]
        if (s == null) {
            try {
                val dc = DatagramChannel.open()
                vpnService.protect(dc.socket())
                dc.socket().soTimeout = 5000
                dc.connect(InetSocketAddress(InetAddress.getByAddress(dstIp), dstPort))
                
                val lastActivity = AtomicLong(System.currentTimeMillis())
                val job = scope.launch {
                    val resp = ByteBuffer.allocate(4096)
                    try {
                        while (isRunning.get() && dc.isOpen) {
                            resp.clear()
                            val n = dc.read(resp)
                            if (n <= 0) break
                            resp.flip()
                            val data = ByteArray(resp.remaining())
                            resp.get(data)
                            lastActivity.set(System.currentTimeMillis())
                            sendUdp(dstIp, dstPort, srcIp, srcPort, data)
                        }
                    } catch (_: Exception) {}
                    finally {
                        udpSessions.remove(key)
                        try { dc.close() } catch (_: Exception) {}
                    }
                }
                
                val newSession = UdpSession(key, dc, lastActivity, job)
                udpSessions[key] = newSession
                s = newSession
            } catch (e: Exception) {
                android.util.Log.e("ByteAway", "Failed to create UDP session: ${e.message}")
                return
            }
        }

        // Send payload via existing or new session
        scope.launch {
            try {
                s.lastActivity.set(System.currentTimeMillis())
                s.channel.write(ByteBuffer.wrap(payload))
            } catch (e: Exception) {
                udpSessions.remove(key)
                try { s.channel.close() } catch (_: Exception) {}
            }
        }
    }

    private suspend fun handleDnsOverTcp(srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int, query: ByteArray) {
        var lastError: String? = null
        val dohCandidates = listOf(
            DohEndpoint(connectIp = "1.1.1.1", host = "cloudflare-dns.com"),
            DohEndpoint(connectIp = "8.8.8.8", host = "dns.google"),
            DohEndpoint(connectIp = "9.9.9.9", host = "dns.quad9.net")
        )
        for (endpoint in dohCandidates) {
            val resp = resolveDnsViaDoh(query, endpoint)
            if (resp != null) {
                sendUdp(dstIp, dstPort, srcIp, srcPort, resp)
                return
            }
            lastError = "DoH failed for ${endpoint.host}"
        }

        val now = System.currentTimeMillis()
        if (now - lastDnsFailureLogAt > 5000) {
            lastDnsFailureLogAt = now
            android.util.Log.w("ByteAway", "DNS DoH failed on all resolvers: $lastError")
        }
    }

    private fun resolveDnsViaDirectUdp(query: ByteArray, dnsServer: String, dnsPort: Int): ByteArray? {
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            vpnService.protect(socket)
            socket.soTimeout = 2000
            val addr = InetAddress.getByName(dnsServer)

            socket.send(DatagramPacket(query, query.size, addr, dnsPort))

            val buf = ByteArray(4096)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            resp.data.copyOf(resp.length)
        } catch (_: Exception) {
            null
        } finally {
            try { socket?.close() } catch (_: Exception) {}
        }
    }

    private data class DohEndpoint(
        val connectIp: String,
        val host: String,
        val path: String = "/dns-query"
    )

    private fun resolveDnsViaDoh(query: ByteArray, endpoint: DohEndpoint): ByteArray? {
        var raw: Socket? = null
        var tls: SSLSocket? = null
        return try {
            val encoded = Base64.encodeToString(
                query,
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )
            raw = Socket()
            vpnService.protect(raw)
            raw.soTimeout = 4000
            raw.connect(InetSocketAddress(endpoint.connectIp, 443), 4000)

            val sslFactory = SSLSocketFactory.getDefault() as SSLSocketFactory
            tls = (sslFactory.createSocket(
                raw,
                endpoint.host,
                443,
                true
            ) as SSLSocket).apply {
                soTimeout = 4000
                startHandshake()
            }

            val req = StringBuilder()
                .append("GET ${endpoint.path}?dns=$encoded HTTP/1.1\r\n")
                .append("Host: ${endpoint.host}\r\n")
                .append("Accept: application/dns-message\r\n")
                .append("Connection: close\r\n")
                .append("User-Agent: ByteAway-DNS/1.0\r\n")
                .append("\r\n")
                .toString()

            val out = tls.outputStream
            out.write(req.toByteArray(Charsets.US_ASCII))
            out.flush()

            val bytes = ByteArrayOutputStream()
            val buf = ByteArray(4096)
            while (true) {
                val n = tls.inputStream.read(buf)
                if (n <= 0) break
                bytes.write(buf, 0, n)
            }

            val rawResp = bytes.toByteArray()
            val headerEnd = indexOfHeaderEnd(rawResp)
            if (headerEnd <= 0) return null

            val headerText = String(rawResp, 0, headerEnd, Charsets.US_ASCII)
            if (!headerText.startsWith("HTTP/1.1 200") && !headerText.startsWith("HTTP/1.0 200")) {
                return null
            }

            val bodyOffset = headerEnd + 4
            val body = rawResp.copyOfRange(bodyOffset, rawResp.size)

            return if (headerText.contains("transfer-encoding: chunked", ignoreCase = true)) {
                decodeChunkedBody(body)
            } else {
                body
            }
        } catch (_: Exception) {
            null
        } finally {
            try { tls?.close() } catch (_: Exception) {}
            try { raw?.close() } catch (_: Exception) {}
        }
    }

    private fun indexOfHeaderEnd(bytes: ByteArray): Int {
        for (i in 0 until (bytes.size - 3)) {
            if (bytes[i] == '\r'.code.toByte() &&
                bytes[i + 1] == '\n'.code.toByte() &&
                bytes[i + 2] == '\r'.code.toByte() &&
                bytes[i + 3] == '\n'.code.toByte()
            ) {
                return i
            }
        }
        return -1
    }

    private fun decodeChunkedBody(body: ByteArray): ByteArray? {
        val out = ByteArrayOutputStream()
        var idx = 0
        try {
            while (idx < body.size) {
                val lineEnd = indexOfCrlf(body, idx)
                if (lineEnd <= idx) return null
                val sizeHex = String(body, idx, lineEnd - idx, Charsets.US_ASCII).trim()
                val chunkSize = sizeHex.substringBefore(';').toInt(16)
                idx = lineEnd + 2
                if (chunkSize == 0) return out.toByteArray()
                if (idx + chunkSize > body.size) return null
                out.write(body, idx, chunkSize)
                idx += chunkSize
                if (idx + 1 >= body.size || body[idx] != '\r'.code.toByte() || body[idx + 1] != '\n'.code.toByte()) {
                    return null
                }
                idx += 2
            }
        } catch (_: Exception) {
            return null
        }
        return null
    }

    private fun indexOfCrlf(bytes: ByteArray, start: Int): Int {
        for (i in start until (bytes.size - 1)) {
            if (bytes[i] == '\r'.code.toByte() && bytes[i + 1] == '\n'.code.toByte()) {
                return i
            }
        }
        return -1
    }

    // ─── Packet Construction ─────────────────────────────

    private fun sendTcp(
        srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int,
        seq: Long, ack: Long, flags: Int, payload: ByteArray
    ): Int {
        if (payload.isEmpty() || (flags and F_PSH) == 0) {
            sendSingleTcpSegment(srcIp, srcPort, dstIp, dstPort, seq, ack, flags, payload)
            return payload.size
        }

        var offset = 0
        var curSeq = seq
        while (offset < payload.size) {
            val chunkSize = minOf(maxTcpPayloadPerPacket, payload.size - offset)
            val chunk = payload.copyOfRange(offset, offset + chunkSize)
            sendSingleTcpSegment(srcIp, srcPort, dstIp, dstPort, curSeq, ack, flags, chunk)
            curSeq += chunkSize
            offset += chunkSize
        }

        return payload.size
    }

    private fun sendSingleTcpSegment(
        srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int,
        seq: Long, ack: Long, flags: Int, payload: ByteArray
    ) {
        val ipH = 20; val tcpH = 20
        val total = ipH + tcpH + payload.size
        val p = ByteArray(total)

        // IP header
        p[0] = 0x45.toByte()
        w16(p, 2, total)
        p[6] = 0x40.toByte() // DF
        p[8] = 64 // TTL
        p[9] = 6  // TCP
        srcIp.copyInto(p, 12)
        dstIp.copyInto(p, 16)
        val ipCk = checksum(p, 0, ipH)
        w16(p, 10, ipCk)

        // TCP header
        w16(p, ipH, srcPort)
        w16(p, ipH + 2, dstPort)
        w32(p, ipH + 4, seq)
        w32(p, ipH + 8, ack)
        p[ipH + 12] = (5 shl 4).toByte() // data offset 5 words
        p[ipH + 13] = flags.toByte()
        w16(p, ipH + 14, 65535) // window
        payload.copyInto(p, ipH + tcpH)

        // TCP checksum
        val tcpCk = tcpChecksum(srcIp, dstIp, p, ipH, tcpH + payload.size)
        w16(p, ipH + 16, tcpCk)

        writeTun(p)
    }

    private fun sendUdp(srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int, payload: ByteArray) {
        val ipH = 20; val udpH = 8
        val udpTotal = udpH + payload.size
        val total = ipH + udpTotal
        val p = ByteArray(total)

        p[0] = 0x45.toByte()
        w16(p, 2, total)
        p[6] = 0x40.toByte()
        p[8] = 64
        p[9] = 17 // UDP
        srcIp.copyInto(p, 12)
        dstIp.copyInto(p, 16)
        w16(p, 10, checksum(p, 0, ipH))

        w16(p, ipH, srcPort)
        w16(p, ipH + 2, dstPort)
        p[ipH + 4] = ((udpTotal ushr 8) and 0xFF).toByte()
        p[ipH + 5] = (udpTotal and 0xFF).toByte()
        payload.copyInto(p, ipH + udpH)
        
        // Compute UDP Checksum (Mandatory for some Android versions to handle DNS)
        val ck = udpChecksum(srcIp, dstIp, p, ipH, udpTotal)
        w16(p, ipH + 6, ck)

        writeTun(p)
    }

    private fun udpChecksum(srcIp: ByteArray, dstIp: ByteArray, pkt: ByteArray, off: Int, len: Int): Int {
        var sum = 0L
        // Pseudo-header
        for (i in 0 until 4 step 2) sum += u16(srcIp, i)
        for (i in 0 until 4 step 2) sum += u16(dstIp, i)
        sum += 17L // protocol UDP
        sum += len.toLong()
        
        // UDP Header + Payload
        var i = off; var rem = len
        while (rem > 1) {
            // Skip the checksum field itself (offset 6 in UDP header)
            if (i != off + 6) sum += u16(pkt, i)
            i += 2; rem -= 2
        }
        if (rem == 1) sum += (pkt[i].toInt() and 0xFF) shl 8
        
        while (sum shr 16 != 0L) sum = (sum and 0xFFFFL) + (sum shr 16)
        var res = sum.toInt().inv() and 0xFFFF
        if (res == 0) res = 0xFFFF
        return res
    }

    private fun writeTun(pkt: ByteArray) {
        try {
            synchronized(tunWriteLock) {
                tunOut.write(pkt)
            }
        } catch (e: Exception) {
            android.util.Log.w("ByteAway", "TUN write: ${e.message}")
        }
    }

    // ─── Helpers ─────────────────────────────────────────

    private fun sessionKey(s: ByteArray, sp: Int, d: ByteArray, dp: Int) =
        "${s[0].toInt() and 0xFF}.${s[1].toInt() and 0xFF}.${s[2].toInt() and 0xFF}.${s[3].toInt() and 0xFF}:$sp→" +
        "${d[0].toInt() and 0xFF}.${d[1].toInt() and 0xFF}.${d[2].toInt() and 0xFF}.${d[3].toInt() and 0xFF}:$dp"

    private fun u16(b: ByteArray, o: Int) = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)
    private fun u32(b: ByteArray, o: Int): Long =
        ((b[o].toLong() and 0xFF) shl 24) or ((b[o+1].toLong() and 0xFF) shl 16) or
        ((b[o+2].toLong() and 0xFF) shl 8) or (b[o+3].toLong() and 0xFF)

    private fun w16(b: ByteArray, o: Int, v: Int) {
        b[o] = ((v ushr 8) and 0xFF).toByte()
        b[o + 1] = (v and 0xFF).toByte()
    }
    private fun w32(b: ByteArray, o: Int, v: Long) {
        b[o]   = ((v ushr 24) and 0xFF).toByte()
        b[o+1] = ((v ushr 16) and 0xFF).toByte()
        b[o+2] = ((v ushr 8)  and 0xFF).toByte()
        b[o+3] = (v and 0xFF).toByte()
    }

    private fun readFully(input: java.io.InputStream, buffer: ByteArray, expected: Int): Int {
        var off = 0
        while (off < expected) {
            val n = input.read(buffer, off, expected - off)
            if (n <= 0) return off
            off += n
        }
        return off
    }

    private fun checksum(data: ByteArray, off: Int, len: Int): Int {
        var sum = 0L
        var i = off; var rem = len
        while (rem > 1) { sum += u16(data, i); i += 2; rem -= 2 }
        if (rem == 1) sum += (data[i].toInt() and 0xFF) shl 8
        while (sum ushr 16 != 0L) sum = (sum and 0xFFFF) + (sum ushr 16)
        return (sum.toInt() xor 0xFFFF) and 0xFFFF
    }

    private fun tcpChecksum(srcIp: ByteArray, dstIp: ByteArray, pkt: ByteArray, tcpOff: Int, tcpLen: Int): Int {
        var sum = 0L
        sum += u16(srcIp, 0); sum += u16(srcIp, 2)
        sum += u16(dstIp, 0); sum += u16(dstIp, 2)
        sum += 6 // protocol
        sum += tcpLen

        // zero checksum field temporarily
        val c0 = pkt[tcpOff + 16]; val c1 = pkt[tcpOff + 17]
        pkt[tcpOff + 16] = 0; pkt[tcpOff + 17] = 0

        var i = tcpOff; var rem = tcpLen
        while (rem > 1) { sum += u16(pkt, i); i += 2; rem -= 2 }
        if (rem == 1) sum += (pkt[i].toInt() and 0xFF) shl 8

        pkt[tcpOff + 16] = c0; pkt[tcpOff + 17] = c1

        while (sum ushr 16 != 0L) sum = (sum and 0xFFFF) + (sum ushr 16)
        return (sum.toInt() xor 0xFFFF) and 0xFFFF
    }

    companion object {
        const val F_FIN = 0x01; const val F_SYN = 0x02; const val F_RST = 0x04
        const val F_PSH = 0x08; const val F_ACK = 0x10
        private val EMPTY = ByteArray(0)
    }
}
