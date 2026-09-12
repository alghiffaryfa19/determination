package com.aurora.companion

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import kotlin.concurrent.thread

/** User-confirmed mode request for apps which do not hold the signature API. */
class AuroraModeRequestActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mode = intent.getStringExtra(AuroraApi.EXTRA_MODE)
        if (!AuroraApi.validMode(mode)) {
            finishWith(AuroraApi.RESULT_INVALID, "invalid mode")
            return
        }
        val entering = mode == AuroraApi.MODE_DESKTOP
        AlertDialog.Builder(this)
            .setTitle(if (entering) R.string.api_enter_title else R.string.api_exit_title)
            .setMessage(
                if (entering) R.string.api_enter_body else R.string.api_exit_body,
            )
            .setNegativeButton(android.R.string.cancel) { _, _ ->
                finishWith(Activity.RESULT_CANCELED, "cancelled")
            }
            .setPositiveButton(if (entering) R.string.enter_go else R.string.exit_go) { _, _ ->
                requestMode(mode!!)
            }
            .setOnCancelListener { finishWith(Activity.RESULT_CANCELED, "cancelled") }
            .show()
    }

    private fun requestMode(mode: String) {
        thread(name = "aurora-api-mode", isDaemon = true) {
            val response = ZygiskBridge.mode(mode)
            runOnUiThread {
                finishWith(
                    response?.status ?: AuroraApi.RESULT_UNAVAILABLE,
                    response?.payload ?: "native control API unavailable",
                )
            }
        }
    }

    private fun finishWith(status: Int, message: String) {
        setResult(
            if (status == ZygiskBridge.STATUS_OK || status == ZygiskBridge.STATUS_ACCEPTED) {
                Activity.RESULT_OK
            } else {
                status
            },
            Intent()
                .putExtra(AuroraApi.EXTRA_STATUS, status)
                .putExtra(AuroraApi.EXTRA_JSON, message),
        )
        finish()
    }
}
