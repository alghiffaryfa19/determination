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
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.determination.companion.CATALOG
import com.determination.companion.DetViewModel
import com.determination.companion.RootState

@Composable
fun SoftwareScreen(
    vm: DetViewModel,
    wide: Boolean,
    modifier: Modifier = Modifier,
    bottomPad: Dp = 0.dp,
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 24.dp + bottomPad),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (!vm.guestUp) {
            GlassCard {
                Text(
                    "Guest container is not running : package status and installs need it up. " +
                        "Start it from the Control tab.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(20.dp),
                )
            }
        }

        DistroSection(vm)

        if (wide) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(Modifier.weight(1f)) { CatalogSection(vm) }
            }
        } else {
            CatalogSection(vm)
        }
    }
}

@Composable
private fun DistroSection(vm: DetViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel("Guest distro")
        vm.guestDistros.forEach { distro ->
            GlassCard {
                Row(
                    Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = distro.active,
                        onClick = { vm.selectGuestDistro(distro.id) },
                        enabled = distro.installed && !distro.active && vm.busy == null,
                    )
                    Column(Modifier.weight(1f)) {
                        Text(
                            distro.name,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            when {
                                !distro.installed -> "Not installed"
                                distro.ready -> "Installed · runtime provisioned"
                                else -> "Installed · base needs provisioning"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (distro.active && distro.installed && !distro.ready) {
                        FilledTonalButton(
                            enabled = vm.busy == null,
                            onClick = vm::provisionGuestDistro,
                        ) { Text("Provision") }
                    }
                }
            }
        }
    }
}

@Composable
private fun CatalogSection(vm: DetViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        CATALOG.groupBy { it.category }.forEach { (category, apps) ->
            SectionLabel(category)
            GlassCard {
                Column(Modifier.padding(vertical = 6.dp)) {
                    apps.forEach { app ->
                        val installed = vm.pkgStatus[app.pkg] == "installed"
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 20.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(app.title, style = MaterialTheme.typography.titleSmall)
                                Text(
                                    "${app.blurb} · ${app.pkg}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Spacer(Modifier.width(10.dp))
                            when {
                                !vm.guestUp -> Text(
                                    ":",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                installed -> OutlinedButton(
                                    enabled = vm.installingPkg == null,
                                    onClick = { vm.removePkg(app.pkg) },
                                ) { Text("Remove") }
                                else -> InstallButton(vm, app.pkg)
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun InstallButton(vm: DetViewModel, pkg: String, label: String = "Install") {
    val installingThis = vm.installingPkg == pkg
    FilledTonalButton(
        enabled = vm.installingPkg == null && vm.rootState == RootState.GRANTED,
        onClick = { vm.installPkg(pkg) },
    ) {
        if (installingThis) {
            LoadingIndicator(Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(if (installingThis) "Installing…" else label)
    }
}
