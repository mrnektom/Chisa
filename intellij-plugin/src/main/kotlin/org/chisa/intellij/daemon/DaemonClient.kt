package org.chisa.intellij.daemon

import com.intellij.openapi.diagnostic.Logger
import org.json.JSONObject
import java.io.*
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.channels.Channels
import java.nio.channels.SocketChannel
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock

// ─── Protocol data classes ────────────────────────────────────────────────────

data class DaemonDiagnostic(
    val message: String,
    val line: Int,
    val col: Int,
    val start: Int,
    val end: Int,
)

data class DaemonCompletion(
    val label: String,
    val kind: String,
    val detail: String,
)

// ─── Internal connection abstraction ─────────────────────────────────────────

private interface Connection : Closeable {
    val reader: BufferedReader
    val writer: PrintWriter
    val isOpen: Boolean
}

private class TcpConnection(host: String, port: Int, timeoutMs: Int) : Connection {
    private val socket = Socket().apply { setSoTimeout(10_000); connect(InetSocketAddress(host, port), timeoutMs) }
    override val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
    override val writer = PrintWriter(BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)))
    override val isOpen get() = !socket.isClosed
    override fun close() { socket.close() }
}

private class UnixConnection(path: String) : Connection {
    private val channel: SocketChannel = run {
        val addrClass = Class.forName("java.net.UnixDomainSocketAddress")
        val addr = addrClass.getMethod("of", String::class.java).invoke(null, path)
        val protoEnum = Class.forName("java.net.StandardProtocolFamily")
            .getField("UNIX").get(null)
        val ch = SocketChannel::class.java
            .getMethod("open", Class.forName("java.net.ProtocolFamily"))
            .invoke(null, protoEnum) as SocketChannel
        ch.apply {
            Class.forName("java.nio.channels.SocketChannel")
                .getMethod("connect", Class.forName("java.net.SocketAddress"))
                .invoke(this, addr)
        }
    }
    override val reader = BufferedReader(InputStreamReader(Channels.newInputStream(channel), Charsets.UTF_8))
    override val writer = PrintWriter(BufferedWriter(OutputStreamWriter(Channels.newOutputStream(channel), Charsets.UTF_8)))
    override val isOpen get() = channel.isOpen
    override fun close() { channel.close() }
}

// ─── Client ───────────────────────────────────────────────────────────────────

/**
 * Thread-safe client that communicates with a running zs-daemon.
 *
 * Transport:
 *   - Unix domain socket on Linux/Mac (`/tmp/zs-daemon.sock`) when Java 16+ is available
 *   - TCP `127.0.0.1:<port>` otherwise (always on Windows)
 */
class DaemonClient(private val tcpPort: Int = 7654) {

    private val log = Logger.getInstance(DaemonClient::class.java)
    private val lock = ReentrantLock()
    private val idGen = AtomicLong(0)
    private var conn: Connection? = null
    private val readExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "zs-daemon-read").apply { isDaemon = true }
    }

    private val isWindows = System.getProperty("os.name", "").lowercase().contains("windows")
    private val unixSocketPath = "/tmp/zs-daemon.sock"

    // ─── Public API ───────────────────────────────────────────────────────────

    fun check(file: String, content: String): List<DaemonDiagnostic> {
        val resp = send("check", file, content, null) ?: return emptyList()
        val arr = resp.optJSONArray("diagnostics") ?: return emptyList()
        return (0 until arr.length()).map { i ->
            val d = arr.getJSONObject(i)
            DaemonDiagnostic(
                message = d.optString("message"),
                line = d.optInt("line"),
                col = d.optInt("col"),
                start = d.optInt("start"),
                end = d.optInt("end"),
            )
        }
    }

    fun complete(file: String, content: String, offset: Int): List<DaemonCompletion> {
        val resp = send("complete", file, content, offset.toLong()) ?: return emptyList()
        val arr = resp.optJSONArray("completions") ?: return emptyList()
        return (0 until arr.length()).map { i ->
            val c = arr.getJSONObject(i)
            DaemonCompletion(
                label = c.optString("label"),
                kind = c.optString("kind"),
                detail = c.optString("detail"),
            )
        }
    }

    fun hover(file: String, content: String, offset: Int): String? {
        val resp = send("hover", file, content, offset.toLong()) ?: return null
        return if (resp.isNull("type")) null else resp.optString("type")
    }

    fun close() {
        readExecutor.shutdown()
        if (lock.tryLock(2, TimeUnit.SECONDS)) {
            try { disconnect() } finally { lock.unlock() }
        }
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    private fun send(method: String, file: String, content: String, offset: Long?): JSONObject? {
        if (!lock.tryLock(5, TimeUnit.SECONDS)) {
            log.warn("zs-daemon: lock timeout — daemon may be stuck")
            return null
        }
        try {
            val c = ensureConnected() ?: return null
            val id = idGen.incrementAndGet()
            val req = buildRequest(id, method, file, content, offset)
            return try {
                c.writer.println(req)
                c.writer.flush()
                val line = try {
                    readExecutor.submit<String?> { c.reader.readLine() }.get(10, TimeUnit.SECONDS)
                } catch (e: TimeoutException) {
                    log.warn("zs-daemon: read timeout")
                    disconnect()
                    return null
                } catch (e: ExecutionException) {
                    log.warn("zs-daemon: IO error — ${e.cause?.message}")
                    disconnect()
                    return null
                } ?: run {
                    log.warn("zs-daemon: connection closed by peer")
                    disconnect()
                    return null
                }
                JSONObject(line)
            } catch (e: IOException) {
                log.warn("zs-daemon: IO error — ${e.message}")
                disconnect()
                null
            }
        } finally {
            lock.unlock()
        }
    }

    private fun ensureConnected(): Connection? {
        val existing = conn
        if (existing != null && existing.isOpen) return existing
        disconnect()
        val c = tryConnect()
        conn = c
        return c
    }

    private fun tryConnect(): Connection? {
        if (!isWindows) {
            try {
                val c = UnixConnection(unixSocketPath)
                log.info("zs-daemon: connected via Unix socket")
                return c
            } catch (e: Exception) {
                log.warn("zs-daemon: Unix socket failed (${e.message}), trying TCP")
            }
        }
        return try {
            val c = TcpConnection("127.0.0.1", tcpPort, 2000)
            log.info("zs-daemon: connected via TCP :$tcpPort")
            c
        } catch (e: IOException) {
            log.warn("zs-daemon: TCP connection failed — ${e.message}")
            null
        }
    }

    private fun disconnect() {
        try { conn?.close() } catch (_: IOException) {}
        conn = null
    }

    private fun buildRequest(id: Long, method: String, file: String, content: String, offset: Long?): String {
        val obj = JSONObject()
        obj.put("id", id)
        obj.put("method", method)
        obj.put("file", file)
        obj.put("content", content)
        if (offset != null) obj.put("offset", offset)
        return obj.toString()
    }
}
