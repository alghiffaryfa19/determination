@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
)

package com.aurora.companion.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.aurora.companion.AuroraViewModel
import com.aurora.companion.EnvInstall
import com.aurora.companion.RootState
import kotlinx.coroutines.delay

/**
 * Desktop environments: what the guest can run, and what installing one means
 * for this device. Everything shown comes from the device's session manifests.
 */
@Composable
fun EnvironmentSection(vm: AuroraViewModel) {
    val catalog = vm.envCatalog
    val run = vm.envRun
    val busy = vm.envBusy != null
    var confirming by remember { mutableStateOf<EnvInstall.Environment?>(null) }

    LaunchedEffect(run?.state) {
        if (run?.active == true) {
            while (true) {
                delay(2_000)
                vm.pollEnvironments()
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel("Desktop environment")
        Text(
            "What desktop mode runs. Installing an environment pulls the packages " +
                "the guest's own package manager provides; components Aurora builds " +
                "from source stay a separate, explicit step.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (catalog == null) {
            GlassCard {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        vm.envError ?: "Reading the environment catalog…",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    if (vm.envError != null) {
                        FilledTonalButton(onClick = { vm.refreshEnvironments() }) {
                            Text("Check again")
                        }
                    }
                }
            }
            return@Column
        }

        run?.takeIf { it.present }?.let { EnvironmentRunCard(vm, it) }

        catalog.environments.forEach { environment ->
            EnvironmentRow(
                environment = environment,
                busy = busy || run?.active == true,
                onInstall = { confirming = environment },
                onRemove = { vm.removeEnvironment(environment.id) },
            )
        }

        if (catalog.meta.mode == "desktop") {
            Text(
                "Android is paused while this guest owns the panel, so package changes " +
                    "have to wait for phone mode.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }

    confirming?.let { environment ->
        InstallEnvironmentDialog(
            vm = vm,
            environment = environment,
            onDismiss = { confirming = null },
            onConfirm = { withBuild ->
                confirming = null
                vm.installEnvironment(environment.id, withBuild)
            },
        )
    }
}

@Composable
private fun EnvironmentRow(
    environment: EnvInstall.Environment,
    busy: Boolean,
    onInstall: () -> Unit,
    onRemove: () -> Unit,
) {
    val tint = when {
        environment.runtimeReady -> Color(0xFF54B87B)
        !environment.installable -> MaterialTheme.colorScheme.onSurfaceVariant
        else -> MaterialTheme.colorScheme.tertiary
    }
    GlassCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (environment.runtimeReady) Icons.Rounded.CheckCircle
                    else Icons.Rounded.RadioButtonUnchecked,
                    null,
                    Modifier.size(18.dp),
                    tint = tint,
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    environment.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    environment.qualification,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (environment.qualified) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                environment.status,
                style = MaterialTheme.typography.bodyMedium,
                color = tint,
            )
            Text(
                environment.detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (environment.limitations.isNotEmpty()) {
                Text(
                    "Limits: ${environment.limitations.joinToString("; ")}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (environment.backend.isNotBlank()) {
                Text(
                    "Backend ${environment.backend} · ${environment.packages.joinToString(", ")}",
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!environment.runtimeReady && environment.installable) {
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(onClick = onInstall, enabled = !busy) {
                        Text(if (environment.present) "Provision" else "Install")
                    }
                    if (environment.present) {
                        OutlinedButton(onClick = onRemove, enabled = !busy) { Text("Remove") }
                    }
                }
            } else if (environment.runtimeReady) {
                Spacer(Modifier.height(4.dp))
                OutlinedButton(onClick = onRemove, enabled = !busy) {
                    Text("Remove packages")
                }
            }
        }
    }
}

@Composable
private fun InstallEnvironmentDialog(
    vm: AuroraViewModel,
    environment: EnvInstall.Environment,
    onDismiss: () -> Unit,
    onConfirm: (withBuild: Boolean) -> Unit,
) {
    var withBuild by remember { mutableStateOf(false) }
    val needsBuild = environment.missingBinaries.isNotEmpty() && environment.build.isNotBlank()
    LaunchedEffect(environment.id) { vm.loadEnvironmentPlan(environment.id) }
    val packages = vm.envPackages
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Install ${environment.title}?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    when {
                        environment.packages.isEmpty() -> "No package set is declared for this guest."
                        packages.isNotEmpty() -> "${packages.size} packages to install"
                        else -> "Package set ${environment.packages.joinToString(", ")}"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                if (packages.isNotEmpty()) {
                    Text(
                        packages.map { it.name + if (it.state == "installed") " (installed)" else "" }
                            .joinToString(", "),
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    "Installed by the guest's package manager from its configured " +
                        "repositories. Requires network and can take several minutes.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (needsBuild) {
                    Text(
                        "${environment.missingBinaries.joinToString(", ")} is not packaged " +
                            "for this guest. Aurora's in-guest provisioner " +
                            "${environment.build.substringAfterLast('/')} can compile it here, " +
                            "which takes a long time.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Switch(checked = withBuild, onCheckedChange = { withBuild = it })
                        Spacer(Modifier.width(12.dp))
                        Text(
                            if (environment.buildPresent) "Build it in the guest"
                            else "Build it (provisioner absent)",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
                if (environment.qualification !in setOf("qualified", "proven")) {
                    Text(
                        "${environment.qualification}: " +
                            environment.reason.ifBlank { "not fully qualified" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(withBuild && environment.buildPresent) },
            ) { Text("Install") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun EnvironmentRunCard(vm: AuroraViewModel, run: EnvInstall.Run) {
    val log = rememberScrollState()
    LaunchedEffect(run.log) { log.animateScrollTo(log.maxValue) }
    val title = run.envTitle.ifBlank { run.env }
    val verb = if (run.action == "remove") "Removing" else "Installing"
    GlassCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (run.active) {
                    LoadingIndicator(Modifier.size(18.dp))
                } else {
                    Icon(
                        if (run.succeeded) Icons.Rounded.CheckCircle else Icons.Rounded.Warning,
                        null,
                        Modifier.size(18.dp),
                        tint = if (run.succeeded) Color(0xFF54B87B)
                        else MaterialTheme.colorScheme.tertiary,
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        when {
                            run.active -> "$verb $title"
                            run.state == "fail" -> "$title failed"
                            run.state == "cancelled" -> "$title cancelled"
                            else -> "$title finished"
                        },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    run.summary.takeIf { it.isNotBlank() }?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    run.error.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error)
                    }
                }
                if (!run.active) {
                    TextButton(onClick = { vm.resetEnvironment() }) { Text("Dismiss") }
                }
            }
            if (run.stepTotal > 0) {
                LinearProgressIndicator(
                    progress = { (run.stepIndex.toFloat() / run.stepTotal).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(4.dp),
                )
            }
            run.steps.forEach { step -> EnvironmentStepRow(step, current = step.id == run.step) }
            AnimatedVisibility(visible = run.log.isNotBlank()) {
                Text(
                    run.log,
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.bodySmall,
                    softWrap = false,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(150.dp)
                        .verticalScroll(log),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (run.active) {
                    OutlinedButton(
                        onClick = { vm.cancelEnvironment() },
                        enabled = vm.envBusy == null,
                    ) { Text("Cancel after this step") }
                }
                // A freshly installed environment is only useful once it is the
                // one desktop mode starts.
                if (run.succeeded && run.runtimeReady == "yes" && vm.compositor != run.env) {
                    FilledTonalButton(
                        onClick = { vm.selectSession(run.env) },
                        enabled = vm.busy == null,
                    ) { Text("Use ${run.envTitle.ifBlank { run.env }}") }
                }
                TextButton(onClick = { vm.openLog("env-install.log") }) { Text("Open full log") }
            }
        }
    }
}

@Composable
private fun EnvironmentStepRow(step: EnvInstall.Step, current: Boolean) {
    val (icon, tint) = when (step.state) {
        "ok" -> Icons.Rounded.CheckCircle to Color(0xFF54B87B)
        "skip" -> Icons.Rounded.RadioButtonUnchecked to MaterialTheme.colorScheme.onSurfaceVariant
        "warn" -> Icons.Rounded.Warning to MaterialTheme.colorScheme.tertiary
        "fail" -> Icons.Rounded.ErrorOutline to MaterialTheme.colorScheme.error
        "cancelled" -> Icons.Rounded.Close to MaterialTheme.colorScheme.onSurfaceVariant
        "running" -> null to MaterialTheme.colorScheme.primary
        else -> Icons.Rounded.RadioButtonUnchecked to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon == null) LoadingIndicator(Modifier.size(16.dp))
        else Icon(icon, null, Modifier.size(16.dp), tint = tint)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                step.title.ifBlank { step.id },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal,
            )
            if (step.detail.isNotBlank()) {
                Text(
                    step.detail,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Control-tab prompt: the selected session cannot start until it is installed. */
@Composable
fun EnvironmentPrompt(vm: AuroraViewModel, onOpenEnvironments: () -> Unit) {
    val s = vm.status
    if (s["installed"] != "yes") return
    if (s["graphics"] == "ready") return
    val session = s["session"].orEmpty().ifBlank { "phosh" }
    val environment = vm.envCatalog?.environments?.firstOrNull { it.id == session }
    GlassCard {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                environment?.let { "${it.title} is not ready" } ?: "Desktop environment not ready",
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                environment?.detail
                    ?: "The selected session ($session) cannot start yet. Install it in the " +
                    "Apps tab.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = onOpenEnvironments,
                    enabled = vm.rootState == RootState.GRANTED && vm.busy == null,
                ) { Text("Open environments") }
                if (environment != null && environment.installable && !environment.runtimeReady) {
                    Button(
                        onClick = { vm.installEnvironment(environment.id, false) },
                        enabled = vm.envBusy == null && vm.envRun?.active != true,
                    ) { Text("Install now") }
                }
            }
        }
    }
}
