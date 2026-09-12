# Aurora companion app

A native Android controller to drive Aurora without a
computer attached. It uses the versioned local control bridge when available
and labels the direct Magisk `su` path as an emergency compatibility fallback.

## What it does

- **Live status** : mode (phone/desktop), guest container state, SurfaceFlinger
  state, host-agent state, kernel.
- **Enter Desktop Mode** : one tap: ensures the guest is up, then launches
  `desktop-on` *detached* (it survives the app being killed when SurfaceFlinger
  stops and the Android UI hands off to the panel).
- **Quick Settings tile** : pull down the shade, tap once to enter desktop mode.
- **Exit Desktop Mode** : runs `desktop-off`. Mostly a fallback: once you're in
  desktop mode the Android shade is gone, so the normal way back is the
  in-desktop **Exit to Phone Mode** launcher / power menu (guest-side, see
  `guest/setup-controls.sh`).

The division is deliberate: this app is the **enter** side (phone UI), the guest
launchers are the **exit / power** side (desktop UI). Together = full round trip
from the touchscreen, no cable.

## Building

No Gradle wrapper jar is committed. Either:

- **Android Studio** : open `companion/` and let it sync (it provisions the
  wrapper from `gradle/wrapper/gradle-wrapper.properties`), then Run, or
- **CLI** : `cd companion && gradle wrapper && ./gradlew assembleDebug`
  (needs a local Gradle ≥ 8.7 and an Android SDK with API 34).

Install the debug APK: `adb install app/build/outputs/apk/debug/app-debug.apk`.

## Requirements

- Aurora installed on-device (`/data/aurora`, kernel + Magisk
  module flashed).
- Magisk su granted to `com.aurora.companion` (Superuser tab; screen
  unlocked for the grant prompt).

The companion reports bridge status when the installed module supports it. A
successful request can mean accepted rather than completed; recovery-required
is a state to resolve, not a successful transition. See the
[documentation home](../docs/README.md) for current operational guidance.

## Installation ownership

System installation, updates, porting, and boot recovery are owned by the
[PC workbench](../installer/README.md). The companion retains mode control,
Linux package management, session selection, diagnostics, and power controls.
The installation wizard, release downloader, local updater, and boot writer
have been removed from the APK.
