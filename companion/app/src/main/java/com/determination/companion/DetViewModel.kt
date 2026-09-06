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
import java.net.SocketTimeoutException
import java.net.UnknownHostException

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
    var updateManifestUrl by mutableStateOf(Prefs.updateManifestUrl); private set
    var installerDryRun by mutableStateOf(Prefs.installerDryRun); private set
    var installerWalkthroughSeen by mutableStateOf(Prefs.installerWalkthroughSeen); private set

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

    fun updateManifestUrl(value: String) {
        Prefs.updateManifestUrl = value
        updateManifestUrl = value
        onlineRelease = null
    }

    fun resetManifestUrl() = updateManifestUrl(Prefs.UPDATE_MANIFEST_DEFAULT)

    fun updateInstallerDryRun(value: Boolean) {
        Prefs.installerDryRun = value
        installerDryRun = value
    }

    fun markInstallerWalkthroughSeen() {
        Prefs.installerWalkthroughSeen = true
        installerWalkthroughSeen = true
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

    // Installer
    var inventory by mutableStateOf<Map<String, String>>(emptyMap()); private set
    var artifacts by mutableStateOf<List<String>>(emptyList()); private set
    var onlineRelease by mutableStateOf<OnlineRelease?>(null); private set
    var onlineError by mutableStateOf<String?>(null); private set
    var installerDistro by mutableStateOf("debian"); private set
    var installerHostname by mutableStateOf("determination"); private set
    var installerStopGuestOnExit by mutableStateOf(false); private set
    var installerStep by mutableStateOf<String?>(null); private set
    var installerPreviewComplete by mutableStateOf(false); private set

    // Software
    var pkgStatus by mutableStateOf<Map<String, String>>(emptyMap()); private set
    var guestUp by mutableStateOf(false); private set
    var compositor by mutableStateOf("phosh"); private set
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

    fun refreshInstaller() {
        if (rootState != RootState.GRANTED) return
        busy = "inventory"
        viewModelScope.launch(Dispatchers.IO) {
            inventory = Root.inventory()
            artifacts = Root.findArtifacts()
            busy = null
        }
    }

    fun checkOnlineUpdates() {
        if (busy != null) return
        busy = "online-check"
        onlineError = null
        viewModelScope.launch(Dispatchers.IO) {
            try {
                onlineRelease = ReleaseRepository.fetch(updateManifestUrl)
            } catch (e: Exception) {
                onlineRelease = null
                onlineError = releaseLookupError(e)
            }
            busy = null
        }
    }

    private fun releaseLookupError(error: Exception): String = when (error) {
        is UnknownHostException ->
            "The release host could not be reached. Check your connection, then try again."
        is SocketTimeoutException ->
            "The release host took too long to respond. Try again in a moment."
        is ReleaseHttpException -> when (error.statusCode) {
            404 -> "No qualified release is published yet. Verification mode is still available."
            else -> "The release host returned HTTP ${error.statusCode}. Try again later."
        }
        else -> error.message ?: "The release check failed. Try again in a moment."
    }

    fun selectInstallerDistro(id: String) {
        if (id in setOf("debian", "arch", "alpine") && busy == null) installerDistro = id
    }

    fun updateInstallerHostname(value: String) {
        installerHostname = value.lowercase().filter { it.isLetterOrDigit() || it == '-' }.take(63)
    }

    fun updateInstallerStopGuestOnExit(value: Boolean) {
        installerStopGuestOnExit = value
    }

    /**
     * Complete first-install transaction. Every downloaded byte is checked
     * against the release manifest before it crosses into the root-owned
     * staging directory. The boot partition is deliberately last.
     */
    fun installSelectedRelease(allowExperimental: Boolean = false) {
        if (rootState != RootState.GRANTED || busy != null) return
        val release = onlineRelease ?: run {
            onlineError = "Check for a complete installer release first"
            return
        }
        val deviceIds = inventory["device_ids"].csvSet() + listOfNotNull(inventory["device"])
        val abis = inventory["abis"].csvSet() + listOfNotNull(inventory["abi"])
        val fingerprint = inventory["fingerprint"].orEmpty()
        val distroInstalled = installerDistro in inventory["installed_distros"].csvSet()
        fun artifact(kind: UpdateArtifactKind, distro: String = ""): OnlineArtifact? =
            release.artifacts.firstOrNull {
                it.kind == kind && (distro.isBlank() || it.distro == distro) &&
                    it.supports(deviceIds, abis, fingerprint)
            }

        val module = artifact(UpdateArtifactKind.MODULE)
        val runtime = artifact(UpdateArtifactKind.RUNTIME)
        val rootfs = artifact(UpdateArtifactKind.ROOTFS, installerDistro)
        val boot = artifact(UpdateArtifactKind.BOOT)
        val missing = buildList {
            if (module == null) add("module")
            if (runtime == null) add("LXC runtime")
            if (rootfs == null && (!distroInstalled || installerDryRun)) add("$installerDistro rootfs")
            if (boot == null) add("boot image for this exact Android build")
        }
        if (missing.isNotEmpty()) {
            onlineError = "This release cannot install this device: missing ${missing.joinToString()}"
            return
        }
        if (rootfs?.support == ArtifactSupport.EXPERIMENTAL && !allowExperimental) {
            onlineError = "${rootfs.description.ifBlank { installerDistro }} is experimental and needs explicit confirmation"
            return
        }
        // Rootfs validation/extraction briefly needs the compressed app copy,
        // root staging copy, and expanded tree. Boot needs candidate, active
        // dump, repack output, and the user-visible recovery backup.
        val needed = (rootfs?.size ?: 0L) * 5 +
            listOfNotNull(module, runtime).sumOf { it.size } * 2 +
            (boot?.size ?: 0L) * 4
        val free = inventory["data_free"]?.toLongOrNull() ?: 0L
        if (free > 0 && needed > free) {
            onlineError = "Not enough free /data space. Need roughly ${formatBytes(needed)} including extraction and recovery; ${formatBytes(free)} is free."
            return
        }

        busy = "install-all"
        onlineError = null
        installerPreviewComplete = false
        viewModelScope.launch(Dispatchers.IO) {
            try {
                fun stage(a: OnlineArtifact): String {
                    installerStep = "Downloading ${a.name}"
                    val local = ReleaseRepository.download(getApplication(), a)
                    installerStep = "Verifying and staging ${a.name}"
                    val staged = Root.stageUpdate(local.absolutePath, a.name)
                    if (!staged.ok) error(staged.err.ifBlank { staged.out }.ifBlank { "root staging failed" })
                    return staged.out.lineSequence().lastOrNull { it.startsWith("/") }
                        ?: error("updater returned no staged path")
                }

                if (installerDryRun) {
                    installerStep = "Checking the module payload"
                    Root.validateModuleArchive(stage(module!!)).requireOk("module validation")
                    installerStep = "Checking the container runtime"
                    Root.validateRuntimeArchive(stage(runtime!!)).requireOk("runtime validation")
                    installerStep = "Checking the $installerDistro guest archive"
                    Root.validateGuestArchive(installerDistro, stage(rootfs!!)).requireOk("rootfs validation")
                    installerStep = "Repacking and checking recovery"
                    Root.flashBootImage(stage(boot!!), dryRun = true).requireOk("boot dry run")
                    installerStep = null
                    artifacts = Root.findArtifacts()
                    message = "Safety verification passed. Downloads and a verified boot backup were kept; nothing was installed or flashed."
                    busy = null
                    return@launch
                }

                val moduleCurrent = inventory["module_code"]?.toIntOrNull() == release.versionCode &&
                    inventory["module_state"] != "disabled" && inventory["toolkit"] == "yes"
                if (!moduleCurrent) {
                    installerStep = "Installing the root integration"
                    Root.installModuleZip(stage(module!!)).requireOk("module install")
                }
                installerStep = "Installing the container runtime"
                Root.installRuntimeArchive(stage(runtime!!)).requireOk("runtime install")

                if (!distroInstalled) {
                    installerStep = "Installing the $installerDistro guest"
                    Root.installGuestArchive(installerDistro, stage(rootfs!!)).requireOk("rootfs install")
                }
                installerStep = "Selecting and customising the guest"
                Root.activateGuestOffline(installerDistro).requireOk("guest activation")
                Root.configureInstall(installerHostname, installerStopGuestOnExit).requireOk("customization")

                installerStep = "Backing up and installing the kernel"
                Root.flashBootImage(stage(boot!!)).requireOk("boot install")
                inventory = Root.inventory()
                artifacts = Root.findArtifacts()
                installerStep = null
                rebootPrompt = "Determination ${release.version} is installed. Reboot to load the kernel and module; Android remains the default mode."
            } catch (e: Exception) {
                installerStep = null
                onlineError = e.message ?: "installation failed"
            }
            busy = null
        }
    }

    /** Manifest-free UI/progress rehearsal. It performs no I/O and no root calls. */
    fun runInstallerPreview() {
        if (busy != null) return
        busy = "install-preview"
        onlineError = null
        installerPreviewComplete = false
        viewModelScope.launch {
            listOf(
                "Checking root and device compatibility",
                "Resolving the exact Android build",
                "Verifying module and runtime payloads",
                "Preparing the selected Linux guest",
                "Repacking the Magisk boot image",
                "Verifying recovery and final state",
            ).forEach {
                installerStep = it
                delay(550)
            }
            installerStep = null
            busy = null
            installerPreviewComplete = true
            message = "Walkthrough complete. Your phone was left exactly as we found it."
        }
    }

    /** Download + verify + root-stage an artifact, then install safe artifact classes. */
    fun downloadOnlineArtifact(artifact: OnlineArtifact) {
        if (rootState != RootState.GRANTED || busy != null) return
        val deviceIds = inventory["device_ids"].csvSet() + listOfNotNull(inventory["device"])
        val abis = inventory["abis"].csvSet() + listOfNotNull(inventory["abi"])
        if (!artifact.supports(deviceIds, abis, inventory["fingerprint"].orEmpty())) {
            message = "${artifact.name} does not support ${inventory["device"] ?: "this device"} / ${inventory["abi"] ?: "this ABI"}"
            return
        }
        busy = "download-${artifact.kind.wireName}"
        onlineError = null
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val local = ReleaseRepository.download(getApplication(), artifact)
                val staged = Root.stageUpdate(local.absolutePath, artifact.name)
                if (!staged.ok) error(staged.err.ifBlank { staged.out }.ifBlank { "root staging failed" })
                val path = staged.out.lineSequence().lastOrNull { it.startsWith("/") }
                    ?: error("updater returned no staged path")
                artifacts = (listOf(path) + Root.findArtifacts()).distinct()
                when (artifact.kind) {
                    UpdateArtifactKind.MODULE -> {
                        val result = Root.installModuleZip(path)
                        if (!result.ok) error(result.err.ifBlank { result.out })
                        rebootPrompt = "Module ${onlineRelease?.version ?: "update"} installed. It takes effect on the next boot."
                    }
                    UpdateArtifactKind.COMPANION -> {
                        val result = Root.installApk(path)
                        if (!result.ok) error(result.err.ifBlank { result.out })
                        message = "Companion update installed"
                    }
                    UpdateArtifactKind.BOOT -> {
                        message = "Verified boot image downloaded. Review it under local updates before flashing."
                    }
                    UpdateArtifactKind.RUNTIME -> {
                        val result = Root.installRuntimeArchive(path)
                        if (!result.ok) error(result.err.ifBlank { result.out })
                        message = "Container runtime installed"
                    }
                    UpdateArtifactKind.ROOTFS -> {
                        message = "Verified ${artifact.distro.ifBlank { "guest" }} rootfs downloaded. Use the guided installer to install it."
                    }
                }
                inventory = Root.inventory()
            } catch (e: Exception) {
                onlineError = e.message ?: "download or install failed"
            }
            busy = null
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

    fun installModule(path: String) {
        busy = "module"
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.installModuleZip(path)
            if (r.ok) rebootPrompt = "Module installed. It takes effect on the next boot."
            else message = "Install failed: ${r.err.ifBlank { r.out }}"
            inventory = Root.inventory()
            busy = null
        }
    }

    fun flashBoot(path: String) {
        busy = "flash"
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.flashBootImage(path)
            if (r.ok) rebootPrompt = "Boot image flashed to the active slot."
            else message = "Flash failed: ${r.err.ifBlank { r.out }}"
            busy = null
        }
    }

    fun installApk(path: String) {
        busy = "apk"
        viewModelScope.launch(Dispatchers.IO) {
            val r = Root.installApk(path)
            message = if (r.ok) "App updated" else "APK install failed: ${r.err.ifBlank { r.out }}"
            busy = null
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

    private fun String?.csvSet(): Set<String> = this
        ?.split(',')
        ?.map { it.trim() }
        ?.filter { it.isNotBlank() }
        ?.toSet()
        .orEmpty()

    private fun Root.Result.requireOk(operation: String) {
        if (!ok) error("$operation failed: ${err.ifBlank { out }.ifBlank { "unknown error" }}")
    }

    private fun formatBytes(value: Long): String = when {
        value >= 1024L * 1024 * 1024 -> "%.1f GiB".format(value / (1024.0 * 1024 * 1024))
        else -> "%.0f MiB".format(value / (1024.0 * 1024))
    }
}
