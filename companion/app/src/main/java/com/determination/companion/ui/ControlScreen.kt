package com.determination.companion.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.DesktopWindows
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Healing
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.Smartphone
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.determination.companion.DetViewModel
import com.determination.companion.Root
import com.determination.companion.RootState
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ControlScreen(
    vm: DetViewModel,
    wide: Boolean,
    modifier: Modifier = Modifier,
    bottomPad: Dp = 0.dp,
) {
    var confirmEnter by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    val s = vm.status
    val desktop = s["mode"] == "desktop"
    val installed = s["installed"] == "yes"
    val rootOk = vm.rootState == RootState.GRANTED
    val busy = vm.busy != null

    // Live status: quiet re-poll while this screen is visible. Period comes
    // from Settings (0 = manual only) : each poll is a root round-trip.
    val pollSec = vm.pollSeconds
    LaunchedEffect(rootOk, pollSec) {
        while (rootOk && pollSec > 0) {
            delay(pollSec * 1000L)
            vm.refreshQuiet()
        }
    }

    if (rootOk && s.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { LoadingIndicator() }
        return
    }

    PullToRefreshBox(
        isRefreshing = vm.busy == "status",
        onRefresh = { vm.refresh() },
        modifier = modifier,
    ) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp + bottomPad),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (vm.rootState == RootState.DENIED) {
                GlassCard {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Root required", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "This app drives Determination through Magisk su. Open Magisk → " +
                                "Superuser and grant Determination (screen must be unlocked), then retry.",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        FilledTonalButton(onClick = { vm.refresh() }) { Text("Retry") }
                    }
                }
                return@Column
            }

            if (wide) {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Column(Modifier.weight(1f)) { StatusCard(vm, desktop) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        DesktopActions(vm, desktop, installed, rootOk, busy) {
                            confirmEnter = true
                        }
                    }
                }
            } else {
                StatusCard(vm, desktop)
                DesktopActions(vm, desktop, installed, rootOk, busy) {
                    confirmEnter = true
                }
            }

            SectionLabel("External desktop")
            ExternalDesktopCard(vm, rootOk, installed, busy)

        }
    }

    if (confirmEnter) {
        AlertDialog(
            onDismissRequest = { confirmEnter = false },
            icon = { Icon(Icons.Rounded.DesktopWindows, null) },
            title = { Text("Enter desktop mode?") },
            text = {
                Text(
                    "The phone UI hands the panel to the Linux desktop. To come back, use " +
                        "“Exit to Phone Mode” inside the desktop, or the power menu.",
                )
            },
            confirmButton = {
                Button(onClick = {
                    confirmEnter = false
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    vm.act("enter", refreshAfter = false) { Root.enterDesktop() }
                }) { Text("Enter") }
            },
            dismissButton = { TextButton(onClick = { confirmEnter = false }) { Text("Cancel") } },
        )
    }

}

@Composable
private fun ModeBadge(desktop: Boolean) {
    val color by animateColorAsState(
        targetValue = if (desktop) MaterialTheme.colorScheme.tertiaryContainer
        else MaterialTheme.colorScheme.primaryContainer,
        animationSpec = tween(240),
        label = "mode badge color",
    )
    Box(
        Modifier
            .size(48.dp)
            .clip(MaterialTheme.shapes.large)
            .background(color),
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(
            targetState = desktop,
            transitionSpec = { fadeIn(tween(150)) togetherWith fadeOut(tween(90)) },
            label = "mode icon",
        ) { isDesktop ->
            Icon(
                if (isDesktop) Icons.Rounded.DesktopWindows else Icons.Rounded.Smartphone,
                null,
                Modifier.size(24.dp),
                tint = if (isDesktop) MaterialTheme.colorScheme.onTertiaryContainer
                else MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun StatusCard(vm: DetViewModel, desktop: Boolean) {
    val s = vm.status
    GlassCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ModeBadge(desktop)
                Spacer(Modifier.width(16.dp))
                Column {
                    Text(
                        if (desktop) "Desktop mode" else "Phone mode",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        if (s["installed"] == "yes") "Determination installed"
                        else "Not installed : see the Install tab",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (s["control"] == "bridge") {
                        Text(
                            when {
                                s["recovery"] == "true" -> "Recovery required"
                                !s["transition"].isNullOrBlank() -> "Transition: ${s["transition"]}"
                                else -> "Structured control connected"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = if (s["recovery"] == "true") MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(Modifier.height(2.dp))
            StatusRow(
                "Guest",
                (s["guest"] ?: "?") + (s["ip"]?.takeIf { it.isNotBlank() }?.let { "  ·  $it" } ?: ""),
                good = s["guest"] == "running",
            )
            StatusRow(
                "SurfaceFlinger", s["sf"] ?: "?",
                // In desktop mode a STOPPED SF is the healthy state.
                good = if (desktop) s["sf"] == "stopped" else s["sf"] == "running",
            )
            StatusRow("Host agent", s["agent"] ?: "?", good = s["agent"] == "up")
            val batt = s["batt"]?.toIntOrNull()
            if (batt != null) {
                val charging = s["battstat"]?.contains("harging") == true
                val low = batt <= 15 && !charging
                Spacer(Modifier.height(2.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (charging) {
                        Icon(
                            Icons.Rounded.Bolt, "charging",
                            Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Text(
                        // (only ever visible at exactly 1% : you cannot give up just yet)
                        if (batt == 1 && !charging) "* But it refused.  ·  1%"
                        else "Battery  $batt%  ·  ${s["battmv"] ?: "?"} mV  ·  ${s["battstat"] ?: ""}",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (low) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                LinearWavyProgressIndicator(
                    progress = { batt / 100f },
                    color = if (low) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.primary,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun StatusRow(label: String, value: String, good: Boolean?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(118.dp),
        )
        if (good != null) {
            Box(
                Modifier
                    .size(8.dp)
                    .clip(MaterialTheme.shapes.small)
                    .background(
                        if (good) Color(0xFF54B87B)
                        else MaterialTheme.colorScheme.error,
                    ),
            )
            Spacer(Modifier.width(8.dp))
        }
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
        )
    }
}

@Composable
private fun DesktopActions(
    vm: DetViewModel,
    desktop: Boolean,
    installed: Boolean,
    rootOk: Boolean,
    busy: Boolean,
    onEnter: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!desktop) {
            Button(
                onClick = onEnter,
                enabled = rootOk && installed && !busy,
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) {
                Icon(Icons.Rounded.DesktopWindows, null)
                Spacer(Modifier.width(8.dp))
                Text("Enter Desktop Mode", style = MaterialTheme.typography.titleMedium)
            }
        } else {
            Button(
                onClick = { vm.act("exit") { Root.exitDesktop() } },
                enabled = rootOk && !busy,
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) {
                Icon(Icons.Rounded.Smartphone, null)
                Spacer(Modifier.width(8.dp))
                Text("Exit Desktop Mode", style = MaterialTheme.typography.titleMedium)
            }
            FilledTonalButton(
                onClick = { vm.act("recover") { Root.recoverDesktop() } },
                enabled = rootOk && !busy,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Rounded.Healing, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Recover desktop (restart phoc)")
            }
        }
    }
}

@Composable
private fun ExternalDesktopCard(
    vm: DetViewModel,
    rootOk: Boolean,
    installed: Boolean,
    busy: Boolean,
) {
    val external = vm.externalDisplay
    GlassCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Rounded.DesktopWindows,
                    null,
                    Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        when (external.phase) {
                            "ready" -> "External desktop ready"
                            "waiting" -> "Waiting for DisplayPort"
                            "starting" -> "Starting presenter…"
                            "error" -> "Presenter error"
                            else -> "External desktop is off"
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        if (external.displayConnected) {
                            "${external.displayName} · ${external.width}×${external.height} · " +
                                "${"%.1f".format(external.refreshRate)} Hz"
                        } else {
                            "Connect a USB-C DisplayPort display"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (external.error.isNotBlank()) {
                Text(external.error, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = {
                        if (external.enabled) vm.stopExternalPresenter() else vm.startExternalPresenter()
                    },
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                ) { Text(if (external.enabled) "Stop presenter" else "Start presenter") }
                Button(
                    onClick = vm::runExternalPlasma,
                    enabled = rootOk && installed && !busy && external.socketReady,
                    modifier = Modifier.weight(1f),
                ) { Text("Open desktop") }
            }
            FilledTonalButton(
                onClick = vm::toggleExternalInput,
                enabled = rootOk && installed && !busy &&
                    (external.socketReady || vm.externalInputCaptured),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Rounded.Keyboard, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    if (vm.externalInputCaptured) "Release external input"
                    else "Capture keyboard, mouse & touch",
                )
            }
        }
    }
}

@Composable
fun ExpandableControlHeader(
    title: String,
    summary: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    expanded: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.large)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(
                summary,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        AnimatedChevron(expanded)
    }
}

@Composable
fun AnimatedExpand(
    visible: Boolean,
    content: @Composable () -> Unit,
) {
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(tween(140)) + expandVertically(
            animationSpec = spring(
                dampingRatio = Spring.DampingRatioNoBouncy,
                stiffness = Spring.StiffnessMediumLow,
            ),
            expandFrom = Alignment.Top,
        ),
        exit = fadeOut(tween(100)) + shrinkVertically(
            animationSpec = tween(180),
            shrinkTowards = Alignment.Top,
        ),
    ) {
        content()
    }
}

@Composable
fun AnimatedChevron(expanded: Boolean, modifier: Modifier = Modifier) {
    val rotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "section chevron",
    )
    Icon(
        Icons.Rounded.ExpandMore,
        null,
        modifier.graphicsLayer { rotationZ = rotation },
    )
}

@Composable
fun LogChip(name: String, vm: DetViewModel) {
    AssistChip(
        onClick = { vm.openLog(name) },
        label = { Text(name.removeSuffix(".log")) },
        leadingIcon = { Icon(Icons.AutoMirrored.Rounded.Article, null, Modifier.size(16.dp)) },
    )
}

@Composable
fun SectionLabel(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
        letterSpacing = MaterialTheme.typography.labelMedium.letterSpacing * 2,
        modifier = Modifier.padding(top = 10.dp, bottom = 2.dp),
    )
}

@Composable
fun GlassCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(
            containerColor = glassColor(),
            contentColor = MaterialTheme.colorScheme.onSurface,
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) { content() }
}
