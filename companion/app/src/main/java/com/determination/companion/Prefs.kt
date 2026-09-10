package com.determination.companion

import android.content.Context
import android.content.SharedPreferences

/**
 * App settings (Settings tab). Plain SharedPreferences : every consumer calls
 * [init] first (idempotent), including BootReceiver which runs before any UI.
 */
object Prefs {
    const val POLL_DEFAULT = 5
    val UPDATE_MANIFEST_DEFAULT: String = BuildConfig.UPDATE_MANIFEST_URL

    private lateinit var sp: SharedPreferences

    fun init(context: Context) {
        if (!::sp.isInitialized) {
            sp = context.applicationContext
                .getSharedPreferences("det-settings", Context.MODE_PRIVATE)
        }
    }

    /** Status poll period while the Control screen is visible; 0 = manual only. */
    var pollSeconds: Int
        get() = sp.getInt("poll_seconds", POLL_DEFAULT)
        set(v) { sp.edit().putInt("poll_seconds", v).apply() }

    /** Mirrored to $DET/etc/stop-guest-on-exit so desktop-off honors it too. */
    var stopGuestOnExit: Boolean
        get() = sp.getBoolean("stop_guest_on_exit", false)
        set(v) { sp.edit().putBoolean("stop_guest_on_exit", v).apply() }

    /** HTTPS release metadata. Custom mirrors are allowed; plain HTTP is not. */
    var updateManifestUrl: String
        get() = sp.getString("update_manifest_url", UPDATE_MANIFEST_DEFAULT)
            ?.takeIf { it.isNotBlank() } ?: UPDATE_MANIFEST_DEFAULT
        set(v) { sp.edit().putString("update_manifest_url", v.trim()).apply() }

    /** Validate and prepare every installer input, but do not install or flash. */
    var installerDryRun: Boolean
        get() = sp.getBoolean("installer_dry_run", false)
        set(v) { sp.edit().putBoolean("installer_dry_run", v).apply() }

    /** Prevent repeatedly forcing the walkthrough after the user has seen it. */
    var installerWalkthroughSeen: Boolean
        get() = sp.getBoolean("installer_walkthrough_seen", false)
        set(v) { sp.edit().putBoolean("installer_walkthrough_seen", v).apply() }

}
