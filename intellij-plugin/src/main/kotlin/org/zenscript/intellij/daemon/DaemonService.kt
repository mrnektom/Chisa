package org.zenscript.intellij.daemon

import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import org.zenscript.intellij.settings.ZenScriptSettings
import java.io.File
import java.io.IOException

/**
 * Project-level service that manages the zs-daemon process lifecycle and
 * provides a shared [DaemonClient].
 *
 * The daemon is started on first use and stopped when the project is closed.
 */
@Service(Service.Level.PROJECT)
class DaemonService(private val project: Project) : Disposable {

    private val log = Logger.getInstance(DaemonService::class.java)

    @Volatile private var process: Process? = null
    @Volatile private var client: DaemonClient? = null

    // ─── Public API ───────────────────────────────────────────────────────────

    /**
     * Returns a ready [DaemonClient], starting the daemon if needed.
     * Returns null if the daemon path is not configured or startup fails.
     */
    fun getClient(): DaemonClient? {
        val existing = client
        if (existing != null && isDaemonAlive()) return existing
        return startDaemon()
    }

    override fun dispose() {
        stopDaemon()
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    @Synchronized
    private fun startDaemon(): DaemonClient? {
        // Return existing if already running
        val existingClient = client
        if (existingClient != null && isDaemonAlive()) return existingClient

        val settings = ZenScriptSettings.getInstance(project)
        val daemonPath = settings.daemonPath.takeIf { it.isNotBlank() } ?: run {
            log.info("zs-daemon: path not configured — skipping startup")
            return null
        }

        if (!File(daemonPath).canExecute()) {
            log.warn("zs-daemon: binary not executable: $daemonPath")
            return null
        }

        stopDaemon()

        val cmd = buildList {
            add(daemonPath)
            val stdlibPath = settings.stdlibPath.takeIf { it.isNotBlank() }
            if (stdlibPath != null) { add("--stdlib"); add(stdlibPath) }
            if (!System.getProperty("os.name", "").lowercase().contains("windows")) {
                // Unix: port not used, but pass it anyway for TCP fallback
            } else {
                add("--port"); add(settings.daemonPort.toString())
            }
        }

        return try {
            val proc = ProcessBuilder(cmd)
                .redirectErrorStream(true) // merge stderr into stdout for logging
                .start()
            process = proc

            // Log daemon output asynchronously
            Thread({
                proc.inputStream.bufferedReader().use { reader ->
                    reader.lineSequence().forEach { line ->
                        log.info("zs-daemon: $line")
                    }
                }
            }, "zs-daemon-output").apply { isDaemon = true; start() }

            // Give the daemon a moment to bind the socket
            Thread.sleep(200)

            if (!proc.isAlive) {
                log.warn("zs-daemon: process exited immediately (exit=${proc.exitValue()})")
                process = null
                return null
            }

            val port = settings.daemonPort
            val c = DaemonClient(port)
            client = c
            log.info("zs-daemon: started (pid=${proc.pid()}, port=$port)")
            c
        } catch (e: IOException) {
            log.warn("zs-daemon: failed to start — ${e.message}")
            null
        }
    }

    @Synchronized
    private fun stopDaemon() {
        client?.close()
        client = null
        process?.destroy()
        process = null
    }

    private fun isDaemonAlive(): Boolean = process?.isAlive == true

    companion object {
        fun getInstance(project: Project): DaemonService =
            project.getService(DaemonService::class.java)
    }
}
