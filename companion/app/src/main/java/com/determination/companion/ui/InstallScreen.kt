package com.determination.companion.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Android
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.determination.companion.BuildConfig
import com.determination.companion.DetViewModel
import com.determination.companion.RootState
import com.determination.companion.OnlineArtifact
import com.determination.companion.UpdateArtifactKind
import com.determination.companion.ArtifactSupport

@Composable
fun InstallScreen(
    vm: DetViewModel,
    wide: Boolean,
    onOpenInstaller: () -> Unit,
    modifier: Modifier = Modifier,
    bottomPad: Dp = 0.dp,
) {
    val inv = vm.inventory
    val busy = vm.busy != null
    val rootOk = vm.rootState == RootState.GRANTED

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 24.dp + bottomPad),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SectionLabel("Guided setup")
        GlassCard {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("New installation", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Turn a rooted Android phone into a complete Determination system, from compatibility checks to your chosen Linux desktop.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = onOpenInstaller, modifier = Modifier.fillMaxWidth()) {
                    Text("Open guided installer")
                }
            }
        }
        SectionLabel("This device")
        if (wide) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(Modifier.weight(1f)) { InventoryCard(inv) }
                Column(Modifier.weight(1f)) { OnlineUpdatesSection(vm, rootOk, busy) }
            }
        } else {
            InventoryCard(inv)
            OnlineUpdatesSection(vm, rootOk, busy)
        }
    }
}

@Composable
fun LocalUpdatesPanel(vm: DetViewModel) {
    var confirmFlash by remember { mutableStateOf<String?>(null) }
    var confirmFlashArmed by remember { mutableStateOf(false) }
    val inv = vm.inventory
    val busy = vm.busy != null
    val rootOk = vm.rootState == RootState.GRANTED

    ArtifactsSection(vm, rootOk, busy) { confirmFlash = it }

    confirmFlash?.let { path ->
        AlertDialog(
            onDismissRequest = { confirmFlash = null; confirmFlashArmed = false },
            icon = { Icon(Icons.Rounded.Warning, null, tint = MaterialTheme.colorScheme.error) },
            title = { Text(if (confirmFlashArmed) "Really flash boot?" else "Flash boot image?") },
            text = {
                Text(
                    if (!confirmFlashArmed)
                        "This writes\n$path\nto the active boot partition. A bad image can " +
                            "brick the phone until a fastboot restore. The image header is " +
                            "verified (ANDROID! magic) before writing."
                    else
                        "Second confirmation. Keep the USB cable handy for fastboot recovery. " +
                            "Flash ${path.substringAfterLast('/')} to boot${inv["slot"] ?: ""} now?",
                )
            },
            confirmButton = {
                Button(
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                    onClick = {
                        if (!confirmFlashArmed) confirmFlashArmed = true
                        else {
                            vm.flashBoot(path)
                            confirmFlash = null
                            confirmFlashArmed = false
                        }
                    },
                ) { Text(if (confirmFlashArmed) "Flash now" else "Continue") }
            },
            dismissButton = {
                TextButton(onClick = { confirmFlash = null; confirmFlashArmed = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun OnlineUpdatesSection(vm: DetViewModel, rootOk: Boolean, busy: Boolean) {
    val release = vm.onlineRelease
    val deviceIds = vm.inventory["device_ids"].csvSet() + listOfNotNull(vm.inventory["device"])
    val abis = vm.inventory["abis"].csvSet() + listOfNotNull(vm.inventory["abi"])
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel("Online updates")
        GlassCard {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (release == null) {
                    Text(
                        "Fetch a small release manifest, then download verified artifacts directly. No file juggling required.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(
                        onClick = vm::checkOnlineUpdates,
                        enabled = rootOk && !busy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Rounded.Refresh, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (vm.busy == "online-check") "Checking…" else "Check online")
                    }
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.CloudDownload, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                "v${release.version} “${release.codename}”",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                "${release.channel} · build ${release.versionCode}" +
                                    release.publishedAt.takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty(),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(onClick = vm::checkOnlineUpdates, enabled = !busy) { Text("Refresh") }
                    }
                    release.artifacts.forEach { artifact ->
                        OnlineArtifactRow(
                            artifact = artifact,
                            compatible = artifact.supports(
                                deviceIds,
                                abis,
                                vm.inventory["fingerprint"].orEmpty(),
                            ),
                            busy = busy,
                            onInstall = { vm.downloadOnlineArtifact(artifact) },
                        )
                    }
                }
                vm.onlineError?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
}

private fun String?.csvSet(): Set<String> = this
    ?.split(',')
    ?.map { it.trim() }
    ?.filter { it.isNotBlank() }
    ?.toSet()
    .orEmpty()

@Composable
private fun GuidedInstallerSection(vm: DetViewModel, rootOk: Boolean, busy: Boolean) {
    val release = vm.onlineRelease ?: return
    val deviceIds = vm.inventory["device_ids"].csvSet() + listOfNotNull(vm.inventory["device"])
    val abis = vm.inventory["abis"].csvSet() + listOfNotNull(vm.inventory["abi"])
    val fingerprint = vm.inventory["fingerprint"].orEmpty()
    val rootfs = release.artifacts.filter {
        it.kind == UpdateArtifactKind.ROOTFS && it.distro.isNotBlank() &&
            it.supports(deviceIds, abis, fingerprint)
    }
    val selected = rootfs.firstOrNull { it.distro == vm.installerDistro }
    val complete = release.artifacts.any {
        it.kind == UpdateArtifactKind.MODULE && it.supports(deviceIds, abis, fingerprint)
    } && release.artifacts.any {
        it.kind == UpdateArtifactKind.RUNTIME && it.supports(deviceIds, abis, fingerprint)
    } && selected != null && release.artifacts.any {
        it.kind == UpdateArtifactKind.BOOT && it.supports(deviceIds, abis, fingerprint)
    }
    var confirmExperimental by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel("Guided installation")
        GlassCard {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(
                    "From rooted Android to a bootable Linux guest. The installer verifies every download, " +
                        "keeps the current Magisk ramdisk, backs up boot, and writes the boot partition last.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (vm.installerDryRun) {
                    Text(
                        "VERIFICATION MODE · Every artifact and recovery step will be proven against this phone. " +
                            "The installed system and boot partition stay untouched.",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                Text("Choose a distro", style = MaterialTheme.typography.titleSmall)
                rootfs.forEach { artifact ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(
                            selected = vm.installerDistro == artifact.distro,
                            onClick = { vm.selectInstallerDistro(artifact.distro) },
                            enabled = !busy,
                        )
                        Column(Modifier.weight(1f)) {
                            Text(
                                when (artifact.distro) {
                                    "debian" -> "Debian + Phosh"
                                    "arch" -> "Arch Linux ARM"
                                    "alpine" -> "Alpine Linux"
                                    else -> artifact.distro
                                },
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Text(
                                artifact.description.ifBlank {
                                    if (artifact.support == ArtifactSupport.QUALIFIED) "Device-qualified"
                                    else "Experimental"
                                },
                                style = MaterialTheme.typography.labelSmall,
                                color = if (artifact.support == ArtifactSupport.EXPERIMENTAL)
                                    MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                if (rootfs.isEmpty()) {
                    Text(
                        "This release has no compatible guest images.",
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                OutlinedTextField(
                    value = vm.installerHostname,
                    onValueChange = vm::updateInstallerHostname,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !busy,
                    singleLine = true,
                    label = { Text("Linux hostname") },
                    supportingText = { Text("Shown on the network and in the terminal") },
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Stop guest after leaving Linux", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Saves RAM and background wakeups; the next launch takes longer.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = vm.installerStopGuestOnExit,
                        onCheckedChange = vm::updateInstallerStopGuestOnExit,
                        enabled = !busy,
                    )
                }

                vm.installerStep?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                }
                Button(
                    onClick = {
                        if (selected?.support == ArtifactSupport.EXPERIMENTAL) confirmExperimental = true
                        else vm.installSelectedRelease()
                    },
                    enabled = rootOk && !busy && complete && vm.installerHostname.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        when {
                            vm.busy == "install-all" && vm.installerDryRun -> "Running checks…"
                            vm.busy == "install-all" -> "Installing…"
                            vm.installerDryRun -> "Run full safety verification"
                            else -> "Install Determination"
                        },
                    )
                }
                if (!complete) {
                    Text(
                        "This manifest is update-only or does not match the exact device and Android build. Installation is blocked.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }

    if (confirmExperimental) {
        AlertDialog(
            onDismissRequest = { confirmExperimental = false },
            icon = { Icon(Icons.Rounded.Warning, null) },
            title = { Text(if (vm.installerDryRun) "Check experimental distro?" else "Install experimental distro?") },
            text = {
                Text(
                    "${selected?.description.orEmpty()} The archive and boot path are installable, but graphics, input, audio, and recovery have not passed the full device gate.",
                )
            },
            confirmButton = {
                Button(onClick = {
                    confirmExperimental = false
                    vm.installSelectedRelease(allowExperimental = true)
                }) { Text(if (vm.installerDryRun) "Run checks" else "Install experiment") }
            },
            dismissButton = {
                TextButton(onClick = { confirmExperimental = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun OnlineArtifactRow(
    artifact: OnlineArtifact,
    compatible: Boolean,
    busy: Boolean,
    onInstall: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(artifact.name, style = MaterialTheme.typography.titleSmall)
            val sizeMiB = artifact.size.toDouble() / (1024.0 * 1024.0)
            Text(
                "${artifact.kind.wireName} · ${"%.1f".format(sizeMiB)} MiB" +
                    if (compatible) " · compatible" else " · not for this device",
                style = MaterialTheme.typography.labelSmall,
                color = if (compatible) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.error,
            )
        }
        Spacer(Modifier.width(10.dp))
        FilledTonalButton(enabled = compatible && !busy, onClick = onInstall) {
            Text(
                when (artifact.kind) {
                    UpdateArtifactKind.BOOT, UpdateArtifactKind.ROOTFS -> "Download"
                    else -> "Install"
                },
            )
        }
    }
}

@Composable
private fun InventoryCard(inv: Map<String, String>) {
    val expectedModuleVersion = "v${BuildConfig.VERSION_NAME}"
    val moduleVersion = inv["module_ver"]?.takeIf { it.isNotBlank() }
    val moduleEnabled = moduleVersion != null && inv["module_state"] != "disabled"
    val moduleMatches = moduleVersion == expectedModuleVersion &&
        inv["module_code"]?.toIntOrNull() == BuildConfig.VERSION_CODE

    GlassCard {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            InventoryRow(
                Icons.Rounded.Memory, "Kernel",
                inv["kernel"] ?: "?",
                ok = inv["det_kernel"] == "yes",
                okText = "Determination kernel", badText = "stock kernel : flash needed",
            )
            InventoryRow(
                Icons.Rounded.Archive, "Magisk module",
                moduleVersion
                    ?.let { "$it (${inv["module_code"] ?: "?"})" } ?: "not installed",
                ok = moduleEnabled && moduleMatches,
                okText = "matches this app",
                badText = when {
                    inv["module_state"] == "disabled" -> "disabled"
                    moduleVersion == null -> "missing"
                    else -> "different release"
                },
            )
            InventoryRow(
                Icons.Rounded.Storage, "Guest rootfs",
                inv["guest"]?.takeIf { it.isNotBlank() } ?: "not found",
                ok = !inv["guest"].isNullOrBlank(),
                okText = "present", badText = "missing",
            )
            InventoryRow(
                Icons.Rounded.Android, "Companion app",
                "v${BuildConfig.VERSION_NAME} “${BuildConfig.RELEASE_CODENAME}” (${BuildConfig.VERSION_CODE})",
                ok = true, okText = "this app", badText = "",
            )
            val slot = inv["slot"]
            if (!slot.isNullOrBlank()) {
                Text(
                    "Active slot $slot  ·  ${inv["boot_part"] ?: ""}",
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun InventoryRow(
    icon: ImageVector,
    title: String,
    value: String,
    ok: Boolean,
    okText: String,
    badText: String,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(
                value,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            if (ok) Icons.Rounded.CheckCircle else Icons.Rounded.ErrorOutline,
            if (ok) okText else badText,
            Modifier.size(20.dp),
            tint = if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
        )
    }
}

@Composable
private fun ArtifactsSection(
    vm: DetViewModel,
    rootOk: Boolean,
    busy: Boolean,
    onFlash: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            "Online downloads appear here. Manual files can also be staged in Download or /data/local/tmp while in phone mode.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (vm.artifacts.isEmpty()) {
            GlassCard {
                Text(
                    "Nothing found.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(20.dp),
                )
            }
        }
        vm.artifacts.forEach { path ->
            val name = path.substringAfterLast('/')
            GlassCard {
                Row(
                    Modifier.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(name, style = MaterialTheme.typography.titleSmall)
                        Text(
                            path.substringBeforeLast('/'),
                            style = MaterialTheme.typography.labelSmall,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.width(10.dp))
                    when {
                        name.endsWith(".zip") -> FilledTonalButton(
                            enabled = rootOk && !busy,
                            onClick = { vm.installModule(path) },
                        ) { Text("Install") }
                        name.endsWith(".img") -> FilledTonalButton(
                            enabled = rootOk && !busy,
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer,
                                contentColor = MaterialTheme.colorScheme.onErrorContainer,
                            ),
                            onClick = { onFlash(path) },
                        ) { Text("Flash") }
                        name.endsWith(".apk") -> FilledTonalButton(
                            enabled = rootOk && !busy,
                            onClick = { vm.installApk(path) },
                        ) { Text("Update") }
                    }
                }
            }
        }
    }
}
