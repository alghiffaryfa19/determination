# Arch / Opal bring-up checkpoint

Evidence: `artifacts/opal-arch-bringup/` (September 2026).

## Operating constraint

The current user instruction is **no mode switches**. Continue host builds and
phone-mode-safe probes only. Do not start a compositor, acquire hwcomposer, stop
SurfaceFlinger, restart the framework, or schedule a restore timer to validate
these changes. A previous full reboot is confirmed by uptime and boot reason;
its cause is not established. Pstore was empty after recovery.

## Installed and verified

- Arch boots, root works, and firstboot provisioning completes.
- Both Android 16 hwcomposer compatibility libraries build and are installed.
- Arch-built libhybris renders through vendor Adreno EGL. The native-buffer
  smoke test passes 1,200 rendering/fence/readback cycles with stable descriptor
  counts, including as unprivileged `aurora` (uid 1000).
- Hyprland and a private Quickshell/Qt runtime are under `/opt/hyprland`.
  Cached compositor artifacts still use the earlier environment contract;
  staging wrappers adapt it. These are bring-up binaries, not clean release
  builds. New source/build paths use `graphics/hyprland` and `guest/*hyprland*`.
- Guest tools are restored from `/data/aurora/guest-tools` during `guest-start`.
  Updating only the active rootfs is not persistent; update the payload too.

## Input: two independent failures

### Device enumeration

Arch's installed libudev returned `scan_rc=-49`, enumerating zero input nodes.
The identical unprivileged probe with libudev 257.13 enumerated all 13 nodes.
The runtime library is private at `/opt/hyprland/lib/compat/libudev.so.1`; the
Hyprland launcher searches that directory first. Do not replace Arch's system
library or remove the systemd package pin.

The tested binary was Debian's `libudev1:arm64` 257.13-1~deb13u1. The Arch
systemd cross-build now also stages its source-built 257.13 library in this
private location. That source-built artifact still needs the same device
qualification before replacing the tested binary.

### Touchscreen acceptance

The phone's generated profile omitted the existing device-specific input quirk.
Libinput rejected `touchpanel` because `ABS_MT_WIDTH_MAJOR` has minimum equal to
maximum. The host device configuration now selects
`AURORA_INPUT_QUIRK=oneplus-touchpanel-zero-axes`. `generate-guest-config` writes
`/usr/share/libinput/99-aurora.quirks` on each guest start, masking the two bogus
axes and setting direct-touch properties. It leaves user-owned
`/etc/libinput/local-overrides.quirks` untouched.

A display-safe libinput context, without EVIOCGRAB, verified six accepted devices:
five keyboard-only devices and `touchpanel` with touch and keyboard capability.
SurfaceFlinger remained running. This proves enumeration and acceptance, **not**
touch delivery to a compositor, gesture behavior, or input arbitration.

## Remaining Opal work

The initial Quickshell runtime lacked the Qt Wayland platform plugin. The
cross-build container now includes `qt6-wayland:arm64` and the required QML
runtime modules, in addition to development headers. The rebuilt Quickshell
0.3.0 and matching private Qt runtime are installed. Both Wayland platform
plugins resolve their dependencies with the launcher's `LD_LIBRARY_PATH`;
the initial plain `ldd` invocation omitted it and incorrectly suggested missing
Qt libraries. Never mix Qt private-API versions.

`aurora-opal check` now checks the executable and both Wayland plugins for
unresolved dependencies, then runs `quickshell --version`. This passes as the
unprivileged guest user. The updated launcher is installed in both the active
rootfs and persistent guest-tools payload. Evidence:
`artifacts/opal-arch-bringup/resumed-preflight.log`.

A windowless import probe also passes on-device as `aurora`, loading Qt Quick,
Controls, Layouts, Models, and Quickshell's Hyprland, Wayland, I/O, notification,
and tray modules. It exits successfully after `OPAL_QML_IMPORTS_OK`; see
`artifacts/opal-arch-bringup/qml-import-probe.qml` and its `.log`. The probe uses
Qt's offscreen platform with no windows or rendering, so it does not qualify
vendor graphics or the complete Opal configuration.

The same pass reconfirmed six accepted input devices including one touchscreen,
with SurfaceFlinger running and uninterrupted uptime. Shell rendering, touch
delivery, and gestures still require a separately authorized desktop session.

The companion's new gradient ribbon icon builds successfully. The latest
blended revision was installed successfully during the preceding Pi session.
Source artwork is `companion/branding/aurora.svg`. Run
`python3 companion/branding/generate.py` after changing it, and `--check` to
verify the three generated Android vectors.

## Regression checks

- `sh guest/tests/platform-runtime-test.sh`: provisioning must not explicitly
  target an already-installed, kernel-qualified systemd with pacman.
- `sh toggle/tests/guest-input-config-test.sh`: correct touchscreen quirk,
  readable permissions, idempotence, and preservation of user overrides.
- `sh guest/tests/hyprland-launch-test.sh`: launcher environment and privilege
  boundaries.
- `sh guest/tests/opal-runtime-test.sh`: missing plugins, unresolved dependencies,
  and executable failures must fail the display-safe preflight.
- `python3 companion/branding/generate.py --check`: artwork/vector consistency.
