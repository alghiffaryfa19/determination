package com.aurora.companion

/**
 * Root bridge for the on-device environment installer (`$AURORA/bin/env-install`).
 *
 * The device owns the catalog (the session manifests), the package recipes and
 * the readiness verdict; this object only reads them back, so the app can never
 * offer an environment the launcher would refuse to start.
 */
object EnvInstall {

    private const val BIN = "${Root.AURORA}/bin/env-install"
    private val ENV_ID = Regex("[a-z0-9-]{1,32}")

    data class Environment(
        val id: String,
        val title: String,
        val description: String,
        val backend: String,
        val renderer: String,
        val qualification: String,
        val reason: String,
        val limitations: List<String>,
        val packages: List<String>,
        val build: String,
        val glue: List<String>,
        val requiredBinaries: List<String>,
        val missingBinaries: List<String>,
        val runtimeReady: Boolean,
        val runtimeUnknown: Boolean,
        val runtimeReason: String,
        val packagesState: String,
        val packagesMissing: List<String>,
        val glueMissing: List<String>,
        val recipe: String,
        val packageSet: String,
        val buildPresent: Boolean,
        val installable: Boolean,
        val installableReason: String,
    ) {
        val qualified get() = qualification == "qualified" || qualification == "proven"
        val experimental get() = qualification == "experimental" || qualification == "diagnostic"
        val selectable get() = runtimeReady && qualification in SELECTABLE_QUALIFICATIONS
        val present get() = missingBinaries.isEmpty()

        /** One line for the list: what state this environment is in now. */
        val status: String
            get() = when {
                runtimeUnknown -> "Cannot verify"
                !installable && !present -> "Not installable here"
                runtimeReady -> "Ready"
                !present -> "Missing ${missingBinaries.joinToString(", ")}"
                else -> "Installed · launcher not satisfied"
            }

        val detail: String
            get() = when {
                glueMissing.isNotEmpty() ->
                    "Aurora integration missing: ${glueMissing.joinToString(", ")}"
                missingBinaries.isNotEmpty() && build.isNotBlank() ->
                    "${missingBinaries.joinToString(", ")} · no package provides it; " +
                        "${build.substringAfterLast('/')} builds it in the guest"
                missingBinaries.isNotEmpty() -> "Missing ${missingBinaries.joinToString(", ")}"
                runtimeUnknown -> runtimeReason.ifBlank { "The device returned no verdict" }
                runtimeReady -> "The launcher can start this session"
                // Installed, nothing missing, yet session-select refuses it.
                runtimeReason.isNotBlank() -> runtimeReason
                !installable -> installableReason
                else -> "Packages: ${packages.joinToString(", ").ifBlank { "none declared" }}"
            }
    }

    data class Meta(
        val mode: String,
        val guestRunning: Boolean,
        val distro: String,
        val freeMib: Int,
        val lastRunState: String,
    )

    data class Catalog(val meta: Meta, val environments: List<Environment>)

    data class Step(val id: String, val title: String, val state: String, val detail: String) {
        val done get() = state == "ok" || state == "skip"
        val running get() = state == "running"
    }

    data class Package(val name: String, val state: String)

    /** One install/remove run as the device recorded it. */
    data class Run(
        val present: Boolean,
        val running: Boolean,
        val state: String,
        val action: String,
        val env: String,
        val envTitle: String,
        val step: String,
        val stepIndex: Int,
        val stepTotal: Int,
        val startedAt: Long,
        val distro: String,
        val withBuild: Boolean,
        val packageCount: Int,
        val runtimeReady: String,
        val runtimeReason: String,
        val summary: String,
        val error: String,
        val log: String,
        val steps: List<Step>,
    ) {
        val active get() = running || state == "pending"
        val finished get() = !running && state in setOf("ok", "warn", "fail", "cancelled")
        val succeeded get() = state == "ok" || state == "warn"
        fun stepState(id: String) = steps.firstOrNull { it.id == id }?.state ?: "pending"
        fun stepDetail(id: String) = steps.firstOrNull { it.id == id }?.detail ?: ""
    }

    // ------------------------------------------------------------ device calls

    fun catalog(): Catalog? {
        val result = Root.run("$BIN catalog", timeoutSec = 90)
        if (result.out.isBlank()) return null
        val parsed = parse(result.out)
        val meta = parsed.firstOf("meta")
        return Catalog(
            meta = Meta(
                mode = meta["mode"] ?: "phone",
                guestRunning = meta["guest_running"] == "yes",
                distro = meta["distro"] ?: "",
                freeMib = meta["free_mib"]?.toIntOrNull() ?: 0,
                lastRunState = meta["run_state"] ?: "none",
            ),
            environments = parsed.of("environment").map { environmentFrom(it) },
        )
    }

    /** Recipe detail for one environment, including its package list. */
    fun plan(id: String): Pair<Environment?, List<Package>> {
        if (!ENV_ID.matches(id)) return null to emptyList()
        val result = Root.run("$BIN plan $id", timeoutSec = 120)
        if (result.out.isBlank()) return null to emptyList()
        val parsed = parse(result.out)
        val catalog = parsed.of("environment").firstOrNull()?.let { environmentFrom(it) }
        val packages = parsed.of("package").map {
            Package(it["name"] ?: "", it["state"] ?: "absent")
        }
        return catalog to packages
    }

    fun status(): Run {
        val parsed = parse(Root.run("$BIN status", timeoutSec = 30).out)
        val state = parsed.firstOf("state")
        return Run(
            present = state.isNotEmpty() && state["state"] != "none",
            running = state["running"] == "yes",
            state = state["state"] ?: "none",
            action = state["action"] ?: "install",
            env = state["env"] ?: "",
            envTitle = state["env_title"] ?: "",
            step = state["step"] ?: "",
            stepIndex = state["step_index"]?.toIntOrNull() ?: 0,
            stepTotal = state["step_total"]?.toIntOrNull() ?: 0,
            startedAt = state["started"]?.toLongOrNull() ?: 0L,
            distro = state["distro"] ?: "",
            withBuild = state["with_build"] == "yes",
            packageCount = state["package_count"]?.toIntOrNull() ?: 0,
            runtimeReady = state["runtime_ready"] ?: "unknown",
            runtimeReason = state["runtime_reason"] ?: "",
            summary = state["summary"] ?: "",
            error = state["error"] ?: "",
            log = parsed.bodyOf("log").trim(),
            steps = parsed.of("step").map {
                Step(
                    id = it["id"] ?: "",
                    title = it["title"] ?: "",
                    state = it["state"] ?: "pending",
                    detail = it["detail"] ?: "",
                )
            },
        )
    }

    /** Install (or with [withBuild], also compile what no package ships). */
    fun install(id: String, withBuild: Boolean): Root.Result {
        if (!ENV_ID.matches(id)) return Root.Result(false, "", "invalid environment id")
        val flag = if (withBuild) " --with-build" else ""
        return Root.run("$BIN install $id$flag", timeoutSec = 60)
    }

    fun remove(id: String): Root.Result {
        if (!ENV_ID.matches(id)) return Root.Result(false, "", "invalid environment id")
        return Root.run("$BIN remove $id", timeoutSec = 60)
    }

    fun cancel() = Root.run("$BIN cancel", timeoutSec = 30)

    fun reset() = Root.run("$BIN reset", timeoutSec = 30)

    // ---------------------------------------------------------------- parsing

    private fun split(value: String) =
        value.split(',').map { it.trim() }.filter { it.isNotEmpty() }

    private fun environmentFrom(fields: Map<String, String>) = Environment(
        id = fields["id"] ?: "",
        title = fields["title"] ?: "",
        description = fields["description"] ?: "",
        backend = fields["backend"] ?: "",
        renderer = fields["renderer"] ?: "",
        qualification = fields["qualification"] ?: "planned",
        reason = fields["reason"] ?: "",
        limitations = split(fields["limitations"] ?: ""),
        packages = split(fields["packages"] ?: ""),
        build = fields["build"] ?: "",
        glue = split(fields["glue"] ?: ""),
        requiredBinaries = split(fields["required_binaries"] ?: ""),
        missingBinaries = split(fields["missing_binaries"] ?: ""),
        runtimeReady = fields["runtime_ready"] == "yes",
        runtimeUnknown = fields["runtime_ready"] == "unknown",
        runtimeReason = fields["runtime_reason"] ?: "",
        packagesState = fields["packages_state"] ?: "unknown",
        packagesMissing = split(fields["packages_missing"] ?: ""),
        glueMissing = split(fields["glue_missing"] ?: ""),
        recipe = fields["recipe"] ?: "none",
        packageSet = fields["package_set"] ?: "none",
        buildPresent = fields["build_present"] == "yes",
        installable = fields["installable"] == "yes",
        installableReason = fields["installable_reason"] ?: "",
    )

    private data class Section(
        val name: String,
        val fields: Map<String, String>,
        val body: String,
    )

    private fun List<Section>.of(name: String) = filter { it.name == name }.map { it.fields }
    private fun List<Section>.firstOf(name: String) = of(name).firstOrNull() ?: emptyMap()
    private fun List<Section>.bodyOf(name: String) =
        filter { it.name == name }.joinToString("\n") { it.body }

    /** `==name` section headers followed by key=value lines (see the script). */
    private fun parse(text: String): List<Section> {
        val out = mutableListOf<Section>()
        var name: String? = null
        var fields = linkedMapOf<String, String>()
        var body = StringBuilder()

        fun flush() {
            name?.let { out += Section(it, fields, body.toString()) }
            fields = linkedMapOf()
            body = StringBuilder()
        }
        text.lineSequence().forEach { line ->
            if (line.startsWith("==")) {
                flush()
                name = line.removePrefix("==").trim()
            } else {
                val i = line.indexOf('=')
                if (i > 0 && !line.substring(0, i).contains(' ')) {
                    fields[line.substring(0, i)] = line.substring(i + 1).trim()
                } else if (line.isNotBlank()) {
                    body.append(line).append('\n')
                }
            }
        }
        flush()
        return out
    }
}

/** Qualifications the session picker may select; shared with the environments list. */
val SELECTABLE_QUALIFICATIONS = setOf("qualified", "proven", "experimental", "diagnostic")
