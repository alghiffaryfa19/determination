package com.determination.companion

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.UnknownHostException
import java.net.URL
import java.security.MessageDigest

enum class UpdateArtifactKind(val wireName: String) {
    MODULE("module"),
    RUNTIME("runtime"),
    ROOTFS("rootfs"),
    COMPANION("companion"),
    BOOT("boot");

    companion object {
        fun parse(value: String): UpdateArtifactKind =
            entries.firstOrNull { it.wireName == value }
                ?: throw IllegalArgumentException("unknown artifact type: $value")
    }
}

enum class ArtifactSupport(val wireName: String) {
    QUALIFIED("qualified"),
    EXPERIMENTAL("experimental");

    companion object {
        fun parse(value: String): ArtifactSupport =
            entries.firstOrNull { it.wireName == value } ?: EXPERIMENTAL
    }
}

data class OnlineArtifact(
    val kind: UpdateArtifactKind,
    val name: String,
    val url: String,
    val sha256: String,
    val size: Long,
    val devices: Set<String>,
    val abis: Set<String>,
    val androidBuilds: Set<String>,
    val distro: String,
    val support: ArtifactSupport,
    val description: String,
) {
    fun supports(
        deviceIds: Set<String>,
        deviceAbis: Set<String>,
        buildFingerprint: String = "",
    ): Boolean =
        (devices.isEmpty() || devices.any { it in deviceIds }) &&
            (abis.isEmpty() || abis.any { it in deviceAbis }) &&
            (androidBuilds.isEmpty() || buildFingerprint in androidBuilds)
}

data class OnlineRelease(
    val version: String,
    val versionCode: Int,
    val codename: String,
    val channel: String,
    val publishedAt: String,
    val artifacts: List<OnlineArtifact>,
)

class ReleaseHttpException(val statusCode: Int) :
    IOException("update server returned HTTP $statusCode")

/** HTTPS-only release metadata and hash-verified artifact downloads. */
object ReleaseRepository {
    private val SUPPORTED_SCHEMAS = setOf(1, 2)
    private const val MAX_MANIFEST_BYTES = 256 * 1024
    private const val MAX_ARTIFACT_BYTES = 4L * 1024 * 1024 * 1024
    private const val MAX_REDIRECTS = 5
    private const val DNS_ATTEMPTS = 3

    fun fetch(manifestUrl: String): OnlineRelease {
        val bytes = retryDnsLookup {
            readHttps(manifestUrl, MAX_MANIFEST_BYTES.toLong())
        }
        val root = JSONObject(bytes.toString(Charsets.UTF_8))
        require(root.getInt("schema") in SUPPORTED_SCHEMAS) { "unsupported update schema" }
        val artifactsJson = root.getJSONArray("artifacts")
        val artifacts = buildList {
            for (i in 0 until artifactsJson.length()) {
                val item = artifactsJson.getJSONObject(i)
                val name = safeName(item.getString("name"))
                val sha = item.getString("sha256").lowercase()
                require(sha.matches(Regex("[0-9a-f]{64}"))) { "bad SHA-256 for $name" }
                val size = item.getLong("size")
                require(size in 1..MAX_ARTIFACT_BYTES) { "bad size for $name" }
                val url = item.getString("url")
                requireHttps(url)
                add(
                    OnlineArtifact(
                        kind = UpdateArtifactKind.parse(item.getString("type")),
                        name = name,
                        url = url,
                        sha256 = sha,
                        size = size,
                        devices = item.stringSet("devices"),
                        abis = item.stringSet("abis"),
                        androidBuilds = item.stringSet("androidBuilds"),
                        distro = item.optString("distro"),
                        support = ArtifactSupport.parse(item.optString("support")),
                        description = item.optString("description"),
                    ),
                )
            }
        }
        require(artifacts.isNotEmpty()) { "release has no artifacts" }
        return OnlineRelease(
            version = root.getString("version"),
            versionCode = root.getInt("versionCode"),
            codename = root.optString("codename"),
            channel = root.optString("channel", "stable"),
            publishedAt = root.optString("publishedAt"),
            artifacts = artifacts,
        )
    }

    /** Download, verify exact length and SHA-256, then atomically publish locally. */
    fun download(context: Context, artifact: OnlineArtifact): File {
        val updateDir = File(context.filesDir, "updates").apply { mkdirs() }
        val destination = File(updateDir, safeName(artifact.name))
        val part = File(updateDir, ".${destination.name}.part")
        if (destination.length() == artifact.size && sha256(destination) == artifact.sha256) {
            return destination
        }
        destination.delete()
        part.delete()

        val connection = openHttps(artifact.url)
        try {
            val declared = connection.contentLengthLong
            require(declared < 0 || declared == artifact.size) {
                "server size changed for ${artifact.name}"
            }
            val digest = MessageDigest.getInstance("SHA-256")
            var count = 0L
            connection.inputStream.buffered().use { input ->
                FileOutputStream(part).buffered().use { output ->
                    val buffer = ByteArray(128 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        count += read
                        require(count <= artifact.size && count <= MAX_ARTIFACT_BYTES) {
                            "download exceeded declared size"
                        }
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                }
            }
            require(count == artifact.size) { "short download: $count of ${artifact.size} bytes" }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            require(actual == artifact.sha256) { "SHA-256 mismatch for ${artifact.name}" }
            if (destination.exists() && !destination.delete()) error("cannot replace old download")
            require(part.renameTo(destination)) { "cannot publish verified download" }
            return destination
        } finally {
            connection.disconnect()
            part.delete()
        }
    }

    private fun readHttps(url: String, maxBytes: Long): ByteArray {
        val connection = openHttps(url)
        try {
            val declared = connection.contentLengthLong
            require(declared < 0 || declared <= maxBytes) { "update manifest is too large" }
            return connection.inputStream.use { input ->
                val out = ArrayList<Byte>()
                val buffer = ByteArray(8192)
                var total = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    require(total <= maxBytes) { "update manifest is too large" }
                    for (i in 0 until read) out.add(buffer[i])
                }
                ByteArray(out.size) { out[it] }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun openHttps(initialUrl: String): HttpURLConnection {
        var current = initialUrl
        repeat(MAX_REDIRECTS + 1) { redirect ->
            requireHttps(current)
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 45_000
            connection.setRequestProperty("User-Agent", "Determination/${BuildConfig.VERSION_NAME}")
            val code = try {
                connection.responseCode
            } catch (e: Exception) {
                connection.disconnect()
                throw e
            }
            if (code in 300..399) {
                val next = connection.getHeaderField("Location")
                    ?: error("update redirect had no location")
                connection.disconnect()
                require(redirect < MAX_REDIRECTS) { "too many update redirects" }
                current = URL(URL(current), next).toString()
            } else {
                if (code !in 200..299) {
                    connection.disconnect()
                    throw ReleaseHttpException(code)
                }
                return connection
            }
        }
        error("too many update redirects")
    }

    /** Android occasionally reports a transient DNS miss while connectivity settles. */
    private fun <T> retryDnsLookup(block: () -> T): T {
        repeat(DNS_ATTEMPTS) { attempt ->
            try {
                return block()
            } catch (e: UnknownHostException) {
                if (attempt == DNS_ATTEMPTS - 1) throw e
                Thread.sleep(750L * (attempt + 1))
            }
        }
        error("unreachable")
    }

    private fun requireHttps(value: String) {
        require(URL(value).protocol.equals("https", ignoreCase = true)) { "updates require HTTPS" }
    }

    private fun safeName(value: String): String {
        require(value.isNotBlank() && value.length <= 120) { "invalid artifact filename" }
        require(value.all { it.isLetterOrDigit() || it in "._-" }) { "unsafe artifact filename" }
        return value
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(128 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun JSONObject.stringSet(key: String): Set<String> {
        val array = optJSONArray(key) ?: return emptySet()
        return buildSet { for (i in 0 until array.length()) add(array.getString(i)) }
    }
}
