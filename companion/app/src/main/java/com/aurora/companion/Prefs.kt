package com.aurora.companion

import android.content.Context
import android.content.SharedPreferences

/**
 * App settings (Settings tab). Plain SharedPreferences : every consumer calls
 * [init] first (idempotent), including BootReceiver which runs before any UI.
 */
object Prefs {
    const val POLL_DEFAULT = 5
    private lateinit var sp: SharedPreferences

    fun init(context: Context) {
        if (!::sp.isInitialized) {
            sp = context.applicationContext
                .getSharedPreferences("aurora-settings", Context.MODE_PRIVATE)
        }
    }

    /** Status poll period while the Control screen is visible; 0 = manual only. */
    var pollSeconds: Int
        get() = sp.getInt("poll_seconds", POLL_DEFAULT)
        set(v) { sp.edit().putInt("poll_seconds", v).apply() }

    /** Mirrored to $AURORA/etc/stop-guest-on-exit so desktop-off honors it too. */
    var stopGuestOnExit: Boolean
        get() = sp.getBoolean("stop_guest_on_exit", false)
        set(v) { sp.edit().putBoolean("stop_guest_on_exit", v).apply() }
}
