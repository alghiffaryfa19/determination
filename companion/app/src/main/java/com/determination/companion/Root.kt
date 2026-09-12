package com.determination.companion

import java.io.BufferedReader
import java.io.BufferedWriter
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Thin wrapper around Magisk `su`. Commands run through ONE persistent root
 * shell (a single su grant per app session) instead of a fresh `su -c` per
 * call : spawning su every 5s poll made Magisk toast "granted superuser
 * rights" endlessly. Determination's on-device tree lives at [DET].
 */
object Root {
    const val DET = "/data/determination"
    private const val BIN = "$DET/bin"
    private const val LXC = "$DET/lxc/bin"
    private const val MODDIR = "/data/adb/modules/determination"

    data class Result(val ok: Boolean, val out: String, val err: String)
    data class HardwareButton(
        val code: String,
        val label: String,
        val devices: List<String>,
    )
    data class GuestDistro(
        val id: String,
        val installed: Boolean,
        val active: Boolean,
        val ready: Boolean,
        val name: String,
    )

    /** One session manifest from $DET/etc/sessions, already honesty-filtered. */
    data class SessionChoice(
        val id: String,
        val title: String,
        val description: String,
        val backend: String,
        val renderer: String,
        val qualification: String,
        val reason: String,
        val limitations: List<String>,
        val installed: Boolean,
        val availabilityReason: String,
    )


    private const val MARK = "__DET_DONE__"
    private var shell: Process? = null
    private var stdin: BufferedWriter? = null
    private var stdout: BufferedReader? = null
    private var stderr: BufferedReader? = null
    private val reader = Executors.newCachedThreadPool()

    @Synchronized
    private fun ensureShell(): Boolean {
        shell?.let { if (it.isAlive) return true }
        return try {
            val p = ProcessBuilder("su").redirectErrorStream(false).start()
            shell = p
            stdin = p.outputStream.bufferedWriter()
            stdout = p.inputStream.bufferedReader()
            stderr = p.errorStream.bufferedReader()
            true
        } catch (e: Exception) {
            shell = null
            false
        }
    }

    @Synchronized
    private fun killShell() {
        shell?.destroyForcibly()
        shell = null
    }

    /** Run a command string in the persistent root shell. Blocking. */
    @Synchronized
    fun run(cmd: String, timeoutSec: Long = 15): Result {
        if (!ensureShell()) return Result(false, "", "su failed (no root?)")
        return try {
            stdin!!.apply {
                // Subshell so `exit`/`set -e` in cmd can't kill our shell.
                write("($cmd)\n")
                write("echo $MARK$?; echo $MARK >&2\n")
                flush()
            }
            val outF = reader.submit<String> { readUntilMark(stdout!!) }
            val errF = reader.submit<String> { readUntilMark(stderr!!) }
            val outRaw = outF.get(timeoutSec, TimeUnit.SECONDS)
            val err = errF.get(2, TimeUnit.SECONDS)
            val nl = outRaw.lastIndexOf('\n')
            val rcLine = outRaw.substring(nl + 1)
            val out = if (nl >= 0) outRaw.substring(0, nl) else ""
            Result(rcLine == "0", out.trim(), err.trim())
        } catch (e: TimeoutException) {
            killShell()
            Result(false, "", "timed out after ${timeoutSec}s")
        } catch (e: Exception) {
            killShell()
            Result(false, "", e.message ?: "su failed (no root?)")
        }
    }

    /** Read lines until the marker; return text before it (marker line carries rc on stdout). */
    private fun readUntilMark(r: BufferedReader): String {
        val sb = StringBuilder()
        while (true) {
            val line = r.readLine() ?: throw RuntimeException("root shell died")
            if (line.startsWith(MARK)) {
                sb.append(line.removePrefix(MARK))
                return sb.toString()
            }
            sb.append(line).append('\n')
        }
    }

    /** True if `su` is present and grants uid 0. */
    fun hasRoot(): Boolean = run("id -u", 8).let { it.ok && it.out.trim() == "0" }

    /** Whether the on-device Determination tree is installed. */
    fun isInstalled(): Boolean = run("[ -x $BIN/desktop-on ] && echo yes", 8).out.contains("yes")

    /** One su round-trip that returns parseable key=value status lines. */
    /*
     * Do not use the app-process Zygisk bridge here. A newly installed APK can
     * run before the matching module library is loaded by a reboot, and mixing
     * protocol/library generations has caused an uncatchable native SIGBUS.
     * The persistent root shell is slower only on its first call and works
     * across module upgrades without coupling the launcher to injected code.
     */
    fun status(): Map<String, String> = legacyStatus()

    private fun legacyStatus(): Map<String, String> {
        val script = """
            echo "uid=${'$'}(id -u)"
            echo "kernel=${'$'}(uname -r)"
            echo "sf=${'$'}(getprop init.svc.surfaceflinger)"
            [ -f $DET/run/desktop-mode ] && echo "mode=desktop" || echo "mode=phone"
            echo "distro=${'$'}($BIN/guest-distro active 2>/dev/null || echo debian)"
            $LXC/lxc-info -P $DET -n guest 2>/dev/null | grep -q RUNNING && echo "guest=running" || echo "guest=stopped"
            [ -e $DET/run/hostagent.pid ] && echo "agent=up" || echo "agent=down"
            echo "installed=${'$'}([ -x $BIN/desktop-on ] && echo yes || echo no)"
            echo "ip=${'$'}($LXC/lxc-info -P $DET -n guest 2>/dev/null | awk '/IP:/{print ${'$'}2; exit}')"
            gauge=${'$'}(sed -n 's/^DET_BATTERY_GAUGE=//p' $DET/etc/device.conf 2>/dev/null | tail -n 1)
            [ -n "${'$'}gauge" ] || gauge=battery
            echo "batt=${'$'}(cat /sys/class/power_supply/${'$'}gauge/capacity 2>/dev/null)"
            echo "battmv=${'$'}(( ${'$'}(cat /sys/class/power_supply/${'$'}gauge/voltage_now 2>/dev/null || echo 0) / 1000 ))"
            echo "battstat=${'$'}(cat /sys/class/power_supply/battery/status 2>/dev/null)"
            up=${'$'}(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
            echo "uptime=${'$'}((up / 3600))h ${'$'}(( (up % 3600) / 60 ))m"
            echo "datafree=${'$'}(df -h /data 2>/dev/null | awk 'NR==2{print ${'$'}4}')"
            echo "tstate=${'$'}(sed -n 's/^state=//p' $DET/run/transition.state 2>/dev/null | tail -n 1)"
            echo "tstep=${'$'}(sed -n 's/^step=//p' $DET/run/transition.state 2>/dev/null | tail -n 1)"
            echo "session=${'$'}(cat $DET/etc/compositor 2>/dev/null || echo phosh)"
        """.trimIndent()
        val r = run(script, 12)
        return parseKv(r.out)
    }

    private fun parseKv(text: String): Map<String, String> {
        val m = HashMap<String, String>()
        text.lineSequence().forEach { line ->
            val i = line.indexOf('=')
            if (i > 0) m[line.substring(0, i)] = line.substring(i + 1).trim()
        }
        return m
    }

    /**
     * Enter desktop mode. Ensures the guest is up, then launches desktop-on
     * DETACHED (setsid + nohup) so it survives this app being killed when
     * SurfaceFlinger stops and the Android UI disappears a moment later.
     */
    fun enterDesktop(): Result {
        return run(
            "$BIN/guest-start >/dev/null 2>&1; " +
                "setsid sh -c 'nohup $BIN/desktop-on >/dev/null 2>&1' >/dev/null 2>&1 &",
            20,
        )
    }

    /** Return to phone mode (restarts SurfaceFlinger). */
    fun exitDesktop(): Result {
        return run("$BIN/desktop-off", 30)
    }

    /** Copy an Android share-sheet staging file into Linux, guest running or not. */
    fun importToGuest(sourcePath: String, displayName: String): Result {
        val safeName = displayName
            .filter { it.code >= 32 && it !in "/\\" }
            .take(120)
            .ifBlank { "Shared file" }
        val inbox = "$DET/active-guest/home/detuser/Downloads/From Android"
        val destination = "$inbox/$safeName"
        return run(
            "install -d -m 0755 -o 1000 -g 1000 ${shellQuote(inbox)}; " +
                "cp -f ${shellQuote(sourcePath)} ${shellQuote(destination)}; " +
                "chown 1000:1000 ${shellQuote(destination)}; " +
                "chmod 0644 ${shellQuote(destination)}",
            30,
        )
    }

    /**
     * Dock auto-summon policy (§8.3): the phone enters desktop mode on its
     * own panel when a remembered trigger has been stable for a grace period,
     * and optionally returns to phone when it disappears.
     */
    fun dockPolicy(): Map<String, String> =
        parseKv(run("cat $DET/etc/dock.conf 2>/dev/null", 8).out)

    fun setDockPolicy(trigger: String, autoExit: Boolean): Result {
        if (trigger !in setOf("off", "charger", "display"))
            return Result(false, "", "invalid dock trigger")
        val body = "trigger=$trigger\ngrace_sec=10\nexit_grace_sec=20\n" +
            "min_battery=15\nauto_exit=${if (autoExit) "1" else "0"}\n"
        val write = "mkdir -p $DET/etc; printf %s ${shellQuote(body)} > " +
            "$DET/etc/dock.conf.new; chmod 0644 $DET/etc/dock.conf.new; " +
            "mv -f $DET/etc/dock.conf.new $DET/etc/dock.conf"
        val stop = "kill \$(cat $DET/run/dock-watch.pid 2>/dev/null) 2>/dev/null; " +
            "rm -f $DET/run/dock-watch.pid $DET/run/dock-watch.fired"
        // Start it right away so the user does not need a reboot.
        val start = "if ! kill -0 \$(cat $DET/run/dock-watch.pid 2>/dev/null) " +
            "2>/dev/null; then setsid $DET/bin/dock-watch >/dev/null 2>&1 & " +
            "echo \$! > $DET/run/dock-watch.pid; fi"
        return run(
            if (trigger == "off") "$write; $stop" else "$write; $start",
            15,
        )
    }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\"'\"'") + "'"

    /**
     * Recover a wedged desktop session without a full toggle: kill phoc; the
     * desktop-on supervisor relaunches the whole stack (compositor + phosh +
     * grabs) within ~10s. The go-to fix when the panel blanks or freezes.
     */
    fun recoverDesktop(): Result =
        run("$LXC/lxc-attach -P $DET -n guest -- /usr/bin/pkill -TERM phoc", 15)

    /** Stop the guest container (battery saver : it idles at ~0 but holds RAM + wakeups). */
    fun stopGuest(): Result = run("$LXC/lxc-stop -P $DET -n guest -t 10", 30)

    /**
     * Persist the "stop guest when leaving desktop mode" flag where desktop-off
     * reads it, so exits triggered from inside the desktop honor it too.
     */
    fun setStopGuestOnExitFlag(on: Boolean): Result =
        if (on) run("mkdir -p $DET/etc && touch $DET/etc/stop-guest-on-exit", 8)
        else run("rm -f $DET/etc/stop-guest-on-exit", 8)

    /** Stop + cold-start the guest container (guest-start is idempotent). */
    fun restartGuest(): Result = run(
        "$LXC/lxc-stop -P $DET -n guest -t 10 2>/dev/null; $BIN/guest-start", 40
    )

    /** Whole-phone power actions (best-effort clean teardown first). */
    fun rebootPhone(): Result =
        run("$BIN/desktop-off 2>/dev/null; svc power reboot || reboot", 20)

    fun powerOff(): Result =
        run("$BIN/desktop-off 2>/dev/null; svc power shutdown || reboot -p", 20)

    /** Tail one of the on-device logs for the in-app viewer. */
    fun tailLog(name: String, lines: Int = 120): String {
        val safe = name.filter { it.isLetterOrDigit() || it == '.' || it == '-' || it == '_' }
        val r = run("tail -n $lines $DET/log/$safe 2>/dev/null", 10)
        return if (r.out.isBlank()) "(empty or not found: $safe)" else r.out
    }

    fun guestRunning(): Boolean =
        run("$LXC/lxc-info -P $DET -n guest 2>/dev/null | grep -q RUNNING && echo yes", 8)
            .out.contains("yes")

    /** Compositor pref + guest state in one su round-trip (Software tab load). */
    fun sessionInfo(): Map<String, String> = parseKv(
        run(
            "echo \"compositor=${'$'}(cat $DET/etc/compositor 2>/dev/null)\"; " +
                "$LXC/lxc-info -P $DET -n guest 2>/dev/null | grep -q RUNNING " +
                "&& echo guestup=yes || echo guestup=no",
            10
        ).out
    )

    /**
     * Session manifests as deployed on the device. The picker renders these
     * verbatim: qualification labels and reasons come from the manifest, not
     * from hardcoded app lists, so an unqualified session can never look
     * selectable just because its package exists.
     */
    fun sessions(): List<SessionChoice> {
        val r = run(
            "$BIN/session-catalog",
            10,
        )
        val sessions = mutableListOf<SessionChoice>()
        var id = ""
        val fields = linkedMapOf<String, String>()
        fun flush() {
            if (id.isBlank()) return
            sessions += SessionChoice(
                id = id,
                title = fields["title"] ?: id,
                description = fields["description"] ?: "",
                backend = fields["backend"] ?: "",
                renderer = fields["renderer"] ?: "",
                qualification = fields["qualification"] ?: "planned",
                reason = fields["reason"] ?: "",
                limitations = (fields["limitations"] ?: "")
                    .split(',').map { it.trim() }.filter { it.isNotEmpty() },
                installed = fields["runtime_ready"] == "yes",
                availabilityReason = fields["runtime_reason"] ?: "Runtime availability unknown",
            )
        }
        for (line in r.out.lineSequence()) {
            if (line.startsWith("===")) {
                flush()
                id = line.removePrefix("===").trim()
                fields.clear()
                continue
            }
            val i = line.indexOf('=')
            if (i > 0) fields[line.substring(0, i)] = line.substring(i + 1).trim()
        }
        flush()
        return sessions.sortedWith(
            compareByDescending<SessionChoice> { it.qualification == "qualified" }
                .thenBy { it.id },
        )
    }

    /** Logical package status for many packages: one guest round-trip. */
    fun dpkgStatus(pkgs: List<String>): Map<String, String> {
        if (pkgs.isEmpty()) return emptyMap()
        val safe = pkgs.map { it.filter { c -> c.isLetterOrDigit() || c in ".+-" } }
        val r = run(
            "$LXC/lxc-attach -P $DET -n guest -- /usr/local/bin/det-platform " +
                "package-status ${safe.joinToString(" ")} 2>/dev/null",
            30
        )
        val states = parseKv(r.out)
        return safe.associateWith { if (states[it] == "installed") "installed" else "absent" }
    }

    /** Install one logical package through the active distro adapter. */
    fun aptInstall(pkg: String): Result {
        val p = pkg.filter { it.isLetterOrDigit() || it in ".+-" }
        return run(
            "$LXC/lxc-attach -P $DET -n guest -- /bin/sh -c " +
                "'det-platform package-refresh >/dev/null; det-platform package-install $p' 2>&1 | tail -5",
            600
        )
    }

    fun aptRemove(pkg: String): Result {
        val p = pkg.filter { it.isLetterOrDigit() || it in ".+-" }
        return run(
            "$LXC/lxc-attach -P $DET -n guest -- /bin/sh -c " +
                "'det-platform package-remove $p' 2>&1 | tail -5",
            300
        )
    }

    /**
     * Session/compositor preference, honored by toggle/session-select at the
     * next desktop-on. Experimental sessions need explicit selection here;
     * planned/incompatible ones refuse host-side regardless.
     */
    fun getCompositor(): String =
        run("cat $DET/etc/compositor 2>/dev/null", 8).out.trim().ifBlank { "phosh" }

    fun activeSession(): String = run(
        "if [ -f $DET/run/desktop-mode ]; then sed -n 's/^id=//p' $DET/run/session.active; fi", 8,
    ).out.trim()

    fun setCompositor(id: String): Result {
        if (!id.matches(Regex("[a-z0-9-]+")))
            return Result(false, "", "Invalid session id")
        return run("$BIN/session-set '$id'", 8)
    }

    fun externalPresenterSmoke(): Result = run("$BIN/external-presenter smoke", 45)

    fun externalPresenterPlasma(): Result = run("$BIN/external-presenter plasma", 30)

    fun guestDistros(): List<GuestDistro> = run("$BIN/guest-distro list", 10).out
        .lineSequence()
        .mapNotNull { line ->
            val fields = line.split('|')
            if (fields.size != 5) null else GuestDistro(
                id = fields[0],
                installed = fields[1] == "installed",
                active = fields[2] == "active",
                ready = fields[3] == "ready",
                name = fields[4],
            )
        }.toList()

    fun selectGuestDistro(id: String): Result {
        if (id !in setOf("debian", "arch", "alpine"))
            return Result(false, "", "unsupported guest distro")
        return run("$BIN/guest-distro select $id", 60)
    }

    fun provisionGuestDistro(): Result = run("$BIN/guest-distro provision", 1_800)

    fun externalRenderer(): String =
        run(". $BIN/device-config; echo ${'$'}DET_EXTERNAL_RENDERER", 8)
            .out.trim()
            .ifBlank { "auto" }

    fun setExternalRenderer(renderer: String): Result {
        if (renderer !in setOf("auto", "mesa-prefix", "zink", "turnip-zink"))
            return Result(false, "", "invalid external renderer")
        val config = "$DET/etc/device.conf"
        val temporary = "$DET/etc/device.conf.renderer-new"
        val guestConfig = "$DET/active-guest/etc/determination-device.conf"
        val guestTemporary = "$DET/active-guest/etc/determination-device.conf.renderer-new"
        return run(
            "mkdir -p $DET/etc; " +
                "sed '/^DET_EXTERNAL_RENDERER=/d' $config 2>/dev/null > $temporary; " +
                "echo 'DET_EXTERNAL_RENDERER=$renderer' >> $temporary; " +
                "mv -f $temporary $config; " +
                "if [ -d $DET/active-guest/etc ]; then " +
                "sed '/^DET_EXTERNAL_RENDERER=/d' $guestConfig 2>/dev/null > $guestTemporary; " +
                "echo 'DET_EXTERNAL_RENDERER=$renderer' >> $guestTemporary; " +
                "mv -f $guestTemporary $guestConfig; chmod 0644 $guestConfig; fi",
            8,
        )
    }

    fun externalInputStatus(): Boolean =
        run("$BIN/external-input status", 8).out.trim() == "active"

    fun startExternalInput(): Result = run("$BIN/external-input start", 20)

    fun stopExternalInput(): Result = run("$BIN/external-input stop", 15)

    private val remappableKeys = linkedMapOf(
        "KEY_VOLUMEUP" to "Volume up",
        "KEY_VOLUMEDOWN" to "Volume down",
        "KEY_MUTE" to "Mute",
        "KEY_MICMUTE" to "Mic mute",
        "KEY_MEDIA" to "Headset / media button",
        "KEY_PLAYPAUSE" to "Play / pause",
        "KEY_NEXTSONG" to "Next track",
        "KEY_PREVIOUSSONG" to "Previous track",
        "KEY_F3" to "Alert slider",
        "KEY_F4" to "Touch gesture button",
        "KEY_HOME" to "Home button",
        "KEY_CAMERA" to "Camera button",
        "KEY_SEARCH" to "Search button",
    )

    /** Enumerate real EV_KEY capabilities rather than assuming a phone layout. */
    fun enumerateHardwareButtons(): List<HardwareButton> {
        val output = run("getevent -lp 2>/dev/null", 15).out
        val devices = linkedMapOf<String, MutableSet<String>>()
        var device = "Unknown input device"
        var readingKeys = false
        val keyRegex = Regex("KEY_[A-Z0-9_]+")
        output.lineSequence().forEach { line ->
            when {
                line.trimStart().startsWith("name:") -> {
                    device = line.substringAfter('"', device).substringBeforeLast('"', device)
                    readingKeys = false
                }
                line.trimStart().startsWith("KEY (0001):") -> {
                    readingKeys = true
                    keyRegex.findAll(line.substringAfter(':')).forEach { match ->
                        if (match.value in remappableKeys) {
                            devices.getOrPut(match.value) { linkedSetOf() }.add(device)
                        }
                    }
                }
                readingKeys && line.startsWith("                ") -> {
                    keyRegex.findAll(line).forEach { match ->
                        if (match.value in remappableKeys) {
                            devices.getOrPut(match.value) { linkedSetOf() }.add(device)
                        }
                    }
                }
                else -> readingKeys = false
            }
        }
        return remappableKeys.mapNotNull { (code, label) ->
            devices[code]?.let { HardwareButton(code, label, it.toList()) }
        }
    }

    fun inputMappings(): Map<String, String> =
        run("cat $DET/active-guest/etc/determination/input-actions.conf 2>/dev/null", 8)
            .out.lineSequence()
            .mapNotNull { line ->
                val code = line.substringBefore('=')
                val action = line.substringAfter('=', "")
                if (code in remappableKeys && action in inputActions) code to action else null
            }.toMap()

    private val inputActions = setOf(
        "default", "volume-up", "volume-down", "mute", "play-pause",
        "next", "previous", "exit-desktop",
    )

    /** Persist one mapping atomically. It is applied at the next desktop session. */
    fun setInputMapping(code: String, action: String): Result {
        if (code !in remappableKeys || action !in inputActions) {
            return Result(false, "", "unsupported button mapping")
        }
        val mappings = inputMappings().toMutableMap()
        if (action == "default") mappings.remove(code) else mappings[code] = action
        val body = remappableKeys.keys.mapNotNull { key ->
            mappings[key]?.let { "$key=$it" }
        }.joinToString("\n", postfix = if (mappings.isEmpty()) "" else "\n")
        val path = "$DET/active-guest/etc/determination/input-actions.conf"
        return run(
            "install -d -m 0755 $DET/active-guest/etc/determination; " +
                "printf %s ${shellQuote(body)} > ${shellQuote(path)}; " +
                "chown 1000:1000 ${shellQuote(path)}; chmod 0644 ${shellQuote(path)}",
            10,
        )
    }
}
