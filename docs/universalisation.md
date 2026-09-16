# Project Universalisation

> This document covers **device portability**. The other half of
> universalisation — consuming Android services and vendor HALs from Linux —
> is a separate project documented in
> [android-capability-bridge.md](android-capability-bridge.md).

Aurora currently has one proven device: OnePlus 7 `guacamoleb`. The
portable architecture is a hypothesis until a second device crosses a
meaningfully different hardware or Android axis. This document tracks the work
needed to make that hypothesis testable.

## Configuration contract

Host-side scripts source `/data/aurora/bin/device-config`. It discovers
safe defaults at runtime and then applies the data-only overrides in
`/data/aurora/etc/device.conf`.

Currently generated and consumed, with incomplete paths called out below:

| Key | Discovery/default | Consumers |
|---|---|---|
| `AURORA_BACKLIGHT_PATH` | known Android paths, then first backlight node | HWC and native toggle paths |
| `AURORA_BACKLIGHT_LEVEL` | one third of `max_brightness` | HWC and native toggle paths |
| `AURORA_WIFI_IFACE` | first `wlan*` or `wifi*` interface | guest network keeper/routing |
| `AURORA_HWC_OUTPUT` | `HWCOMPOSER-1` | generated phoc configuration |
| `AURORA_PANEL_WIDTH`, `AURORA_PANEL_HEIGHT` | Android physical display size | scale calculation and diagnostics |
| `AURORA_OUTPUT_SCALE` | approximately 360 logical pixels wide | generated phoc configuration |
| `AURORA_BATTERY_GAUGE` | unset | guest battery translator |
| `AURORA_INPUT_QUIRK` | `none` | classified libinput workaround |
| `AURORA_DRM_CARD` | `/dev/dri/card0` | reserved for generated native-display config |
| `AURORA_DRM_RENDER_NODE` | first render node, then card | minigbm and graphics interop probes |
| `AURORA_GRAPHICS_RENDERER` | `libhybris` | graphics policy; native Mesa requires an explicit diagnostic override |
| `AURORA_GBM_PROVIDER` | `minigbm` | compositor-facing GBM policy; not the GPU renderer |

`AURORA_DRM_CARD` is emitted by recon but is not yet wired through every native
display consumer. It must not be advertised as complete portability.

The graphics keys now enforce the product default and guard the old native-Mesa
launcher, but they do not imply that the direct KWin compatibility winsys is
finished. Its remaining plane-metadata and fence work is tracked in
`docs/graphics-architecture.md`.

`recon/recon.sh` now records identity, backlights, network interfaces, power
supplies, and DRM connectors and emits `device.conf` beside the raw report.
Review that file before installing it; recon does not guess vendor quirks.

`recon/classify.py` converts the raw report into `capabilities.conf` and a
human-readable `compatibility.txt`. It classifies composer, mapper, allocator,
GPU, binder, DRM, kernel requirements, and boot layout. Unsupported composer
APIs and missing hardware identities are blockers; kernel rebuilds and unproven
GPU or boot paths are reported as explicit porting work.

Before every guest start, `generate-lxc-config` rebuilds the runtime LXC config
from `config.base`. It selects binderfs or direct binder sources, canonicalises
them inside the guest, and includes only device families present on the phone:
KGSL, Mali, PowerVR, Vivante, ashmem/ION/dma-heaps, DRM, input, audio, and legacy
graphics. Uncommon nodes can be supplied through `AURORA_EXTRA_DEVICES`. The exact
result is recorded in `/data/aurora/lxc/device-manifest`.

Known profiles live in `device-profiles/`. The Magisk installer selects a
profile only on an exact `ro.product.device` match. Unknown phones retain
runtime discovery rather than inheriting OnePlus-specific values.

## Portability axes

| Axis | Classes to support | Current state |
|---|---|---|
| Composer | HIDL 2.x, AIDL composer3 | HIDL 2.x proven; AIDL unsupported |
| Allocator | gralloc3/4, mapper3/4, AHardwareBuffer | QTI gralloc4 proven |
| GPU | Android vendor EGL/GLES through libhybris | Adreno vendor blob proven; other families require device ports |
| Compositor buffers | Android gralloc + minigbm GBM facade | full-handle shared-buffer round trip passed on QTI gralloc4/minigbm; plane metadata and fence bridge pending |
| Display | HWC exclusive, native DRM exclusive, Android presenter external | first two proven on SM8150 |
| Kernel | vendor 4.x through modern GKI | 4.14 proven; fragment partly generic |
| Input | evdev + `EVIOCGRAB`, uinput return path | evdev handoff proven |
| Boot | A/B boot image layouts, vendor_boot/init_boot | legacy A/B boot proven |

## Next implementation slices

1. Generate the remaining guest display metadata: DT compatibles, touch-to-
   output mapping, rotation, and panel cutout geometry.
2. Split quirks into independently selected classes (kernel, GPU blob,
   composer, display driver), with explicit probes and failure messages.
3. Make kernel building consume a device build manifest rather than the
   guacamoleb source tree and captured config.
4. Port a second phone chosen to invalidate assumptions: preferably AIDL
   composer or Mali on a modern GKI kernel.

The acceptance test is not “the profile file exists.” A clean recon must
produce configuration that reaches a guest shell, renders a smoke frame,
hands input over, and restores Android without hand-editing scripts.
