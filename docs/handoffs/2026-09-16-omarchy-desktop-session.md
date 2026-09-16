# Session handoff: Omarchy desktop, audio, hotplug, input

Date: 2026-09-16
Scope: one working session on the reference phone. Engineering only; the
long-term vision lives elsewhere and is not required to continue this work.

## Device state

- Wireless adb: `192.168.0.164:5555` (USB was unplugged for the monitor test).
  After a phone reboot: `adb tcpip 5555` over USB, then `adb connect`.
- Guest: ALARM running the `omarchy` session, HWC multi-display backend.
- Monitors: `HWC-1` 1080x2340 @ scale 2.0, `HWC-EXT-1` 1920x1080 @ scale 1.5.

## Landed and verified on the phone

- Omarchy shell starts: module zip mode preservation, `LD_LIBRARY_PATH` in
  `aurora-omarchy`, exec bits restored, `guest-start` self-heal.
- Reload-loop fix: the config no longer loads a missing plugin; `hyprgrass`
  is now built from the revision pinned to Hyprland 0.49 (`51da8d1`) and loads.
- Icons: `ttf-jetbrains-mono-nerd` plus the monospace fontconfig alias.
- Apps: extended profile installed (foot, firefox, thunar, mousepad,
  galculator, loupe, papers, file-roller, inotify-tools).
- Audio: claim reachable on existing installs (stale `AURORA_PROFILE_ID`),
  PipeWire graph up, 440 Hz tone verified, volume keys drive the guest sink
  and raise the OSD via `aurora-audio-volume`.
- `hyprland-qtutils` built and installed; `ANRManager` and
  `DynamicPermissionManager` start.
- External monitor hotplug: multi-display aquamarine deployed
  (`HWC connected HWC-EXT-1`), extended desktop on its own workspace.
- External input: `aurora-input-proxy` cross-built, unit installed and
  enabled; host bridge active, guest logs "ready".
- Layout: gaps 2/4, 3px themed border, rounding 22, terminal swallow,
  XWayland zero scaling, flat pointer accel.

## Commits

`d8b79c5` omarchy shell launch · `f733c1f` reload loop + fonts · `cbc1c97`
audio claim · `9428bd3` hyprctl · `7e4da99` PAM/Polkit quickshell · `ae34002`
hyprgrass · `8bef134` qtutils · `43ab459` HWC hotplug · `df8f420` input proxy ·
`c705524` volume keys + app profile · `428395a` layout tuning · `8229323`
capability-bridge design doc.

## Open threads

1. `docs/android-capability-bridge.md` is public pending the owner's call on
   whether it belongs on a private branch.
2. P0 (read-only capability inventory) is safe to start. P1 (selective
   `system_server` thread freeze) needs explicit authorization for one
   desktop-mode cycle.
3. Monitor **unplug** path untested; the watcher is at
   `/data/aurora/log/hotplug-watch.log` on the phone.
4. DP audio is blocked at the kernel: no `msm-dp-audio` driver, no ELD, no
   device-tree audio node. Needs a kernel/DT project, not a mixer tweak.
5. Idle lock is deliberately not implemented: an `ext-session-lock` surface
   hides squeekboard, so a phone with no hardware keyboard could not unlock.
6. Gesture bindings are live (3-finger tap = menu, swipe up = apps, etc.);
   worth a human pass.
7. `tools/check-repo.sh` currently fails four release checks because of
   in-flight work on the v0.5.0-alpha.2 manifest and pins by another author.
