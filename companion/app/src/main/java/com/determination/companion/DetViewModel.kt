package com.determination.companion

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class RootState { CHECKING, GRANTED, DENIED }

/** One entry in the guest software catalog. */
data class CatalogApp(
    val pkg: String,
    val title: String,
    val blurb: String,
    val category: String,
)

val CATALOG = listOf(
    CatalogApp("firefox-esr", "Firefox ESR", "Full desktop browser", "Browsers"),
    CatalogApp("chromium", "Chromium", "Blink engine, wayland-native", "Browsers"),
    CatalogApp("epiphany-browser", "GNOME Web", "Lightweight WebKit browser", "Browsers"),
    CatalogApp("mpv", "mpv", "Minimal, GPU-accelerated video player", "Media"),
    CatalogApp("vlc", "VLC", "Plays everything", "Media"),
    CatalogApp("gnome-loupe", "Image Viewer", "GNOME Loupe, touch-friendly", "Media"),
    CatalogApp("libreoffice", "LibreOffice", "Full office suite (large!)", "Productivity"),
    CatalogApp("gnome-text-editor", "Text Editor", "GNOME's modern editor", "Productivity"),
    CatalogApp("evince", "Document Viewer", "PDF and friends", "Productivity"),
    CatalogApp("gnome-calculator", "Calculator", "GNOME calculator", "Productivity"),
    CatalogApp("nautilus", "Files", "GNOME file manager", "Productivity"),
    CatalogApp("phosh-mobile-settings", "Mobile Settings", "Phosh tweaks & scaling", "System"),
    CatalogApp("feedbackd", "feedbackd", "Haptics + LED event feedback", "System"),
    CatalogApp("htop", "htop", "Interactive process viewer", "System"),
    CatalogApp("fastfetch", "fastfetch", "System info, for screenshots", "System"),
    CatalogApp("foot", "foot", "Fast Wayland terminal", "System"),
)

class DetViewModel(app: Application) : AndroidViewModel(app) {

    init { Prefs.init(app) }

    // Settings (persisted; see Prefs)
    var pollSeconds by mutableStateOf(Prefs.pollSeconds); private set
    var stopGuestOnExit by mutableStateOf(Prefs.stopGuestOnExit); private set

    fun updatePollSeconds(v: Int) {
        Prefs.pollSeconds = v
        pollSeconds = v
    }

    fun updateStopGuestOnExit(v: Boolean) {
        Prefs.stopGuestOnExit = v
        stopGuestOnExit = v
        // Mirror to the device so desktop-off honors it on ANY exit path
        // (session-manager exits never go through this app).
        viewModelScope.launch(Dispatchers.IO) { Root.setStopGuestOnExitFlag(v) }
    }

    fun stopGuestNow() = act("guest-stop") { Root.stopGuest() }

    // Control
    var rootState by mutableStateOf(RootState.CHECKING); private set
    var status by mutableStateOf<Map<String, String>>(emptyMap()); private set
    var busy by mutableStateOf<String?>(null); private set
    var message by mutableStateOf<String?>(null)  // one-shot snackbar text
    var rebootPrompt by mutableStateOf<String?>(null)  // "why" text → offer reboot
    var logText by mutableStateOf<String?>(null)
    var logName by mutableStateOf<String?>(null)

    // Software
    var pkgStatus by mutableStateOf<Map<String, String>>(emptyMap()); private set
    var guestUp by mutableStateOf(false); private set
    var compositor by mutableStateOf("phosh"); private set
    var activeSession by mutableStateOf(""); private set
    var sessions by mutableStateOf<List<Root.SessionChoice>>(emptyList()); private set
    var installingPkg by mutableStateOf<String?>(null); private set
    var guestDistros by mutableStateOf<List<Root.GuestDistro>>(emptyList()); private set

    // Dock auto-summon (§8.3): enter desktop when the phone docks.
    var dock by mutableStateOf<Map<String, String>>(emptyMap()); private set

    fun setDockPolicy(trigger: String, autoExit: Boolean) {
        if (busy != null) return
        busy = "dock"
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.setDockPolicy(trigger, autoExit)
            if (!r.ok) message = r.err.ifBlank { r.out }.ifBlank { "Could not save dock policy" }
            dock = Root.dockPolicy()
            busy = null
        }
    }

    var externalDisplay by mutableStateOf(ExternalDisplayState.read(app)); private set
    var externalRenderer by mutableStateOf("auto"); private set
    var externalInputCaptured by mutableStateOf(false); private set
    var hardwareButtons by mutableStateOf<List<Root.HardwareButton>>(emptyList()); private set
    var inputMappings by mutableStateOf<Map<String, String>>(emptyMap()); private set

    fun refreshExternalDisplay() {
        externalDisplay = ExternalDisplayState.read(getApplication())
    }

    fun startExternalPresenter() {
        val app = getApplication<Application>()
        app.startForegroundService(ExternalDisplayService.startIntent(app))
        externalDisplay = externalDisplay.copy(phase = "starting", error = "")
    }

    fun stopExternalPresenter() {
        val app = getApplication<Application>()
        ExternalDisplayService.stop(app)
        externalDisplay = ExternalDisplaySnapshot(phase = "off")
    }

    fun runExternalTest() = act("presenter-test", refreshAfter = false) {
        Root.externalPresenterSmoke()
    }

    fun runExternalPlasma() = act("presenter-plasma", refreshAfter = false) {
        Root.externalPresenterPlasma()
    }

    fun selectExternalRenderer(renderer: String) {
        if (renderer !in setOf("auto", "mesa-prefix", "zink", "turnip-zink") ||
            busy != null
        ) return
        busy = "renderer"
        viewModelScope.launch(Dispatchers.IO) {
            val result = Root.setExternalRenderer(renderer)
            if (result.ok) {
                externalRenderer = renderer
            } else {
                message = result.err.ifBlank { result.out }.ifBlank {
                    "Could not select renderer"
                }
            }
            busy = null
        }
    }

    fun toggleExternalInput() {
        if (busy != null) return
        busy = "external-input"
        viewModelScope.launch(Dispatchers.IO) {
            val result = if (externalInputCaptured) {
                Root.stopExternalInput()
            } else {
                Root.startExternalInput()
            }
            if (!result.ok) {
                message = result.err.ifBlank { result.out }.ifBlank {
                    "External input capture failed"
                }
            }
            externalInputCaptured = Root.externalInputStatus()
            busy = null
        }
    }

    fun refreshHardwareButtons() {
        if (rootState != RootState.GRANTED || busy != null) return
        busy = "buttons"
        viewModelScope.launch(Dispatchers.IO) {
            hardwareButtons = Root.enumerateHardwareButtons()
            inputMappings = Root.inputMappings()
            busy = null
        }
    }

    fun cycleHardwareButton(code: String) {
        if (busy != null) return
        val actions = listOf(
            "default", "volume-up", "volume-down", "mute", "play-pause",
            "next", "previous", "exit-desktop",
        )
        val current = inputMappings[code] ?: "default"
        val next = actions[(actions.indexOf(current).coerceAtLeast(0) + 1) % actions.size]
        busy = "button-$code"
        viewModelScope.launch(Dispatchers.IO) {
            val result = Root.setInputMapping(code, next)
            if (result.ok) inputMappings = Root.inputMappings()
            else message = result.err.ifBlank { "Could not save button mapping" }
            busy = null
        }
    }

    val logs = listOf("compositor.log", "toggle.log", "hostagent.log", "service.log")

    fun refresh() {
        busy = "status"
        viewModelScope.launch(Dispatchers.IO) {
            // One su round-trip: the status script reports uid, which doubles
            // as the root check (previously a separate `id -u` trip).
            val s = Root.status()
            rootState = if (s["uid"] == "0") RootState.GRANTED else RootState.DENIED
            status = if (rootState == RootState.GRANTED) s else emptyMap()
            externalDisplay = ExternalDisplayState.read(getApplication())
            externalRenderer = Root.externalRenderer()
            externalInputCaptured = Root.externalInputStatus()
            hardwareButtons = Root.enumerateHardwareButtons()
            inputMappings = Root.inputMappings()
            val sessionInfo = Root.sessionInfo()
            compositor = sessionInfo["compositor"].orEmpty().ifBlank { "phosh" }
            activeSession = Root.activeSession()
            sessions = Root.sessions()
            busy = null
        }
    }

    /** Background poll: refresh status without the busy spinner (no UI flicker). */
    fun refreshQuiet() {
        if (rootState != RootState.GRANTED || busy != null) return
        viewModelScope.launch(Dispatchers.IO) {
            status = Root.status()
            externalDisplay = ExternalDisplayState.read(getApplication())
            externalInputCaptured = Root.externalInputStatus()
        }
    }

    fun refreshSoftware() {
        if (rootState != RootState.GRANTED) return
        busy = "software"
        viewModelScope.launch(Dispatchers.IO) {
            val info = Root.sessionInfo()
            guestDistros = Root.guestDistros()
            sessions = Root.sessions()
            compositor = (info["compositor"] ?: "").ifBlank { "phosh" }
            activeSession = Root.activeSession()
            guestUp = info["guestup"] == "yes"
            pkgStatus =
                if (guestUp) Root.dpkgStatus(CATALOG.map { it.pkg })
                else emptyMap()
            busy = null
        }
    }

    /** Run a Root action with a busy label, then refresh control status. */
    fun act(label: String, refreshAfter: Boolean = true, action: () -> Root.Result) {
        busy = label
        viewModelScope.launch(Dispatchers.IO) {
            val r = action()
            if (!r.ok) message = r.err.ifBlank { r.out }.ifBlank { "failed" }
            busy = null
            if (refreshAfter) refresh()
        }
    }

    fun installPkg(pkg: String) {
        installingPkg = pkg
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.aptInstall(pkg)
            message = if (r.ok) "$pkg installed" else "install failed: ${r.out.ifBlank { r.err }}"
            pkgStatus = Root.dpkgStatus(CATALOG.map { it.pkg })
            installingPkg = null
        }
    }

    fun removePkg(pkg: String) {
        installingPkg = pkg
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.aptRemove(pkg)
            message = if (r.ok) "$pkg removed" else "remove failed: ${r.out.ifBlank { r.err }}"
            pkgStatus = Root.dpkgStatus(CATALOG.map { it.pkg })
            installingPkg = null
        }
    }

    fun selectSession(id: String) {
        if (busy != null || rootState != RootState.GRANTED) return
        val session = sessions.firstOrNull { it.id == id } ?: return
        if (!session.installed) {
            message = session.availabilityReason.ifBlank { "${session.title} is not installed" }
            return
        }
        when (session.qualification) {
            "qualified", "proven", "experimental", "diagnostic" -> Unit
            else -> {
                message = session.reason.ifBlank {
                    "${session.title} is ${session.qualification}; it cannot be selected"
                }
                return
            }
        }
        busy = "session-$id"
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val result = Root.setCompositor(id)
                if (result.ok) {
                    compositor = id
                    message = "${session.title} selected for next desktop entry" +
                        if (session.qualification in setOf("experimental", "diagnostic"))
                            " · ${session.reason.ifBlank { session.qualification }}" else ""
                } else {
                    message = "Session selection failed: ${result.err.ifBlank { result.out }}"
                }
            } finally {
                busy = null
            }
        }
    }

    fun selectGuestDistro(id: String) {
        if (busy != null || guestDistros.none { it.id == id && it.installed }) return
        busy = "distro-$id"
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.selectGuestDistro(id)
            message = if (r.ok) "Active guest: $id" else r.err.ifBlank { r.out }
            guestDistros = Root.guestDistros()
            refreshSoftware()
        }
    }

    fun provisionGuestDistro() {
        if (busy != null) return
        busy = "distro-provision"
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.provisionGuestDistro()
            message = if (r.ok) "Guest base provisioned" else r.err.ifBlank { r.out }
            guestDistros = Root.guestDistros()
            busy = null
        }
    }

    fun openLog(name: String) {
        logName = name
        logText = null
        viewModelScope.launch(Dispatchers.IO) { logText = Root.tailLog(name) }
    }

    fun closeLog() { logName = null; logText = null }

}
