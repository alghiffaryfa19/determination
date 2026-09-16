# Direct audio architecture

Status: internal-speaker alpha hardware-proven on `guacamoleb`; full route and
failure qualification remains.

## Product invariant

Aurora audio is a Linux hardware stack:

```text
Linux application
  -> PipeWire / pipewire-pulse
  -> ALSA PCM and control API
  -> Qualcomm ASoC + DSP + Tavil codec kernel drivers
  -> speaker, headset, microphone, USB or DP
```

AudioFlinger, AAudio, `AudioTrack`, the Android audio Binder APIs, and the
companion app never carry Aurora PCM. They are not fallbacks. During an
exclusive internal-codec handoff Android's owners must be quiesced, but they do
not become a transport or service dependency.

The guest owns the application graph. A small host component may arbitrate
hardware ownership and execute a device-profile route transaction, but it must
never proxy sample buffers.

## Current implementation

`aurora-audio-probe` has Android/bionic and Debian/glibc builds with one stable
JSON schema. It inventories `/dev/snd`, captures `/proc/asound`, identifies all
open ALSA descriptors, and implements a read-only `--require-unowned` gate.
The same binary on each side makes namespace and permission mismatches obvious.

The Android binary is packaged as `/data/aurora/bin/aurora-audio-probe`.
The guest binary is installed as `/usr/local/bin/aurora-audio-probe` on each guest
start. Neither binary opens a PCM or mutates a mixer.

`aurora-audio-session` is the unprivileged guest lifetime guard. It starts
PipeWire, pipewire-pulse, and WirePlumber only while the host's fsync'd
`audio-claimed` marker is visible; marker withdrawal terminates the graph.
Normal owner restore then requires a fresh zero-holder probe before it restarts
Android's HAL. This prevents PipeWire and Android racing the same codec.

`aurora-audio-owner` snapshots `audioserver` and `vendor.audio-hal`, converges both
to a stable stopped state, proves zero ALSA holders, and publishes the guest
claim. The settling check is load-bearing on Android 16: `audioserver.rc`
deliberately restarts `vendor.audio-hal` after audioserver stops for VTS.

`aurora-audio-route` journals the pre-claim mixer state, applies the vendor speaker
route (`MultiMedia1` to `QUAT_MI2S_RX`, TFA selector 2), and verifies Android's
HAL asynchronously rebuilds the exact original route after ownership returns.
PipeWire creates one static `aurora-speaker` sink for `hw:0,0`; desktop
udev discovery does not describe this Qualcomm card correctly in the guest.

On 2026-08-02 a one-second 440 Hz, -40 dBFS tone was heard first through direct
ALSA and then through `pw-play`. Both paths returned to `Off Off`, TFA selector
3, and running Android audio services. `desktop-on` and `desktop-off` now call
the same journalled route transaction. This proves the internal speaker slice,
not the remaining routes or stress gates.

## Ownership transaction

Internal display mode needs an exclusive codec transaction. The current alpha
uses the journalled native owner plus a bounded route wrapper; folding the
transaction under `aurorad` remains the intended control-plane endpoint:

1. Refuse the request during calls, alarms, recording, or an existing audio
   transition unless the policy explicitly permits interruption.
2. Record the device profile, kernel boot ID, service states, every relevant
   ALSA control value, active route, node ownership, and current `/dev/snd`
   holders to an fsync'd journal.
3. Quiesce the profile's Android audio owners in dependency order. This is
   arbitration only; no Android audio API is used.
4. Run `aurora-audio-probe --require-unowned`. Any remaining holder aborts and
   restores the journal.
5. Apply the exact profile route and permissions, then expose the nodes to the
   guest. Unknown controls, cards, or topology hashes are a hard failure.
6. Start the guest PipeWire graph and prove a bounded PCM stream. Record hw/appl
   pointers, negotiated format/rate/periods, xruns, and startup latency.
7. On exit, stop the graph, verify the guest released every node, restore mixer
   controls in reverse order, then restart only Android owners which were
   running in the snapshot.
8. Verify Android can reopen the card. Keep the journal if verification fails
   and surface recovery through `auroractl doctor`; never silently declare success.

Daemon death recovery reads the journal phase. Pre-claim phases roll back;
post-claim phases first terminate the bounded guest graph, then restore. The
emergency recovery command is fixed and cannot accept arbitrary service names
or mixer controls from an app client.

## Route model

Routes are data selected by an exact device profile, with topology hashes to
prevent applying OnePlus 7 mixer values to a vaguely similar phone. Each route
describes:

- card identity and required PCM/control/compress nodes;
- playback/capture PCM, format, rate, period and buffer bounds;
- complete precondition and postcondition controls;
- ordered enable and reverse-disable operations;
- speaker amplifier/DSP dependencies and safe gain ceilings;
- jack detection, DP/HDMI ELD, USB hotplug, and microphone privacy policy;
- Android owner stop/start order and timeout;
- a reversible verification action.

UCM2 is preferred where it can fully express a route. A tiny native adapter is
allowed for Qualcomm-specific topology or amplifier sequencing, but only mixer
and route metadata cross that boundary:never PCM buffers.

## Concurrency policy

Internal phone codec ownership is exclusive until the driver stack proves safe
sharing. External convergence can stay concurrent by choosing independent
hardware: DP/HDMI ALSA, USB Audio Class, or a Bluetooth backend managed directly
from Linux. If a route is not independently ownable, capabilities report it as
unavailable; Aurora does not smuggle it through Android.

## Qualification gate

Full direct audio is not called working until all of these pass on-device:

- [x] exact card/PCM/control inventory captured on both sides;
- [x] zero `/dev/snd` holders after quiesce;
- [x] a direct speaker tone with a conservative gain ceiling;
- [x] Android route and service state restored byte-for-byte;
- [x] PipeWire app playback without a companion service;
- volume/mute, headset and DP/USB routes;
- suspend/wake, cable cycles, daemon kill, guest crash and failed-restore tests;
- measured latency, drift and xrun recovery under CPU/GPU load;
- microphone disabled by default with visible privacy state when enabled.

Until those gates pass, the honest state is
`direct_audio=internal-speaker-alpha`, not `audio=working`.
