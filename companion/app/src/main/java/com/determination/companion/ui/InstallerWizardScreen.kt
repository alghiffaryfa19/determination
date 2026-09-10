package com.determination.companion.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.NavigateNext
import androidx.compose.material.icons.rounded.Science
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.determination.companion.ArtifactSupport
import com.determination.companion.DetViewModel
import com.determination.companion.RootState
import com.determination.companion.UpdateArtifactKind
import kotlinx.coroutines.delay

private const val WIZARD_PAGES = 4

@Composable
fun InstallerWizardScreen(
    vm: DetViewModel,
    wide: Boolean,
    onClose: () -> Unit,
) {
    // A newly opened installer is a new journey. Restoring an old page here can
    // strand a first-run user on Review after an activity or APK restart.
    var page by remember { mutableIntStateOf(0) }
    var navigationReady by remember { mutableStateOf(false) }
    val busy = vm.busy != null
    LaunchedEffect(Unit) {
        // Prevent the tap that opened this full-screen route from landing on a
        // newly composed Continue button at the same coordinates.
        delay(350)
        navigationReady = true
    }

    AuroraBackground {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (page > 0) {
                    IconButton(
                        onClick = { page-- },
                        enabled = !busy,
                    ) {
                        Icon(Icons.Rounded.ArrowBack, "Back")
                    }
                } else {
                    Icon(
                        Icons.Rounded.Security,
                        null,
                        Modifier.padding(12.dp).size(28.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                Column(Modifier.weight(1f)) {
                    Text("Install Determination", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Step ${page + 1} of $WIZARD_PAGES · ${pageTitle(page)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = onClose, enabled = !busy) {
                    Icon(Icons.Rounded.Close, "Close installer")
                }
            }
            LinearProgressIndicator(
                progress = { (page + 1f) / WIZARD_PAGES },
                modifier = Modifier.fillMaxWidth().height(3.dp),
            )
            Box(
                Modifier.fillMaxSize(),
                contentAlignment = Alignment.TopCenter,
            ) {
                Column(
                    Modifier
                        .widthIn(max = if (wide) 820.dp else 640.dp)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    when (page) {
                        0 -> WelcomePage(vm)
                        1 -> DevicePage(vm)
                        2 -> CustomizePage(vm)
                        else -> ReviewPage(vm)
                    }

                    vm.installerStep?.let {
                        GlassCard {
                            Column(
                                Modifier.padding(18.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                LinearProgressIndicator(Modifier.fillMaxWidth())
                                Text(it, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }

                    Row(
                        Modifier.fillMaxWidth().padding(bottom = 24.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (page > 0) {
                            OutlinedButton(
                                onClick = { page-- },
                                enabled = !busy && navigationReady,
                                modifier = Modifier.weight(1f),
                            ) { Text("Back") }
                        }
                        if (page < WIZARD_PAGES - 1) {
                            Button(
                                onClick = { page++ },
                                enabled = !busy && navigationReady,
                                modifier = Modifier.weight(1f),
                            ) {
                                Text("Continue")
                                Spacer(Modifier.width(6.dp))
                                Icon(Icons.Rounded.NavigateNext, null, Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun pageTitle(page: Int): String = when (page) {
    0 -> "Welcome"
    1 -> "Device checks"
    2 -> "Linux setup"
    else -> "Ready"
}

@Composable
private fun WelcomePage(vm: DetViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(Icons.Rounded.Security, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
        Text("Your phone is about to grow a desktop.", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Determination keeps Android in charge and builds a full Linux environment alongside it. " +
                "Choose your distro, shape the system, and let the installer handle the dangerous parts with receipts.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        GlassCard {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("One phone. Two worlds. No ROM swap.", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Android remains the trusted boot and hardware layer. Determination adds a real Linux guest, " +
                        "GPU-accelerated desktop, native input hand-off and a clean route home.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                DetailRow("BOOT", "Backed up first · modified last · recoverable")
                DetailRow("LINUX", "A complete distro, not a terminal-shaped sandbox")
                DetailRow("HAND-OFF", "Android ↔ desktop without replacing your phone")
            }
        }
        GlassCard {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                WizardCheck("Root access", vm.rootState == RootState.GRANTED, when (vm.rootState) {
                    RootState.GRANTED -> "Granted through Magisk"
                    RootState.CHECKING -> "Waiting for Magisk"
                    RootState.DENIED -> "Grant access through Magisk to install"
                })
                WizardCheck(
                    "Current installation",
                    vm.inventory["toolkit"] == "yes",
                    if (vm.inventory["toolkit"] == "yes") "Determination is already present"
                    else "Ready for a fresh installation",
                )
            }
        }
    }
}

@Composable
private fun DevicePage(vm: DetViewModel) {
    val inv = vm.inventory
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("This phone", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Determination fingerprints the hardware, Android build, ABI and active slot before it touches anything. " +
                "If the release does not match this phone exactly, installation stays locked.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        GlassCard {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                DetailRow("Device", inv["device"] ?: "Reading…")
                DetailRow("Android build", inv["fingerprint"] ?: "Reading…")
                DetailRow("ABI", inv["abis"] ?: inv["abi"] ?: "Reading…")
                DetailRow("Active slot", inv["slot"] ?: "Unknown")
                DetailRow("Battery", inv["battery"]?.let { "$it%" } ?: "Unknown")
                DetailRow("Magisk", inv["magisk"] ?: "Not detected")
            }
        }
        OutlinedButton(onClick = vm::refreshInstaller, enabled = vm.busy == null) {
            Text("Run device checks again")
        }
    }
}

@Composable
private fun CustomizePage(vm: DetViewModel) {
    val published = vm.onlineRelease?.artifacts
        ?.filter { it.kind == UpdateArtifactKind.ROOTFS }
        ?.associateBy { it.distro }
        .orEmpty()
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Choose Linux", style = MaterialTheme.typography.headlineSmall)
        listOf(
            Triple("debian", "Debian + Phosh", "Polished, dependable and built for the full phone-to-desktop experience"),
            Triple("arch", "Arch Linux ARM", "Rolling-edge packages for people who enjoy holding the steering wheel"),
            Triple("alpine", "Alpine Linux", "Tiny, fast and unapologetically minimal"),
        ).forEach { (id, title, character) ->
            val artifact = published[id]
            val experimental = artifact?.support == ArtifactSupport.EXPERIMENTAL || id != "debian"
            GlassCard {
                Row(
                    Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = vm.installerDistro == id,
                        onClick = { vm.selectInstallerDistro(id) },
                        enabled = vm.busy == null,
                    )
                    Column(Modifier.weight(1f)) {
                        Text(title, fontWeight = FontWeight.SemiBold)
                        Text(
                            artifact?.description ?: "$character · ${if (experimental) "experimental" else "recommended"}",
                            style = MaterialTheme.typography.labelSmall,
                            color = if (experimental) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
        OutlinedTextField(
            value = vm.installerDisplayName,
            onValueChange = vm::updateInstallerDisplayName,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("Your name in Linux") },
            supportingText = { Text("Shown by the desktop; the stable login remains detuser.") },
        )
        OutlinedTextField(
            value = vm.installerHostname,
            onValueChange = vm::updateInstallerHostname,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("Linux hostname") },
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Stop guest after leaving Linux", fontWeight = FontWeight.SemiBold)
                Text(
                    "Lower idle memory use; slower next launch.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(
                checked = vm.installerStopGuestOnExit,
                onCheckedChange = vm::updateInstallerStopGuestOnExit,
            )
        }
    }
}

@Composable
private fun ReviewPage(vm: DetViewModel) {
    val release = vm.onlineRelease
    val realReady = release != null
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Ready when you are", style = MaterialTheme.typography.headlineSmall)
        GlassCard {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DetailRow("Distro", vm.installerDistro)
                DetailRow("User", vm.installerDisplayName.ifBlank { "Not set" })
                DetailRow("Hostname", vm.installerHostname)
                DetailRow("Release", release?.let { "${it.version} · ${it.channel}" } ?: "Awaiting first qualified release")
                DetailRow("Mode", if (realReady) {
                    if (vm.installerDryRun) "Verification run · no installation" else "Full installation"
                } else "Guided walkthrough")
            }
        }
        if (release == null) {
            Text(
                "The installer is ready; the first qualified release bundle is not published yet. " +
                    "You can still experience the complete journey and its hand-off sequence now.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            FilledTonalButton(
                onClick = vm::checkOnlineUpdates,
                enabled = vm.busy == null,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Rounded.CloudDownload, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Look for a release")
            }
            Button(
                onClick = vm::runInstallerPreview,
                enabled = vm.busy == null,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Rounded.Science, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Experience the installation")
            }
        } else {
            Button(
                onClick = vm::installSelectedRelease,
                enabled = vm.busy == null && vm.rootState == RootState.GRANTED,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Rounded.CheckCircle, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(if (vm.installerDryRun) "Run full safety verification" else "Install Determination")
            }
            OutlinedButton(
                onClick = vm::runInstallerPreview,
                enabled = vm.busy == null,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Explore the walkthrough") }
        }
        vm.onlineError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (vm.installerPreviewComplete) {
            GlassCard {
                Row(
                    Modifier.padding(18.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                    Text("Walkthrough complete. Your phone was left exactly as we found it.")
                }
            }
        }
    }
}

@Composable
private fun WizardCheck(title: String, ok: Boolean, detail: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            if (ok) Icons.Rounded.CheckCircle else Icons.Rounded.Science,
            null,
            tint = if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.tertiary,
        )
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        Text(value, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
    }
}
