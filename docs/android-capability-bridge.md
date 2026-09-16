# Universalisation: Android as a service provider

Status: planned project
Authority: design
Last reviewed: 2026-09-16

This document describes a multi-phase project. Nothing in it is implemented
unless a slice says so. Read [design-spec.md](design-spec.md) first; the
product invariants there still apply.

## 1. Thesis

Aurora keeps Android as PID 1 and runs a Linux guest on the same kernel. In
internal desktop mode it currently treats Android as an adversary: it stops
SurfaceFlinger, grabs the panel through the composer HAL, and **SIGSTOPs
`system_server`** so the framework Watchdog cannot kill it while its display
path blocks.

That freeze is a workaround, not a design. It also costs real capabilities:
Wi-Fi, Bluetooth, telephony, sensors, GNSS and every framework-owned service
are dead for the whole desktop session, and HALs that idle out during the
freeze wedge the exit path (see the `vendor.lineage_health` incident in
`AGENTS.md`).

The project inverts the relationship. Android stays alive as a **capability
provider**, and Linux consumes those capabilities through a typed, journalled
contract instead of reimplementing vendor drivers. Universalisation means:

- **Universal across devices**: the Linux side talks to capability contracts,
  not device-specific drivers. Porting becomes a negotiation problem, not a
  driver project. See [universalisation.md](universalisation.md) for the
  device-portability contract this builds on.
- **Universal across Android versions**: assume a modern Android (11+; AIDL
  HALs, `cmd` tooling, binderfs). Android 4-era support is explicitly out of
  scope. Versions are handled by **runtime capability negotiation**, never by
  version checks or per-ROM branches.

## 2. Non-goals and invariants

The project must not break the existing product contract.

- Never a ROM. `/system` and `/vendor` stay stock; delivery stays boot image +
  Magisk module + guest.
- Graphics stay on the current compatibility path: vendor EGL/GLES through
  libhybris, Android gralloc buffers with complete native handles and sync
  fences, presentation through hwcomposer. See
  [graphics-architecture.md](graphics-architecture.md).
- Audio stays a **Linux hardware stack**. Android's audio HAL, AudioFlinger
  and Binder are never a PCM transport. The HAL may be *arbitrated* through
  the host broker; it may not carry samples. See
  [audio-architecture.md](audio-architecture.md).
- Android remains PID 1 and owns the radio hardware. Linux requests; it does
  not silently steal interfaces.
- No `adb root` in any procedure.
- A desktop-mode transition is still a mode switch. It requires explicit
  authorization and the live-test protocol in section 8.

## 3. The freeze, and how to escape it

Mechanism, in order of the call path:

1. Internal desktop mode stops SurfaceFlinger and its respawn.
2. The guest's hwcomposer client becomes the HAL's single client and drives
   the panel.
3. `system_server`'s display path blocks on the now-dead display stack.
4. The framework Watchdog sees a blocked monitor for 60 s and kills
   `system_server`, which respawns and loops.
5. Today's answer: `ss-freezer` SIGSTOPs the entire process for the session.

Escaping it does not require giving the panel back.

### 3.1 Selective freeze (preferred, first slice)

The Watchdog only needs one thread to be neutered. Freeze the **blocked
display threads and the Watchdog thread itself**, not the process. Everything
else keeps running: binder thread pools, `WifiService`, `BluetoothService`,
sensors, telephony, `audioserver` coordination, and HAL lifecycle management.

Consequences that make this worth doing first:

- the connectivity broker (`aurora-connectivity` → `aurora-hostagent` →
  `cmd wifi ...`) works *during* desktop mode instead of rejecting calls;
- nothing idles out, so the lazy-HAL exit wedge disappears;
- the freeze becomes a scoped, explainable mechanism instead of a bludgeon.

Thread selection is by name from `/proc/<pid>/task/<tid>/comm` (for example
`Watchdog`, `android.display`, `android.ui`, `DisplayManager` owners). The
selection list is data, not code, so a new Android version can adjust it
without a rebuild.

### 3.2 Fallbacks, in order

1. Java-level Watchdog defusing (LSPosed/Xposed hook) if selective freezing is
   not sufficient on some framework version. The existing native PLT hooking
   angle is recorded as failed in `AGENTS.md`; do not retry it.
2. Presenter path: keep SurfaceFlinger alive on the panel and let Linux render
   to a virtual display consumed by the Android presenter. This is the
   external-convergence design and stays a separate track.
3. Full freeze (today's behaviour) as the compatibility floor. It must remain
   workable for every capability slice: no slice may *require* the freeze to
   be gone.

## 4. Architecture

Three tiers, all behind one Linux-facing contract.

```
Linux app ── aurora-* CLI / DBus ── guest broker
                                        │  control channel (existing)
                                        ▼
                                  host broker (aurorad + hostagent)
                                        │
                    ┌───────────────────┼────────────────────┐
                    ▼                   ▼                    ▼
          framework API (cmd,      vendor HAL (libgbinder,   kernel/sysfs
          binder through           HIDL or AIDL)            (netdev, nodes)
          servicemanager)
```

**Tier 1 — framework API.** Today's `aurora-hostagent` style: `cmd wifi`,
`cmd bluetooth_manager`, binder through `servicemanager`. Cheap, already
proven, but bounded by framework policy and only available while the framework
lives.

**Tier 2 — direct vendor HAL.** `libgbinder` reaches `hwservicemanager` /
`servicemanager` directly. This is where capabilities the framework hides
live: full scan IEs, P2P/AP control, raw sensor rates, codec enumeration,
display config/color, charging control. It is also the tier that makes the
contract portable: vendor HAL families and versions are the real porting
surface, and they are negotiable.

**Tier 3 — kernel and sysfs.** The fallback when a HAL owns nothing useful:
netdev and nl80211 for interface state, power supplies, thermal zones, DRM and
input nodes. Always available, always non-portable.

### 4.1 Capability discovery

Every capability is described, never assumed:

```json
{
  "id": "wifi",
  "tier": "framework",
  "backend": "cmd wifi",
  "available": true,
  "exclusive": false,
  "notes": "scan/connect/forget; AP mode needs tier 2"
}
```

`aurora-capabilities` (name provisional) prints this inventory. It is
read-only, safe in every mode, and is the first artifact of every port: a new
device is "supported" for a capability when the inventory shows a backend that
the tests exercise.

### 4.2 Ownership and leases

HALs on this platform are frequently single-client and stateful, and Android
services may reclaim what they think they own. The audio path already solved
this shape and its pattern is the model to copy:

- snapshot the owned state before taking it, into a journal,
- publish an explicit claim,
- verify the takeover, and
- restore on release, verifying the original owner converged back.

Every capability that takes exclusive ownership reuses that pattern: journalled
claim/restore, never a silent takeover, and a visible failure when restore
cannot be verified. Shared capabilities (sensors, GNSS reads) need only
lifecycle coordination.

### 4.3 Failure model

- Every broker call has a bounded timeout and a typed error, never a bare
  failure string.
- A capability that cannot be restored is marked degraded and reported, not
  silently dropped.
- Framework death or restart must not strand a claim; the host broker owns
  cleanup.
- Guests are distro-neutral: the contract is a CLI plus a DBus interface, not
  a Python or glibc dependency.

### 4.4 Security

Tier 2 is powerful: binder access from the guest can reach vendor HALs that
control radios, keys and cameras. Rules:

- expose **typed operations with capability scoping**, never an arbitrary
  binder proxy or shell escape;
- the guest is a trusted boundary already (it owns the display and input), but
  each new operation still needs its own review;
- secrets (Wi-Fi passphrases, lock credentials) never enter logs, artifacts,
  preferences or the clipboard history;
- any operation that can alter another owner's data (forget network, radio
  reconfiguration, AP mode) gets a journal entry and an explicit confirmation
  in the UI path.

## 5. Capability inventory

Probed from `lshal` on the reference device (`guacamoleb`, Android 16). HAL
families are version-negotiated at runtime; the list below is what the broker
must expect to see on this class of device, not a hard dependency.

| Capability | Android owner today | Candidate backend | What Linux gains | Tier | Notes |
|---|---|---|---|---|---|
| Wi-Fi | `WifiService`, `wpa_supplicant` | `cmd wifi`, `vendor.qti.hardware.wifi@*` | scan, connect, forget, later AP/P2P | 1 → 2 | the headline ask; must respect Android's regulatory state |
| Bluetooth | `BluetoothService`, `IBluetoothHci` | `cmd bluetooth_manager`, `android.hardware.bluetooth@1.x` | pairing, HID, A2DP, RFCOMM | 1 → 2 | BT audio is a different owner than the codec |
| Telephony/SMS | `Telephony`, `vendor.oplus.hardware.radio` | framework broker | calls, SMS, data state | 1 | privacy-sensitive; read-mostly first |
| GNSS | `vendor.qti.gnss@*` | framework broker, then HAL | position fixes for Linux apps | 1 → 2 | HAL can drive the chip directly; sharing with Android needs a lease |
| Sensors | `android.frameworks.sensorservice` | framework broker, then HAL | accelerometer, proximity, light, hall | 1 → 2 | high-rate streams are tier 2 only |
| Camera | `camera.provider@2.4` | framework broker | capture for Linux apps | 1 | heavy; later phase |
| Biometrics | `biometrics.fingerprint@2.x` | framework broker | authentication prompts | 1 | must integrate with the OSK/lock design, not bypass it |
| Charging/power | `vendor.lineage.health`, power supplies | HAL, sysfs | charge control, battery health, thermal limits | 2 → 3 | the exit-wedge HAL lives here |
| Thermal | thermal HAL, thermal zones | framework, sysfs | throttling control | 1 → 3 | feeds performance profiles (`aurora power`) |
| Display extras | `vendor.display.config/postproc/color` | vendor HAL | colour, post-processing, DSI quirks | 2 | complementary to the composer path |
| Audio effects | `audio.effect@6.0`, `audiohalext` | vendor HAL | effect chains, codec tuning | 2 | never a PCM transport |
| Media codecs | `media.c2`, `vendor.qti.media.*` | framework, C2 HAL | hardware decode/encode | 1 → 2 | large surface, evaluate before promising |
| DRM | `drm@1.x` widevine | framework broker | protected playback | 1 | licensing constraints |
| Neural networks | `neuralnetworks@1.3` (DSP/GPU/HTA) | NNAPI broker | accelerated inference | 1 | power-sensitive |
| Haptics | vibrator HAL, `qti-haptics` | sysfs, HAL | touch feedback | 3 → 2 | small, high perceived value |
| USB | `UsbService` | framework broker | mode and gadget control | 1 | interacts with DP-alt |
| Alarms/time | `vendor.qti.hardware.alarm` | framework broker | wake alarms | 1 | overlaps suspend policy |

The list is deliberately longer than the roadmap: future agents should be able
to pick a capability, confirm its tier, and find the acceptance gate without
re-deriving ownership. Nothing here is promised to users until its slice
passes.

## 6. Contract sketch

Not final; the first implementation slice fixes the details.

- **Discovery**: `aurora-capabilities [--json]` prints the inventory, read-only.
- **Operations**: one verb per capability (`aurora-wifi status|scan|connect|forget`),
  stable stdout schema, `0` success, typed non-zero errors, stderr for detail.
- **Guest API**: a session DBus service (`org.aurora.Capabilities`) mirroring
  the CLI for applications that should not shell out.
- **Broker protocol**: reuse the framed, authenticated control protocol
  conventions in `control/` rather than inventing a second one, and extend the
  journal pattern from `audio/aurora-audio-route`.
- **Leases**: `acquire`, `renew`, `release`, plus a visible `degraded` state.

## 7. Phases

Each phase is independently valuable and must leave the product working.

### P0 — inventory (read-only)

Emit the capability inventory for the reference device; no behavior change, no
framework interaction. Gate: JSON artifact in `artifacts/`, host tests, no
desktop-mode change.

### P1 — selective freeze

Replace the whole-process SIGSTOP with scoped thread freezing. Gate: in
desktop mode `cmd wifi status` answers, `aurora-connectivity wifi-scan`
returns networks, guest networking is unaffected, three desktop cycles leave
no stranded threads, and the compositor is untouched. Evidence: host and
guest logs plus the thread list before/after.

### P2 — broker upgrade

Typed Wi-Fi and Bluetooth broker replacing ad-hoc command parsing, with
journalled claims where ownership moves. Gate: connect, disconnect, forget and
reconnect from the guest; state survives a framework restart.

### P3 — direct HAL probe

Read-only `libgbinder` enumeration of vendor Wi-Fi (and one more) HAL versions
from the guest, compared against the broker inventory. Gate: probe artifact,
no state change, failure paths reported.

### P4 — first direct write

Wi-Fi scan through the vendor HAL, then connect. AP/P2P last, after the
ownership journal covers radio reconfiguration.

### P5 — expand

Sensors, GNSS, thermal/power, haptics through whichever tier the inventory
proves. Each gets its own gate.

### P6 — evaluate the expensive surfaces

Camera, codecs, DRM, NN. These are product decisions as much as engineering
ones; do not start them without a stated user need.

## 8. Testing rules

- Never start a desktop-mode transition without explicit user authorization.
- Before anything audible or disruptive, give the user at least ten seconds of
  warning and a notification on the device.
- Prefer display-safe probes and host tests. A probe that changes radio or
  display ownership is not a probe.
- Every slice records evidence in `artifacts/` and updates its manifest entry;
  [ARTIFACTS.md](../ARTIFACTS.md) applies.
- A capability is not "supported" until a fresh install passes its gate
  through the installer, not a manual repair.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Selective freeze leaves a thread unstoppable and the Watchdog still fires | keep the full freeze as a fallback; watch for Watchdog logs in every cycle |
| A HAL reclaims hardware Android believes it owns | journals and verified restore, as audio already does |
| Framework restart strands a claim | host broker owns cleanup and marks degraded |
| Vendor HAL ABI drift across devices/versions | negotiate versions; never branch on device name |
| Guest binder access becomes a security hole | typed, scoped operations; review each one |
| Radio reconfiguration breaks Android telephony | request, do not steal; verify restore on exit |
| Scope creep into a second OS | invariants in section 2; capabilities land one slice at a time |

## 10. Open questions

1. Does the selective freeze need per-thread naming data from the framework,
   or can thread names be matched generically across versions?
2. Should the host or the guest hold the direct-HAL binder connection? Host is
   simpler for ownership; guest is simpler for latency and distro neutrality.
3. How do leases interact with Android's own state restoration, especially for
   Wi-Fi (regulatory domain, saved networks)?
4. Does the presenter path eventually make the internal-mode freeze
   unnecessary, and if so does universalisation merge with external
   convergence?
5. What is the minimum DBus surface that lets a desktop environment manage
   Wi-Fi natively (NetworkManager integration) without a bespoke applet?

## 11. Related documents

- [design-spec.md](design-spec.md) — product invariants.
- [universalisation.md](universalisation.md) — device portability contract.
- [graphics-architecture.md](graphics-architecture.md) — display ownership.
- [audio-architecture.md](audio-architecture.md) — the journalled-claim pattern
  to copy, and the "never a transport" rule.
- [transformative-roadmap.md](transformative-roadmap.md) — longer-horizon
  product direction.
- [design-spec.md](design-spec.md) — milestone order and product scope.
