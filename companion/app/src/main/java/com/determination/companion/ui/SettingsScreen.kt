package com.determination.companion.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.rounded.Build
import androidx.compose.material.icons.rounded.DesktopWindows
import androidx.compose.material.icons.rounded.Healing
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.SystemUpdateAlt
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.determination.companion.DetViewModel
import com.determination.companion.Prefs
import com.determination.companion.Root
import com.determination.companion.RootState

/** Poll choices: label to seconds (0 = manual refresh only). */
private val POLL_CHOICES = listOf("5 s" to 5, "15 s" to 15, "60 s" to 60, "Off" to 0)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen(
    vm: DetViewModel,
    onOpenInstaller: () -> Unit,
    modifier: Modifier = Modifier,
    bottomPad: Dp = 0.dp,
) {
    val rootOk = vm.rootState == RootState.GRANTED
    val desktop = vm.status["mode"] == "desktop"
    val installed = vm.status["installed"] == "yes"
    val guestRunning = vm.status["guest"] == "running"
    val busy = vm.busy != null
    val haptics = LocalHapticFeedback.current

    var externalExpanded by remember { mutableStateOf(vm.externalDisplay.enabled) }
    var buttonsExpanded by remember { mutableStateOf(false) }
    var localUpdatesExpanded by remember { mutableStateOf(false) }
    var maintenanceExpanded by remember { mutableStateOf(false) }
    var diagnosticsExpanded by remember { mutableStateOf(false) }
    var advancedExpanded by remember { mutableStateOf(false) }
    var confirmPower by remember { mutableStateOf<String?>(null) }

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 24.dp + bottomPad),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // (dog check: 20 pets and the battery section briefly smells of chips)
        var pets by remember { mutableIntStateOf(0) }
        Text(
            "DESKTOP BEHAVIOR",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
            letterSpacing = MaterialTheme.typography.labelMedium.letterSpacing * 2,
            modifier = Modifier
                .padding(top = 10.dp, bottom = 2.dp)
                .combinedClickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = {
                        if (++pets == 20) {
                            pets = 0
                            vm.message = "* (You pet the battery. It was not a dog.)"
                        }
                    },
                ),
        )

        GlassCard {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                SettingRow(
                    title = "Stop guest after desktop mode",
                    blurb = "Saves memory and battery; the next desktop start takes longer.",
                    checked = vm.stopGuestOnExit,
                    enabled = rootOk,
                    onChange = vm::updateStopGuestOnExit,
                )
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Live status polling", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "How often this app refreshes while it is open.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        POLL_CHOICES.forEach { (label, secs) ->
                            FilterChip(
                                selected = vm.pollSeconds == secs,
                                onClick = { vm.updatePollSeconds(secs) },
                                label = { Text(label) },
                            )
                        }
                    }
                }
            }
        }

        SectionLabel("Input & display")
        ExpandableSettingsCard(
            title = "External display",
            summary = "Renderer selection and test output",
            icon = Icons.Rounded.DesktopWindows,
            expanded = externalExpanded,
            onClick = { externalExpanded = !externalExpanded },
        ) {
            ExternalDisplaySettings(vm, rootOk, installed, busy)
        }
        ExpandableSettingsCard(
            title = "Hardware buttons",
            summary = if (vm.hardwareButtons.isEmpty()) "Volume, media, and spare keys"
            else "${vm.hardwareButtons.size} remappable buttons",
            icon = Icons.Rounded.Keyboard,
            expanded = buttonsExpanded,
            onClick = {
                buttonsExpanded = !buttonsExpanded
                if (buttonsExpanded && vm.hardwareButtons.isEmpty()) vm.refreshHardwareButtons()
            },
        ) {
            HardwareButtonSettings(vm, busy)
        }

        SectionLabel("System")
        GlassCard {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Guided installer", style = MaterialTheme.typography.titleSmall)
                Text(
                    "Compatibility checks, distro selection and complete device setup in one focused journey.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                FilledTonalButton(
                    onClick = onOpenInstaller,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Open guided installer") }
            }
        }
        ExpandableSettingsCard(
            title = "Local updates",
            summary = if (vm.artifacts.isEmpty()) "No staged files"
            else "${vm.artifacts.size} staged artifact(s)",
            icon = Icons.Rounded.SystemUpdateAlt,
            expanded = localUpdatesExpanded,
            onClick = { localUpdatesExpanded = !localUpdatesExpanded },
        ) {
            Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp)) {
                LocalUpdatesPanel(vm)
            }
        }
        ExpandableSettingsCard(
            title = "Maintenance",
            summary = "Guest recovery and phone power",
            icon = Icons.Rounded.Build,
            expanded = maintenanceExpanded,
            onClick = { maintenanceExpanded = !maintenanceExpanded },
        ) {
            MaintenanceSettings(
                vm = vm,
                rootOk = rootOk,
                installed = installed,
                desktop = desktop,
                guestRunning = guestRunning,
                busy = busy,
                onPower = { confirmPower = it },
            )
        }
        ExpandableSettingsCard(
            title = "Diagnostics",
            summary = "${vm.logs.size} service logs",
            icon = Icons.AutoMirrored.Rounded.Article,
            expanded = diagnosticsExpanded,
            onClick = { diagnosticsExpanded = !diagnosticsExpanded },
        ) {
            Column(
                Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                vm.logs.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { LogChip(it, vm) }
                    }
                }
            }
        }
        ExpandableSettingsCard(
            title = "Advanced",
            summary = "Update mirrors and development channels",
            icon = Icons.Rounded.Tune,
            expanded = advancedExpanded,
            onClick = { advancedExpanded = !advancedExpanded },
        ) {
            Column(
                Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SettingRow(
                    title = "Verification mode",
                    blurb = "Prove the complete release and recovery path without installing or flashing.",
                    checked = vm.installerDryRun,
                    enabled = !busy,
                    onChange = vm::updateInstallerDryRun,
                )
                Text("Update source", style = MaterialTheme.typography.titleSmall)
                Text(
                    "HTTPS manifest packaged by the distributor, a mirror, or a self-hosted channel.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = vm.updateManifestUrl,
                    onValueChange = vm::updateManifestUrl,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    label = { Text("Manifest URL") },
                )
                OutlinedButton(
                    onClick = vm::resetManifestUrl,
                    enabled = vm.updateManifestUrl != Prefs.UPDATE_MANIFEST_DEFAULT,
                ) { Text("Use packaged source") }
            }
        }
    }

    confirmPower?.let { which ->
        AlertDialog(
            onDismissRequest = { confirmPower = null },
            icon = { Icon(Icons.Rounded.Warning, null) },
            title = { Text(if (which == "reboot") "Reboot the phone?" else "Power off the phone?") },
            text = { Text("This affects the whole phone, not just the Linux guest.") },
            confirmButton = {
                Button(
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                    onClick = {
                        confirmPower = null
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        vm.act("power", refreshAfter = false) {
                            if (which == "reboot") Root.rebootPhone() else Root.powerOff()
                        }
                    },
                ) { Text(if (which == "reboot") "Reboot" else "Power off") }
            },
            dismissButton = { TextButton(onClick = { confirmPower = null }) { Text("Cancel") } },
        )
    }
}

@Composable
fun ExpandableSettingsCard(
    title: String,
    summary: String,
    icon: ImageVector,
    expanded: Boolean,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    GlassCard {
        Column {
            ExpandableControlHeader(title, summary, icon, expanded, onClick)
            AnimatedExpand(expanded) { content() }
        }
    }
}

@Composable
private fun ExternalDisplaySettings(
    vm: DetViewModel,
    rootOk: Boolean,
    installed: Boolean,
    busy: Boolean,
) {
    val external = vm.externalDisplay
    Column(
        Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            "Auto is the portable default. Force a backend only for compatibility testing.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (external.error.isNotBlank()) Text(external.error, color = MaterialTheme.colorScheme.error)
        Text("Renderer", style = MaterialTheme.typography.labelMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            listOf("auto" to "Auto", "zink" to "Zink", "turnip-zink" to "Turnip").forEach { (id, label) ->
                FilterChip(
                    selected = vm.externalRenderer == id,
                    onClick = { vm.selectExternalRenderer(id) },
                    enabled = !busy,
                    label = { Text(label) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
        OutlinedButton(
            onClick = vm::runExternalTest,
            enabled = rootOk && installed && !busy && external.socketReady,
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Show test pattern") }
    }
}

@Composable
private fun HardwareButtonSettings(vm: DetViewModel, busy: Boolean) {
    Column(
        Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Desktop mappings", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            TextButton(onClick = vm::refreshHardwareButtons, enabled = !busy) { Text("Rescan") }
        }
        if (vm.hardwareButtons.isEmpty()) {
            Text(
                if (vm.busy == "buttons") "Reading input capabilities…" else "No remappable buttons found",
                style = MaterialTheme.typography.bodyMedium,
            )
        } else {
            vm.hardwareButtons.forEach { button ->
                val action = vm.inputMappings[button.code] ?: "default"
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(button.label, style = MaterialTheme.typography.bodyMedium)
                        Text(
                            "${button.code} · ${button.devices.joinToString()}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    AssistChip(
                        onClick = { vm.cycleHardwareButton(button.code) },
                        enabled = !busy,
                        label = { Text(actionLabel(action)) },
                    )
                }
            }
        }
    }
}

private fun actionLabel(action: String): String = when (action) {
    "volume-up" -> "Volume +"
    "volume-down" -> "Volume −"
    "mute" -> "Mute"
    "play-pause" -> "Play / pause"
    "next" -> "Next"
    "previous" -> "Previous"
    "exit-desktop" -> "Exit desktop"
    else -> "System default"
}

@Composable
private fun MaintenanceSettings(
    vm: DetViewModel,
    rootOk: Boolean,
    installed: Boolean,
    desktop: Boolean,
    guestRunning: Boolean,
    busy: Boolean,
    onPower: (String) -> Unit,
) {
    Column(
        Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilledTonalButton(
            onClick = { vm.act("guest") { Root.restartGuest() } },
            enabled = rootOk && installed && !desktop && !busy,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Rounded.RestartAlt, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Restart guest container")
        }
        OutlinedButton(
            onClick = vm::stopGuestNow,
            enabled = rootOk && guestRunning && !busy,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Rounded.PowerSettingsNew, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (guestRunning) "Stop guest container" else "Guest already stopped")
        }
        OutlinedButton(
            onClick = { vm.act("recover") { Root.recoverDesktop() } },
            enabled = rootOk && desktop && !busy,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Rounded.Healing, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Recover desktop session")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { onPower("reboot") },
                enabled = rootOk && !busy,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Rounded.RestartAlt, null, Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Reboot")
            }
            OutlinedButton(
                onClick = { onPower("poweroff") },
                enabled = rootOk && !busy,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Rounded.PowerSettingsNew, null, Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Power off")
            }
        }
    }
}

@Composable
private fun SettingRow(
    title: String,
    blurb: String,
    checked: Boolean,
    enabled: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(
                blurb,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}
