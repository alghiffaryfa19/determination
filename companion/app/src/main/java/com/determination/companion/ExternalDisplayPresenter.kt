package com.determination.companion

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import java.io.File
import kotlin.math.roundToInt

object NativePresenter {
    init {
        System.loadLibrary("det_presenter")
    }

    external fun nativeStart(
        surface: Surface,
        socketPath: String,
        width: Int,
        height: Int,
        refreshRate: Float
    ): Boolean
    external fun nativeResize(width: Int, height: Int)
    external fun nativeTouch(
        action: Int,
        pointerId: Int,
        x: Float,
        y: Float,
        width: Int,
        height: Int,
    ): Boolean
    external fun nativeInput(
        type: Int,
        code: Int,
        value: Int,
        minimum: Int,
        maximum: Int,
        sourceFlags: Int,
    ): Boolean
    external fun nativeStop()
}

/**
 * Owns the Android external-display endpoint. KWin remains the compositor;
 * this class merely gives its gralloc buffers a normal app-owned SurfaceControl
 * on the presentation display, so Android can keep the phone display alive.
 */
class ExternalDisplayPresenter(
    private val context: Context,
    private val onState: (ExternalDisplaySnapshot) -> Unit,
) :
    DisplayManager.DisplayListener {

    companion object {
        private const val TAG = "DetExternalDisplay"
        const val SOCKET_NAME = "presenter.sock"
    }

    private val displays = context.getSystemService(DisplayManager::class.java)
    private val socketDir: File = context.createDeviceProtectedStorageContext()
        .filesDir.apply { mkdirs() }
    private var presentation: GuestPresentation? = null
    private var displaySignature: DisplaySignature? = null
    private var started = false

    private data class DisplaySignature(
        val displayId: Int,
        val modeId: Int,
        val width: Int,
        val height: Int,
        val refreshMilliHz: Int,
    )

    fun start() {
        if (started) return
        started = true
        displays.registerDisplayListener(this, null)
        onState(ExternalDisplaySnapshot(phase = "waiting"))
        refresh()
    }

    fun stop() {
        if (!started) return
        started = false
        displays.unregisterDisplayListener(this)
        presentation?.dismiss()
        presentation = null
        displaySignature = null
        NativePresenter.nativeStop()
    }

    override fun onDisplayAdded(displayId: Int) = refresh()
    override fun onDisplayRemoved(displayId: Int) = refresh()
    override fun onDisplayChanged(displayId: Int) = refresh()

    private fun refresh() {
        val candidate = displays
            .getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .firstOrNull { it.displayId != Display.DEFAULT_DISPLAY && it.isValid }
        val mode = candidate?.mode
        val signature = if (candidate != null && mode != null) {
            DisplaySignature(
                candidate.displayId,
                mode.modeId,
                mode.physicalWidth,
                mode.physicalHeight,
                (mode.refreshRate * 1000f).toInt(),
            )
        } else null
        if (signature == displaySignature && presentation?.isShowing == true) return

        presentation?.dismiss()
        presentation = null
        displaySignature = null
        NativePresenter.nativeStop()
        if (candidate != null) {
            Log.i(TAG, "attaching to ${candidate.name} (${candidate.displayId})")
            try {
                presentation = GuestPresentation(
                    context,
                    candidate,
                    File(socketDir, SOCKET_NAME).absolutePath,
                    onState,
                ).also { it.show() }
                displaySignature = signature
            } catch (error: Throwable) {
                presentation = null
                Log.w(TAG, "display disappeared while attaching: ${error.message}")
                onState(ExternalDisplaySnapshot(phase = "error", error = error.message ?: "attach failed"))
            }
        } else {
            Log.i(TAG, "no external presentation display")
            onState(ExternalDisplaySnapshot(phase = "waiting"))
        }
    }
}

private object LinuxInput {
    const val EV_SYN = 0
    const val EV_KEY = 1
    const val EV_REL = 2
    const val EV_ABS = 3
    const val SYN_REPORT = 0
    const val REL_WHEEL_HI_RES = 11
    const val REL_HWHEEL_HI_RES = 12
    const val ABS_X = 0
    const val ABS_Y = 1
    const val SOURCE_ABSOLUTE = 1

    private val letterKeys = intArrayOf(
        30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
        49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44,
    )
    private val keypadDigits = intArrayOf(82, 79, 80, 81, 75, 76, 77, 71, 72, 73)

    fun keyCode(event: KeyEvent): Int? {
        // Hardware KeyEvents normally retain their Linux evdev scan code.
        // scrcpy's SDK injection uses scanCode=0, so keep a complete desktop
        // fallback for Android key codes.
        if (event.scanCode in 1..0x2ff) return event.scanCode
        val key = event.keyCode
        if (key in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) {
            return letterKeys[key - KeyEvent.KEYCODE_A]
        }
        if (key in KeyEvent.KEYCODE_1..KeyEvent.KEYCODE_9) return key - 6
        if (key == KeyEvent.KEYCODE_0) return 11
        if (key in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F10) return key - 72
        if (key in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9) {
            return keypadDigits[key - KeyEvent.KEYCODE_NUMPAD_0]
        }
        return when (key) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> 1
            KeyEvent.KEYCODE_MINUS -> 12
            KeyEvent.KEYCODE_EQUALS -> 13
            KeyEvent.KEYCODE_DEL -> 14
            KeyEvent.KEYCODE_TAB -> 15
            KeyEvent.KEYCODE_LEFT_BRACKET -> 26
            KeyEvent.KEYCODE_RIGHT_BRACKET -> 27
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_CENTER -> 28
            KeyEvent.KEYCODE_CTRL_LEFT -> 29
            KeyEvent.KEYCODE_SEMICOLON -> 39
            KeyEvent.KEYCODE_APOSTROPHE -> 40
            KeyEvent.KEYCODE_GRAVE -> 41
            KeyEvent.KEYCODE_SHIFT_LEFT -> 42
            KeyEvent.KEYCODE_BACKSLASH -> 43
            KeyEvent.KEYCODE_COMMA -> 51
            KeyEvent.KEYCODE_PERIOD -> 52
            KeyEvent.KEYCODE_SLASH -> 53
            KeyEvent.KEYCODE_SHIFT_RIGHT -> 54
            KeyEvent.KEYCODE_ALT_LEFT -> 56
            KeyEvent.KEYCODE_SPACE -> 57
            KeyEvent.KEYCODE_CAPS_LOCK -> 58
            KeyEvent.KEYCODE_F11 -> 87
            KeyEvent.KEYCODE_F12 -> 88
            KeyEvent.KEYCODE_NUM_LOCK -> 69
            KeyEvent.KEYCODE_SCROLL_LOCK -> 70
            KeyEvent.KEYCODE_NUMPAD_SUBTRACT -> 74
            KeyEvent.KEYCODE_NUMPAD_ADD -> 78
            KeyEvent.KEYCODE_NUMPAD_DOT -> 83
            KeyEvent.KEYCODE_NUMPAD_ENTER -> 96
            KeyEvent.KEYCODE_CTRL_RIGHT -> 97
            KeyEvent.KEYCODE_NUMPAD_DIVIDE -> 98
            KeyEvent.KEYCODE_SYSRQ -> 99
            KeyEvent.KEYCODE_ALT_RIGHT -> 100
            KeyEvent.KEYCODE_MOVE_HOME, KeyEvent.KEYCODE_HOME -> 102
            KeyEvent.KEYCODE_DPAD_UP -> 103
            KeyEvent.KEYCODE_PAGE_UP -> 104
            KeyEvent.KEYCODE_DPAD_LEFT -> 105
            KeyEvent.KEYCODE_DPAD_RIGHT -> 106
            KeyEvent.KEYCODE_MOVE_END -> 107
            KeyEvent.KEYCODE_DPAD_DOWN -> 108
            KeyEvent.KEYCODE_PAGE_DOWN -> 109
            KeyEvent.KEYCODE_INSERT -> 110
            KeyEvent.KEYCODE_FORWARD_DEL -> 111
            KeyEvent.KEYCODE_MUTE -> 113
            KeyEvent.KEYCODE_VOLUME_DOWN -> 114
            KeyEvent.KEYCODE_VOLUME_UP -> 115
            KeyEvent.KEYCODE_POWER -> 116
            KeyEvent.KEYCODE_BREAK -> 119
            KeyEvent.KEYCODE_META_LEFT -> 125
            KeyEvent.KEYCODE_META_RIGHT -> 126
            KeyEvent.KEYCODE_MEDIA_NEXT -> 163
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_HEADSETHOOK -> 164
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> 165
            KeyEvent.KEYCODE_MEDIA_STOP -> 166
            KeyEvent.KEYCODE_MEDIA_REWIND -> 168
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> 208
            else -> null
        }
    }

    fun wheelUnits(axis: Float): Int {
        val units = (axis * 120f).roundToInt()
        return if (units == 0 && axis != 0f) if (axis > 0f) 1 else -1 else units
    }
}

private class GuestPresentation(
    context: Context,
    display: Display,
    private val socketPath: String,
    private val onState: (ExternalDisplaySnapshot) -> Unit,
) : Presentation(context, display), SurfaceHolder.Callback {

    private lateinit var surfaceView: SurfaceView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A Presentation is a Dialog. Its default Back handling dismisses the
        // whole external desktop; scrcpy maps right-click to Back, making the
        // presenter appear to crash during ordinary mouse use.
        setCancelable(false)
        setCanceledOnTouchOutside(false)
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        surfaceView = SurfaceView(context).also {
            it.setZOrderOnTop(false)
            it.holder.addCallback(this)
            it.isFocusable = true
            it.isFocusableInTouchMode = true
            it.setOnKeyListener { _, _, event ->
                val linuxCode = LinuxInput.keyCode(event)
                    ?: return@setOnKeyListener false
                val value = when (event.action) {
                    KeyEvent.ACTION_DOWN -> if (event.repeatCount == 0) 1 else return@setOnKeyListener true
                    KeyEvent.ACTION_UP -> 0
                    else -> return@setOnKeyListener false
                }
                NativePresenter.nativeInput(
                    LinuxInput.EV_KEY, linuxCode, value, 0, 0, 0,
                )
            }
            it.setOnGenericMotionListener { _, event ->
                handleGenericMotion(event)
            }
            it.setOnTouchListener { view, event ->
                val width = view.width
                val height = view.height
                if (width <= 0 || height <= 0) return@setOnTouchListener false
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN,
                    MotionEvent.ACTION_POINTER_DOWN,
                    MotionEvent.ACTION_UP,
                    MotionEvent.ACTION_POINTER_UP -> {
                        val index = event.actionIndex
                        NativePresenter.nativeTouch(
                            event.actionMasked,
                            event.getPointerId(index),
                            event.getX(index),
                            event.getY(index),
                            width,
                            height,
                        )
                    }
                    MotionEvent.ACTION_MOVE -> {
                        for (index in 0 until event.pointerCount) {
                            NativePresenter.nativeTouch(
                                MotionEvent.ACTION_MOVE,
                                event.getPointerId(index),
                                event.getX(index),
                                event.getY(index),
                                width,
                                height,
                            )
                        }
                    }
                    MotionEvent.ACTION_CANCEL -> NativePresenter.nativeTouch(
                        MotionEvent.ACTION_CANCEL, 0, 0f, 0f, width, height,
                    )
                    else -> return@setOnTouchListener false
                }
                true
            }
        }
        setContentView(surfaceView)
        hideAndroidChrome()
        surfaceView.requestFocus()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideAndroidChrome()
    }

    private fun hideAndroidChrome() {
        val presentationWindow = window ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            presentationWindow.insetsController?.run {
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsets.Type.systemBars())
            }
        } else {
            @Suppress("DEPRECATION")
            presentationWindow.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        // Pointer-class events are not guaranteed to reach a child view's
        // listener in a Presentation window (notably injected wheel events
        // on an own-focus external display). Intercept them at the window
        // boundary, which also covers real DP mice and touchpads.
        if (handleGenericMotion(event)) return true
        return super.dispatchGenericMotionEvent(event)
    }

    private fun handleGenericMotion(event: MotionEvent): Boolean {
        if (!event.isFromSource(InputDevice.SOURCE_CLASS_POINTER)) return false
        val view = surfaceView
        return when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_MOVE -> {
                sendPointerPosition(view, event)
                true
            }
            MotionEvent.ACTION_SCROLL -> {
                // Android wheel injection can arrive without a preceding
                // hover event. Move KWin's pointer first so the axis event is
                // delivered to the window under Android's supplied position.
                sendPointerPosition(view, event)
                val vertical = LinuxInput.wheelUnits(
                    event.getAxisValue(MotionEvent.AXIS_VSCROLL),
                )
                val horizontal = LinuxInput.wheelUnits(
                    event.getAxisValue(MotionEvent.AXIS_HSCROLL),
                )
                if (vertical != 0) NativePresenter.nativeInput(
                    LinuxInput.EV_REL, LinuxInput.REL_WHEEL_HI_RES,
                    vertical, 0, 0, 0,
                )
                if (horizontal != 0) NativePresenter.nativeInput(
                    LinuxInput.EV_REL, LinuxInput.REL_HWHEEL_HI_RES,
                    horizontal, 0, 0, 0,
                )
                if (vertical != 0 || horizontal != 0) {
                    NativePresenter.nativeInput(
                        LinuxInput.EV_SYN, LinuxInput.SYN_REPORT,
                        0, 0, 0, 0,
                    )
                    true
                } else false
            }
            else -> false
        }
    }

    private fun sendPointerPosition(view: SurfaceView, event: MotionEvent) {
        val maximumX = (view.width - 1).coerceAtLeast(0)
        val maximumY = (view.height - 1).coerceAtLeast(0)
        NativePresenter.nativeInput(
            LinuxInput.EV_ABS, LinuxInput.ABS_X,
            event.x.roundToInt().coerceIn(0, maximumX),
            0, maximumX, LinuxInput.SOURCE_ABSOLUTE,
        )
        NativePresenter.nativeInput(
            LinuxInput.EV_ABS, LinuxInput.ABS_Y,
            event.y.roundToInt().coerceIn(0, maximumY),
            0, maximumY, LinuxInput.SOURCE_ABSOLUTE,
        )
        NativePresenter.nativeInput(
            LinuxInput.EV_SYN, LinuxInput.SYN_REPORT,
            0, 0, 0, LinuxInput.SOURCE_ABSOLUTE,
        )
    }

    override fun surfaceCreated(holder: SurfaceHolder) = Unit

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (width <= 0 || height <= 0 || !holder.surface.isValid) return
        NativePresenter.nativeStop()
        val refreshRate = display.mode.refreshRate
        val nativeStarted = NativePresenter.nativeStart(
            holder.surface, socketPath, width, height, refreshRate,
        )
        Log.i(
            "DetExternalDisplay",
            "surface ${width}x$height @ $refreshRate: started=$nativeStarted",
        )
        onState(
            ExternalDisplaySnapshot(
                phase = if (nativeStarted) "ready" else "error",
                displayName = display.name,
                width = width,
                height = height,
                refreshRate = refreshRate,
                socketReady = nativeStarted,
                error = if (nativeStarted) "" else "native presenter failed to start",
            ),
        )
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        NativePresenter.nativeStop()
        onState(ExternalDisplaySnapshot(phase = "waiting"))
    }
}
