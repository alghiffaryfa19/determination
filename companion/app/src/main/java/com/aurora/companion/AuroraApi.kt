package com.aurora.companion

/** Stable Android-facing names. Native protocol details stay private. */
object AuroraApi {
    const val ACTION_STATUS = "com.aurora.action.STATUS"
    const val ACTION_CAPABILITIES = "com.aurora.action.CAPABILITIES"
    const val ACTION_METRICS = "com.aurora.action.METRICS"
    const val ACTION_REQUEST_MODE = "com.aurora.action.REQUEST_MODE"
    const val ACTION_BIND_CONTROL = "com.aurora.action.BIND_CONTROL"

    const val EXTRA_MODE = "com.aurora.extra.MODE"
    const val EXTRA_JSON = "com.aurora.extra.JSON"
    const val EXTRA_STATUS = "com.aurora.extra.STATUS"

    const val MODE_PHONE = "phone"
    const val MODE_DESKTOP = "desktop"

    const val RESULT_UNAVAILABLE = ZygiskBridge.STATUS_UNAVAILABLE
    const val RESULT_INVALID = ZygiskBridge.STATUS_INVALID

    fun validMode(value: String?): Boolean = value == MODE_PHONE || value == MODE_DESKTOP
}
