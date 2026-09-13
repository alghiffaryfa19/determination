# Troubleshooting

Field-tested failure modes. Every entry here was diagnosed on guacamoleb the
hard way - do not "simplify" the fixes without rereading the linked evidence.

## Screen stuck on last boot-animation frame after desktop-off

`service.bootanim.exit 1` is a *symptom*, not the cause.

1. Check Watchdog: `det log main | grep -i watchdog`
2. Look for `Blocked in handler on main thread` + `ChargingControlController`.

If present, this is the lazy-HAL wedge: `vendor.lineage_health` idles out and
unregisters while system_server is SIGSTOP-frozen during a desktop session.
crDroid's servicemanager cannot lazy-restart it, so the respawned
system_server blocks forever waiting for `IChargingControl`, Watchdog kills it
in a loop, and nothing ever draws over bootanim's final frame.

Fix: `desktop-off` runs the health-HAL keeper (re-asserts
`start vendor.lineage_health` across the ss boot window) plus the bootanim
keeper. If you see this anyway, the keepers did not run - check
`toggle/desktop-off` step 1c/3b on-device under `/data/determination/bin/`.

## Guest never starts / su returns permission denied

The Magisk Superuser "Shell" toggle is off. Enable it in the Magisk app.
Never run `adb root` - it drops wireless transports.

## sudo inside guest says "effective uid is not 0 ... nosuid"

Android's `/data` is `nosuid,nodev`; the container rootfs inherits it after
pivot, so setuid bits are ignored. `guest-start` remounts the container root
`suid,dev,exec` post-start (the host-side bind remount does not reach the
pivoted root on 4.14). If sudo still fails, also run `det passwd` once -
sudo is password-gated for detuser.

## Watchdog kill-loop right after entering desktop mode

Expected protection: `desktop-on` step 3b SIGSTOPs system_server at handoff so
its `android.display` thread cannot accumulate 60s of block time. If you
removed or reordered that step, the framework Watchdog fires within minutes.
Do not replace the freezer with signal hooks: PLT-hooking
`kill`/`tgkill`/`abort`/`exit` in system_server libraries registered but never
fired (2026-07 experiment, abandoned).

Conversely, leaving desktop mode must **SIGKILL** the frozen system_server
(`desktop-off`). SIGCONT would unblock a Watchdog that immediately self-kills
from accumulated block time; SIGKILL lets init/zygote respawn it fresh.

## Battery percentage stuck while charging

UPower reads the raw `battery/capacity`, which the qpnp-smb5 charger freezes
on some states. `det-battery` bind-mounts the corrected `bms` capacity over
it, re-asserted every poll pass because the charger re-enumerates its
power_supply node on USB plug/unplug and silently drops the bind.

Separate known quirk: UPower reports `discharging` while charging (`ac`
line_power online=0; only `pc_port`/`usb` are online=1). Pre-existing,
cosmetic.

## phoc exits with rc 139 during teardown

Cosmetic segfault at shutdown, after the session has ended. Ignore unless it
appears before first frame.

## GSK/GTK apps crash with shader compile errors on Adreno

Adreno driver mis-compiles varying struct layouts in GTK4's NGL renderer. The
libhybris build carries a GSK rewrite hook; ensure guests use it
(`guest/build-libhybris.sh`) and `GSK_RENDERER=ngl` is set
(`/etc/profile.d/hybris.sh`). Matrix flat varyings (mat3/mat4) remain
unverified in the fix.

## GPU clients fail with EGL_BAD_DISPLAY or software rendering

Hybris wayland platform requires per-app env:
`EGL_PLATFORM=wayland HYBRIS_EGLPLATFORM=wayland`. Gate with
`guest/gpu-smoke.sh` before blaming the stack. Vendor EGL always goes through
libhybris; gralloc stays Android-owned; minigbm supplies compositor-facing GBM.

## Desktop mode has no /sdcard

FUSE is unavailable while system_server is frozen (framework thrash). Stage
files through `/data/local/tmp` instead.

## Container PTYs broken (can't allocate tty)

`guest-start` remounts devpts and symlinks `/dev/ptmx` (ptmxmode=000 kernel
default workaround). Verify the post-start block ran by checking for the
symlink inside the container root.

## glib child-watch hangs launching sessions

Never start sessions with `phoc -E`: pidfd support is half-backported on
4.14.357, breaking glib's child watch. The `det-pidfd-shim.so` LD_PRELOAD
forces the SIGCHLD fallback by making `pidfd_open` return ENOSYS. Sessions
launch through `det-session-manager`/`det-phosh-session` instead.

## Zygisk modules stopped loading after update

ReZygisk requires native Zygisk to stay disabled (`zygisk=0`) and both ABI
libraries present (arm64-v8a + armeabi-v7a). A missing v7a .so silently
disables the whole module.

## Kernel/config changes vanish on boot

The running config is merged from `determination.config` by
`kernel/build.sh`; flashing a stock boot.img or OTA revert wipes the custom
kernel. Recovery path: `usb-install/host-flash.sh restore` using backups in
`/sdcard/Download/boot_a-before-determination-*.img`.
