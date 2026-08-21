# Determination

Android convergence layer for Android 16

Android stays PID1; a Wayland desktop runs as an LXC guest
on the **same downstream vendor kernel**; `libhybris` bridges the guest to the
bionic GPU/display blobs. Shipped as a custom `boot.img` (custom kernel +
Magisk-patched ramdisk) plus a Zygisk module : **not a ROM**. `/system` and
`/vendor` stay stock.

Two modes:

- **External convergence** (concurrent): SurfaceFlinger keeps the internal
  panel, the guest compositor drives a DP-alt external display. Both live.
- **Internal on-demand desktop*: SF is stopped and
  respawn-masked, the guest compositor takes the panel via hwcomposer, input is
  handed off with `EVIOCGRAB`.





## Repo layout

| Path | What |
|---|---|
| `recon/` | §9 device recon : run first, with the phone attached |
| `kernel/` | kconfig fragment (container enables) + fetch/build scripts for the downstream SM8150 kernel |
| `boot/` | boot.img unpack/repack with the custom kernel; Magisk patching flow |
| `magisk-module/` | the on-device Determination Magisk module: container launch, boot hooks, sepolicy rules |
| `guest/` | Debian baseline plus experimental Arch Linux ARM/Alpine rootfs builders; shared LXC, libhybris, and session contract |
| `toggle/` | §4 internal-panel handoff: SF stop + respawn suppression + compositor swap + input grab; plus `det-hostagent` (guest→host control channel) |
| `control/` | native `detd` state/API owner, `detctl` client, durable-state/protocol core, and host tests |
| `audio/` | direct ALSA hardware inventory and journalled ownership binaries |
| `companion/` | Android UI and permission facade: mode confirmation, status/API, Quick Settings, share sheet, optional external presenter |
| `tools/evgrab/` | small C daemon that holds `EVIOCGRAB` on evdev nodes during desktop mode |
| `usb-install/` | cable-free install: Magisk action zips that flash/restore the kernel from a USB drive on the phone itself |
| `zygisk/` | Zygisk/LSPosed module for `system_server` hooks |
| `docs/` | Current wiki: guides, architecture, reference, operations, qualification, and separated history |

## Host validation

Run every host-safe check from the repository root:

```sh
./tools/check-host.sh
```



## Linux-first profile

Supported device profiles can request a health-gated Linux-first startup while
retaining the minimum Android and vendor services needed for the downstream
kernel, radio, thermal, power, binder, and qualified networking stack:

```sh
det linux-first status
det linux-first enable
det linux-first apply
det linux-first disable
```

A failed automatic attempt returns to phone mode and disables automatic retry
until it is explicitly enabled again. See the
[boot-profile reference](docs/reference/device-and-boot-profiles.md) and
[recovery guide](docs/guides/install-and-recovery.md) before enabling it.

## Bring-up order (risk-ordered milestones)



## Guest SSH

The guest SSH server is public-key-only. The host routes the private guest
subnet through the phone's current Wi-Fi address, giving the container a real
directly reachable address:

```sh
det ssh-setup                    # server, public key, SSH config, host route
ssh melissa@192.168.117.2        # exactly this; no ProxyCommand
det ssh-route                    # refresh after phone DHCP or host route changes
det motd-setup                   # refresh the guest's dynamic login banner
```

Pass an existing public key to `det ssh-setup` if preferred. Set
its matching private key in `~/.ssh/config.d/determination` when it is not the
default dedicated `~/.ssh/determination_ed25519` key.

## Status

- [x] Repo scaffolding, recon script, kernel fragment, Magisk module, guest
      builder, toggle scripts, evgrab
- [x] Recon on real device over wireless adb → `docs/recon-findings.md`
      (crDroid 12.10/A16, HIDL composer 2.4, gralloc4, binderfs present,
      DP-alt works)
- [x] Kernel built (crDroid 16.0 tree + running config + fragment, 3m13s),
      `boot/determination-boot.img` repacked from the dumped boot_b and verified
- [x] Module zip packaged with static aarch64 evgrab; `./det` host helper
- [x] Cable-free install path: `usb-install/` action zips + `./det publish`
      (flash via Magisk app + `dd`; rescue from a *bootloop* still needs a cable)
- [x] **FLASHED AND BOOTING** (2026-07-02, via the USB-drive path): kernel
      `4.14.357-perf-g96adfa8256dc` live on device, PID/USER/IPC_NS confirmed.
      WiFi initially exposed a `qca_cld3_wlan.ko` vermagic mismatch; the current
      kernel build carries the matching module directly, so the old Magisk WLAN
      overlay has been retired. Full hardware smoke test green. Determination
      module installed. Milestone 1 done.
- [x] Guest rootfs + libhybris smoke test on guacamoleb (2026-07-04, TLS wall
      cleared with upstream libhybris; `test_hwcomposer` GLES 3.2 on the panel)
- [x] wlroots on the panel: phoc + phosh + squeekboard live, touch-verified
      (2026-07-06/07); GPU app buffers zero-copy path working (2026-07-10)
- [x] Toggle round trip cable-free: companion app Enter, guest launchers /
      phosh power menu Exit, verified on-device (2026-07-11) : milestone 4 done
      (QS tile confirmed)
- [x] Milestone 6: Zygisk hook on system_server's SF-death handling :
      verified on device 2026-07-11: system_server stable, WiFi stays up,
      guest networking alive throughout desktop mode
- [x] Debian application-session compatibility layer (2026-08-21): Phosh now
      runs in an active PAM/logind Wayland login with its standard systemd user
      bus, XDG portals, Secret Service, accessibility, feedback, GVfs, Flatpak,
      native Wayland app hints, and user-owned GNOME settings. The live contract
      passed 17/17 checks and GNOME Calculator launched through its desktop
      entry. This qualifies the session plumbing, not every individual app or
      hardware API.
- [x] Milestone 5 phase 1: native graphics/KMS path proven (2026-07-13/14) :
      Turnip on KGSL, minigbm allocation, dmabuf→Vulkan import, raw DSI KMS
      scanout, and Plasma Mobile under KWin with GPU compositing + touch.
      This is retained as an explicit native-Mesa experiment, not the portable
      product renderer.
- [x] Compatibility KWin path: vendor EGL/GLES through libhybris, Android
      gralloc allocation, and minigbm as the compositor-facing GBM layer. The
      first shared-buffer interop gate passed on-device (2026-07-19): vendor
      Adreno rendered through a reconstructed full native handle, pixel readback
      through the original allocation matched, and minigbm imported/re-exported
      its pixel dma-buf. The display-safe 1080x2340 benchmark completes four
      fullscreen textured/blended layers in 4.263 ms mean / 4.625 ms p99;
      full-handle and minigbm setup cost 8 us and 92 us mean respectively.
      Direct KWin integration, authoritative plane metadata, presentation, and
      sync-fence transport remain.
- [ ] Milestone 5 phase 2: concurrent external convergence : Android/SF keeps
      the panel while a guest-rendered dmabuf is presented on DP-alt
- [x] Direct audio : the internal-speaker alpha is hardware-proven on
      `guacamoleb` (2026-08-02): journalled Android ownership, direct ALSA and
      PipeWire playback, normal desktop lifecycle integration, and exact
      mixer/service restoration pass on-device. Volume/mute, headset, DP/USB,
      suspend/cable/crash stress, and latency/xrun qualification remain.
