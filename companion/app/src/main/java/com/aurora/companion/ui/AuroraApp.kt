package com.aurora.companion.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.animateContentSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material.icons.outlined.SystemUpdateAlt
import androidx.compose.material.icons.rounded.Apps
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Smartphone
import androidx.compose.material.icons.rounded.SystemUpdateAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.aurora.companion.AuroraViewModel
import com.aurora.companion.R
import com.aurora.companion.Root
import com.aurora.companion.RootState
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi
import dev.chrisbanes.haze.materials.HazeMaterials

enum class Dest(
    val label: String,
    val icon: ImageVector,
    val activeIcon: ImageVector,
    val headline: String,
    val tagline: String,
) {
    Control(
        "Control", Icons.Outlined.Smartphone, Icons.Rounded.Smartphone,
        "Aurora", "Mode, display, and input",
    ),
    Software(
        "Apps", Icons.Outlined.Apps, Icons.Rounded.Apps,
        "Linux software", "Guest package catalog",
    ),
    Settings(
        "Settings", Icons.Outlined.Settings, Icons.Rounded.Settings,
        "Settings", "Behavior and advanced options",
    ),
}

@OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
    ExperimentalHazeMaterialsApi::class,
)
@Composable
fun AuroraApp(vm: AuroraViewModel, windowSize: WindowSizeClass) {
    var dest by rememberSaveable { mutableStateOf(Dest.Control) }
    val snackbar = remember { SnackbarHostState() }
    val compact = windowSize.widthSizeClass == WindowWidthSizeClass.Compact
    val expanded = windowSize.widthSizeClass == WindowWidthSizeClass.Expanded

    LaunchedEffect(vm.message) {
        vm.message?.let { snackbar.showSnackbar(it); vm.message = null }
    }
    LaunchedEffect(dest, vm.rootState) {
        if (vm.rootState != RootState.GRANTED) return@LaunchedEffect
        when (dest) {
            Dest.Control -> vm.refresh()
            Dest.Software -> vm.refreshSoftware()
            Dest.Settings -> vm.refresh()
        }
    }
    val refreshCurrent = {
        when (dest) {
            Dest.Control -> vm.refresh()
            Dest.Software -> vm.refreshSoftware()
            Dest.Settings -> vm.refresh()
        }
    }
    var soulTaps by remember { mutableStateOf(0) }
    var soulLast by remember { mutableStateOf(0L) }
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    val hazeState = rememberHazeState()

    AuroraBackground {
        Scaffold(
            modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    navigationIcon = {
                        Image(
                            painterResource(R.drawable.ic_soul),
                            contentDescription = null,
                            modifier = Modifier
                                .padding(horizontal = 14.dp)
                                .size(26.dp)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    val now = System.currentTimeMillis()
                                    soulTaps = if (now - soulLast < 1500) soulTaps + 1 else 1
                                    soulLast = now
                                    if (soulTaps >= 7) {
                                        soulTaps = 0
                                        vm.message = "* Despite everything, it's still you."
                                    }
                                },
                        )
                    },
                    title = {
                        Column {
                            Text(dest.headline, style = MaterialTheme.typography.titleLarge)
                            Text(
                                dest.tagline,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                        scrolledContainerColor = MaterialTheme.colorScheme.surface,
                    ),
                    scrollBehavior = scroll,
                )
            },
            snackbarHost = { SnackbarHost(snackbar, Modifier.padding(bottom = 82.dp)) },
        ) { pad ->
            Box(
                Modifier.fillMaxSize().padding(pad),
                contentAlignment = Alignment.TopCenter,
            ) {
                val content = Modifier.widthIn(
                    max = when {
                        expanded -> 1080.dp
                        !compact -> 760.dp
                        else -> 640.dp
                    },
                )
                Box(Modifier.fillMaxSize().hazeSource(hazeState), contentAlignment = Alignment.TopCenter) {
                    // Intentional hard cut: keep the pill, lose the page carousel.
                    when (dest) {
                        Dest.Control -> ControlScreen(vm, expanded, content, 82.dp)
                        Dest.Software -> SoftwareScreen(vm, expanded, content, 82.dp)
                        Dest.Settings -> SettingsScreen(
                            vm,
                            modifier = content,
                            bottomPad = 82.dp,
                        )
                    }
                }
                FloatingPillNav(
                    dest = dest,
                    onSelect = { dest = it },
                    busy = vm.busy != null,
                    onRefresh = refreshCurrent,
                    hazeState = hazeState,
                    modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp),
                )
            }
        }
    }

    LogSheetAndDialogs(vm)
}

@OptIn(ExperimentalHazeMaterialsApi::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun FloatingPillNav(
    dest: Dest,
    onSelect: (Dest) -> Unit,
    busy: Boolean,
    onRefresh: () -> Unit,
    hazeState: HazeState,
    modifier: Modifier = Modifier,
) {
    val stroke = BorderStroke(
        1.dp,
        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
    )
    val frost = HazeMaterials.thin(MaterialTheme.colorScheme.surfaceContainerHigh)
    Row(
        modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp),
    ) {
        Surface(
            shape = CircleShape,
            color = Color.Transparent,
            border = stroke,
            shadowElevation = 7.dp,
        ) {
            Row(
                Modifier
                    .clip(CircleShape)
                    .hazeEffect(hazeState, frost) { blurRadius = 14.dp }
                    .padding(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Dest.entries.forEach { item ->
                    val selected = dest == item
                    val itemColor by animateColorAsState(
                        targetValue = if (selected) MaterialTheme.colorScheme.secondaryContainer
                        else Color.Transparent,
                        animationSpec = tween(durationMillis = 220),
                        label = "pill color",
                    )
                    Surface(
                        onClick = { onSelect(item) },
                        shape = CircleShape,
                        color = itemColor,
                        contentColor = if (selected) MaterialTheme.colorScheme.onSecondaryContainer
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                    ) {
                        Row(
                            Modifier
                                .animateContentSize(
                                    animationSpec = spring(
                                        dampingRatio = Spring.DampingRatioNoBouncy,
                                        stiffness = Spring.StiffnessMedium,
                                    ),
                                )
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                if (selected) item.activeIcon else item.icon,
                                contentDescription = item.label,
                                modifier = Modifier.size(19.dp),
                            )
                            AnimatedVisibility(
                                visible = selected,
                                enter = fadeIn(tween(120)) + expandHorizontally(
                                    animationSpec = spring(
                                        dampingRatio = Spring.DampingRatioNoBouncy,
                                        stiffness = Spring.StiffnessMedium,
                                    ),
                                ),
                                exit = fadeOut(tween(90)) + shrinkHorizontally(tween(160)),
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(6.dp))
                                    Text(item.label, style = MaterialTheme.typography.labelLarge)
                                    Box(Modifier.size(2.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
        Surface(
            shape = CircleShape,
            color = Color.Transparent,
            border = stroke,
            shadowElevation = 7.dp,
        ) {
            Box(
                Modifier
                    .clip(CircleShape)
                    .hazeEffect(hazeState, frost) { blurRadius = 14.dp }
                    .clickable(enabled = !busy, onClick = onRefresh)
                    .size(50.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (busy) LoadingIndicator(Modifier.size(26.dp))
                else Icon(Icons.Rounded.Refresh, "Refresh", Modifier.size(21.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun LogSheetAndDialogs(vm: AuroraViewModel) {
    if (vm.logName != null) {
        val clipboard = LocalClipboardManager.current
        ModalBottomSheet(
            onDismissRequest = { vm.closeLog() },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
                androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        vm.logName ?: "",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = {
                        vm.logText?.let { clipboard.setText(AnnotatedString(it)) }
                    }) { Icon(Icons.Rounded.ContentCopy, "Copy") }
                    IconButton(onClick = { vm.openLog(vm.logName ?: return@IconButton) }) {
                        Icon(Icons.Rounded.Refresh, "Reload")
                    }
                }
                Box(Modifier.size(8.dp))
                val text = vm.logText
                if (text == null) {
                    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                        LoadingIndicator()
                    }
                } else {
                    Text(
                        text,
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        softWrap = false,
                        modifier = Modifier
                            .verticalScroll(rememberScrollState())
                            .horizontalScroll(rememberScrollState())
                            .fillMaxWidth(),
                    )
                }
            }
        }
    }

    vm.rebootPrompt?.let { why ->
        AlertDialog(
            onDismissRequest = { vm.rebootPrompt = null },
            icon = { Icon(Icons.Rounded.RestartAlt, null) },
            title = { Text("Reboot to apply?") },
            text = { Text(why) },
            confirmButton = {
                Button(onClick = {
                    vm.rebootPrompt = null
                    vm.act("power", refreshAfter = false) { Root.rebootPhone() }
                }) { Text("Reboot now") }
            },
            dismissButton = {
                TextButton(onClick = { vm.rebootPrompt = null }) { Text("Later") }
            },
        )
    }
}
