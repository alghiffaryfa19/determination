# Determination transformative roadmap

**Status:** living implementation programme  
**Started:** 2026-08-24  
**Product boundary:** Android remains PID 1; Determination remains a boot image,
Magisk module, Zygisk integration, Android companion, and Linux guest. It is not
a ROM and does not replace `/system` or `/vendor`.

This roadmap is the execution contract for turning Determination into the most
capable Android-hosted Linux convergence platform available. The benchmark is
not “more checkboxes than postmarketOS.” The benchmark is a better daily system:
Android remains a real phone, Linux is a real first-class desktop, transitions
are recoverable, hardware support is evidence-backed, and every layer can be
understood and repaired without private archaeology.

`docs/design-spec.md` remains authoritative for topology. The proven
compatibility renderer remains vendor EGL/GLES through libhybris, Android
gralloc owns compatibility buffers, and complete native handles plus explicit
fences remain mandatory. This programme extends those contracts; it does not
silently replace them with an easier but different product.

## 1. What “done” means

Determination is complete only when the following system-level outcomes are
true together:

1. Android can remain fully interactive on the internal panel while Linux runs
   on an external display, with direct guest rendering, input return, audio,
   hotplug recovery, and no SurfaceFlinger stop.
2. The internal panel can move between Android and Linux repeatedly without a
   black-screen gamble, ambiguous display ownership, stale input grabs, lost
   audio state, or a reboot being the normal recovery path.
3. Linux-first boot reaches a useful desktop through explicit health gates and
   always retains a phone-safe rollback path.
4. One native control plane owns desired state, observed state, transactions,
   policy, diagnostics, and recovery. Shell remains only for bounded hardware
   adapters and independent emergency restoration.
5. Phosh and Plasma Mobile are first-class qualified sessions. Additional
   wlroots compositors are enabled by backend compatibility, not misleading
   name-only launchers. Every selectable session carries a machine-readable
   compatibility verdict and a tested fallback.
6. The companion feels like part of Android: Quick Settings, launcher
   shortcuts, share targets, display attach, Storage Access Framework,
   user-mediated intents, live state, recovery, and update management all use
   the same structured control API.
7. Zygisk integration is a narrow, versioned `system_server` and app-process
   capability bridge. It provides lifecycle and framework hooks that cannot be
   implemented safely from an ordinary APK, but never exposes arbitrary root
   commands or pretends it can hook native SurfaceFlinger.
8. Audio, input, networking, power, files, clipboard, media, notifications,
   haptics, cameras, sensors, location, and external accessories each have an
   explicit ownership and privacy model rather than a collection of accidental
   passthroughs.
9. Install, update, downgrade refusal, rollback, restore, and bug collection
   work from stable public interfaces. A failed update returns to the previous
   complete version atomically.
10. Portability claims are generated from recon and qualification evidence.
    No device, distro, compositor, renderer, or route is called supported
    because it compiled once.

## 2. Programme rules

- Phone mode is the recovery baseline. Any operation that can take display,
  input, power, network, audio, or boot ownership has a deadline and rollback.
- Transition commits require observed evidence from the resource consumer. A
  process existing or a Wayland socket appearing is necessary but not always
  sufficient; frame submission, display attachment, input readiness, and
  session health are separate gates.
- “Automatic” means bounded, explainable, reversible, and observable. It never
  means an unbounded boot loop quietly retrying destructive actions.
- Compatibility comes before novelty. Optimised native paths are welcome only
  behind capability gates with the vendor/libhybris path still available.
- Privilege is split by capability. There is no general-purpose shell operation
  in an Android or guest-facing API.
- Every public state has a schema version, generation, source timestamp, and
  freshness verdict. The app must distinguish unknown, stale, transitioning,
  degraded, failed, and recovered states.
- Every user-facing choice that cannot work on the active device explains why,
  names the missing gate, and offers the closest safe alternative.
- Existing working paths are removed only after a replacement passes the same
  on-device gate and rollback installation is proven.

## 3. Foundation: one authority, many clients

### 3.1 Complete `detd` authority

Move `detd` from observe-only deployment to staged authority without making the
phone depend on an unqualified daemon.

Deliverables:

- boot-scoped instance identity and durable state generation;
- transactional desired/observed state for internal display, external output,
  guest, session, input, audio, networking, and update activation;
- operation IDs that survive client death and can be queried later;
- bounded event subscriptions with sequence numbers and resume cursors;
- idempotency keys for Android lifecycle retries and automation clients;
- structured health registry for every independently supervised component;
- reconciliation after daemon restart, Android reboot, guest restart, and
  partial module activation;
- native timers and process supervision with no append-forever poll loops;
- a policy table keyed by endpoint, peer credentials, operation, capability,
  current mode, and confirmation token;
- journal compaction that retains transition provenance and qualification
  counters without unbounded storage growth;
- a read-only compatibility socket during the authority rollout so old app and
  guest builds cannot mutate new state accidentally.

Gates:

- 100 daemon kill/restarts in PHONE and DESKTOP do not change ownership;
- reboot injection at each transition step reconciles to PHONE or an explicit
  phone-safe reboot requirement within 30 seconds;
- malformed and oversized packets cannot allocate unbounded memory, leak fds,
  cross operation authority, or block the event loop;
- old and new status paths agree during a full compare-only period.

### 3.2 Unified capability graph

Replace scattered booleans with a graph whose nodes describe prerequisites,
evidence, implementation, qualification, and conflicts.

Examples include `display.internal.hwc`, `display.external.presenter`,
`renderer.vendor-hybris`, `renderer.native-turnip`, `session.phosh`,
`session.plasma-mobile`, `audio.speaker.direct`, `audio.dp.direct`,
`input.touch.internal`, `input.keyboard.external`, and
`boot.linux-first.health-gated`.

Each capability records:

- unavailable, detected, buildable, installed, proven, qualified, degraded, or
  revoked status;
- evidence timestamp, device profile digest, ROM/kernel/blob identity, and
  build manifest;
- dependencies, conflicts, required ownership state, and fallback;
- the exact command or automated gate that last produced the verdict;
- whether the claim is host-static, emulator-tested, on-device observed,
  interactively verified, stress-qualified, or release-qualified.

The CLI, app, installer, compositor picker, update system, support matrix, and
documentation all consume the same graph.

### 3.3 Stable public protocol

Protocol v2 adds typed envelopes while retaining v1 status compatibility:

- capability graph query and filtered subscriptions;
- operation start/query/cancel where cancellation is explicitly safe;
- structured transition progress and rollback progress;
- fd-based import/export with MIME, size, display-name, and destination policy;
- guest application launch using desktop IDs, not shell strings;
- display inventory and external session summon/hide;
- audio route, volume, mute, and privacy operations;
- power profile and thermal budget operations;
- sanitised bug-capsule creation;
- update stage, validate, activate, rollback, and post-boot commit;
- user-presence/confirmation tokens issued by the companion for dangerous
  operations.

There remains no `EXEC`, arbitrary path, arbitrary signal, arbitrary property,
or unrestricted device-node operation.

## 4. Transition engine and recovery

### 4.1 Turn scripts into explicit steps

Retain the proven shell behaviour while extracting ownership into individually
journalled adapters:

1. preflight profile, battery, thermal, storage, guest, and recovery assets;
2. snapshot Android display, colour, brightness, rotation, audio, and service
   observations without mutating user settings;
3. start or verify guest init and control agent;
4. prepare unprivileged session runtime and device access;
5. quiesce Android input delivery policy;
6. acquire evdev grabs and prove the intended devices are exclusively owned;
7. freeze `system_server` through the qualified policy;
8. preserve lazy HALs and network services whose liveness is required later;
9. stop SurfaceFlinger and verify composer-client release;
10. start the selected backend and compositor;
11. require Wayland socket, first submitted frame, output geometry, input seat,
    shell readiness, and session-bus readiness;
12. commit DESKTOP and enable optional services independently.

Exit reverses only completed steps, in journal order, with independent deadlines
for compositor release, HWC availability, SurfaceFlinger start, fresh
`system_server`, boot animation completion, input return, audio restoration,
connectivity, SystemUI, and touch interaction.

### 4.2 Recovery controller

Add a tiny recovery supervisor independent of the full daemon. It understands
only version manifests, transition journals, resource holders, and the phone
restore path. It can:

- detect stale ENTERING/EXITING/DESKTOP state at boot;
- kill only PIDs whose recorded boot ID, start time, executable, and generation
  still match;
- release evdev, audio, and presenter ownership;
- restore service state without depending on a responsive framework;
- switch back to the previous module version;
- request a reboot when local restoration cannot be proven;
- leave a bounded, human-readable rescue receipt.

Recovery is available from the app, Quick Settings, `det`, a Magisk action zip,
USB recovery media, and the next boot. None depend on a notification.

### 4.3 Qualification harness

Build deterministic fault injection around every transition step: timeout,
child crash, stale pid, missing device node, HWC busy, failed frame, no input,
guest agent disconnect, low disk, thermal rejection, and daemon death.

The hardware suite runs 50 clean cycles, randomised fault cycles, and an eight
hour soak. Every run emits one manifest and one machine-readable verdict. The
suite always finishes by proving interactive Android phone mode.

## 5. Compositor and session platform

### 5.1 Backend families, not launcher theatre

Support is organised around real rendering/presentation backends:

- libhybris/hwcomposer direct backend for internal ownership;
- Android presenter backend for concurrent external output;
- Android-gralloc/minigbm compatibility winsys for GBM-oriented compositors;
- native DRM/KMS plus Mesa only as a profile-qualified optimisation;
- nested Wayland and headless/VNC backends for recovery and development.

Session manifests declare required backend, renderer, buffer allocator,
presentation path, input strategy, environment, services, known limitations,
and qualification evidence. The UI never enables a compositor because its
binary happens to exist.

### 5.2 Phosh completion

- retain the real PAM/logind/systemd user session;
- eliminate bare-session fallback on qualified systemd guests;
- finish feedbackd, geoclue policy, portals, secret storage, GVfs, Flatpak,
  accessibility, colour management, and GNOME settings integration;
- provide Determination panels for session, Android handoff, external displays,
  power, network, audio routes, input mappings, and recovery;
- persist monitor, scale, orientation, wallpaper, keyboard, and application
  session state;
- repair teardown so exit is clean rather than a tolerated phoc segfault;
- qualify matrix varyings and all GTK renderer paths used by shipped apps.

### 5.3 Plasma Mobile completion

- finish the Android-gralloc KWin winsys with complete native handles;
- expose authoritative plane metadata through mapper adapters;
- use vendor EGLImages from native buffers rather than pretending vendor EGL
  accepts generic dma-buf import;
- carry acquire/release fences through allocation, rendering, KWin, presenter,
  and HWC ownership;
- add bounded linear/copy fallback with visible diagnostics;
- integrate the external presenter as a KWin output path;
- qualify touch, virtual keyboard, rotation, suspend, lock screen, portals,
  PipeWire, window restore, and phone return.

### 5.4 Additional sessions

After the backend gates exist, add capability manifests and qualification for:

- Weston as a diagnostic reference compositor;
- Cage for single-app/appliance sessions;
- labwc for a compact desktop session;
- Hyprland only against an actually compatible wlroots ABI/backend;
- sway only if the hybrid API incompatibility is resolved rather than hidden;
- GNOME/Mutter only if an Android allocation/presentation backend is built;
- headless gamescope sessions for streaming and compatibility experiments.

No project name appears in the supported list before input, frame, teardown,
restore, application, and soak gates pass.

### 5.5 Session continuity

Create a session broker that records desktop IDs, window roles, workspaces,
display placement, and restorable documents where applications expose them. It
can restart a crashed shell or compositor without discarding the entire guest,
and can move a session between internal, external, nested, and remote outputs
without confusing global phone mode.

## 6. External convergence

### 6.1 Presenter as platform service

The presenter stops being “an app that happens to own a Presentation.” Split it
into:

- a minimal Android service process that owns `DisplayManager`, SurfaceControl,
  display lifecycle, authenticated sockets, buffers, and input dispatch;
- a companion UI/client process that configures and observes it;
- `system_server` hooks for display policy, task placement, launch routing,
  external desktop coexistence, and recovery affordances where public APIs are
  insufficient;
- a guest presenter agent that owns buffer registration, pacing, reconnect,
  and compositor-facing output state.

The service supports multiple external displays, per-display sessions,
independent scale/rotation/refresh, HDR capability reporting, hotplug, and app
process updates without losing the guest session.

### 6.2 Buffer protocol

- negotiate protocol, pixel formats, modifiers, dataspace, colour space,
  transforms, usage, buffer count, fence semantics, and damage;
- allocate through Android gralloc by default;
- transfer complete native handles with strict fd/int quotas;
- register a bounded pool once and never import per frame;
- submit damage plus acquire fences and return present/release feedback;
- pace from display timing instead of sleeping to an assumed refresh rate;
- record dropped, late, blocked, copied, and recovered frames;
- survive producer, presenter, display, and app-process death without leaks;
- provide an unmistakable colour-bar/sequence/build-ID producer as the first
  hardware gate before compositor integration.

### 6.3 External input

Implement a typed input protocol for keyboard, pointer, wheel, touch, stylus,
controller, hotplug, LEDs, repeat, layout, and device identity. Android events
are normalised before crossing the boundary and injected through constrained
uinput devices. No arbitrary evdev creation is exposed to apps or the guest.

Add phone-as-touchpad mode with pressure-independent gestures, keyboard entry,
scroll zones, haptic edge feedback, pointer capture, and an immediate escape
gesture. Input latency and dropped event counts appear in diagnostics.

## 7. Deep Android and SystemUI integration

### 7.1 Structured Zygisk bridge

- negotiate module/app/protocol versions in one handshake;
- pin every command to a fixed typed operation;
- authenticate same-UID companion connections and verify package signing
  identity where available;
- forward protocol packets and approved fds, never shell text;
- expose hook health and exact matched framework signatures;
- disable only the incompatible hook when an OTA changes a signature;
- retain a phone-safe fallback when no hook activates;
- add host tests for framing, deadlines, truncation, peer closure, and version
  skew plus on-device tests for both zygote ABIs.

### 7.2 `system_server` hooks

Create a versioned hook registry with independent capabilities:

- suppress the qualified SurfaceFlinger-death reaction only during a recorded
  internal handoff generation;
- expose display attach/detach and task-placement policy to the presenter;
- route explicit Linux-session launches to external displays;
- stabilise Android desktop/freeform flags without globally changing unrelated
  phone behaviour;
- provide a user-visible recovery action when the external service degrades;
- coordinate wake, keyguard, dream, power, and display policy without faking
  Android ownership;
- publish hook diagnostics through the control plane;
- avoid broad method interception and never swallow unrelated framework errors.

### 7.3 SystemUI surface

Implement a narrow SystemUI integration package or hook layer that contributes:

- a live convergence tile with PHONE, ENTERING, DESKTOP, EXITING, EXTERNAL,
  DEGRADED, and RECOVERY states;
- lock-screen and power-menu recovery affordances;
- external-display attach chip with summon/hide/session choices;
- compact thermal, battery, guest, and presenter state when relevant;
- a one-gesture return-to-phone path that does not depend on opening the app;
- no permanent notification as the primary control mechanism.

All SystemUI integration is additive and signature-gated. If an OTA breaks it,
the ordinary app, tile service, shortcuts, CLI, and recovery remain usable.

## 8. Linux-first mode

### 8.1 Boot profile compiler

Replace a monolithic “disable Android” list with a dependency graph generated
from the active device and ROM profile. Classify services as:

- kernel/vendor critical;
- radio/telephony critical;
- thermal/power/charging critical;
- storage/crypto critical;
- graphics/presenter critical;
- network critical;
- optional framework/UI;
- known unsafe to stop;
- unknown and therefore retained.

Every stopped service has a reason, restart strategy, health probe, and ROM
identity constraint. Unknown OTAs automatically fall back to conservative
phone-first boot.

### 8.2 Health-gated boot

Linux-first commits only after guest init, session, frame, input, networking,
storage, thermal, charging, and recovery controls pass. A watchdog requires
periodic health without high-frequency wakeups. Failed boot attempts are
counted durably, automatic retry is disabled after a bounded threshold, and the
next boot returns to phone mode.

### 8.3 Daily-use polish

- configurable boot target, grace period, dock-trigger policy, and power
  source requirement;
- intentional lock/unlock and encrypted guest-home policy;
- charging animation and battery-critical return-to-phone behaviour;
- alarm/call policy visible before enabling Linux-first;
- automatic external session summon when a remembered dock appears;
- clean Android UI restoration without stale boot animation or SystemUI state;
- a dry-run report listing exactly what would be stopped and every unresolved
  risk on the current ROM.

## 9. Audio, media, and communications

### 9.1 Direct audio product path

Complete direct ALSA/PipeWire ownership for speaker, microphones, wired
headsets, USB, DP/HDMI, and qualified Bluetooth backends. Each route has a
journalled claim, exact mixer/service restore, bounded latency, xrun recovery,
and hotplug policy. Internal codec ownership is explicit; external concurrent
mode never silently steals an Android call route.

### 9.2 User controls

- volume/mute keys through the input action daemon;
- desktop OSD and companion controls using the same route state;
- per-route remembered safe volume with speaker/headphone limits;
- microphone privacy toggle, indicator, and per-session consent;
- PipeWire graph and route diagnostics in the bug capsule;
- media-session bridge for title, artwork, play/pause/seek, and hardware keys,
  with opt-in Android lock-screen integration;
- policy for calls, alarms, emergency alerts, voice assistants, and exclusive
  Android ownership conflicts.

### 9.3 Camera and capture

Add an explicit camera capability broker rather than bind-mounting Android
camera devices blindly. Start with USB/UVC cameras, then evaluate Camera2 or
HAL-backed frame transport with visible indicators, bounded formats, and
exclusive ownership. Screen capture uses PipeWire portals and never bypasses
desktop consent silently.

## 10. Input, haptics, sensors, and accessories

- generated libinput metadata and quirks from recon evidence;
- touchscreen calibration, rotation, palm rejection, gestures, and pressure;
- keyboard layouts, LEDs, compose key, media keys, and configurable hardware
  button mappings;
- mouse acceleration profiles and high-resolution wheel support;
- controller hotplug, mapping database, rumble, gyro, and battery reporting;
- feedbackd haptics through a bounded host call with intensity/rate limits;
- proximity, accelerometer, gyro, light, compass, hinge, and orientation broker
  with per-sensor privacy and power budgets;
- fingerprint and biometric use only through user-mediated Android APIs; never
  expose raw biometric hardware to the guest;
- a complete input ownership diagnostic that identifies double delivery,
  missing grabs, stale uinput devices, and latency.

## 11. Connectivity and continuity

### 11.1 Network ownership

Move repeated netd-resistant shell assertions into a supervised network
component that observes link, route, rule, DNS, tether, and interface events.
Keep the proven table-117 fallback, but record why it activated and stop
forking polling processes when netlink can report the change.

### 11.2 Desktop network UX

- Wi-Fi scan/connect/forget through a typed Android broker;
- Ethernet, USB tether, hotspot, VPN, and captive-portal state;
- split-DNS and per-link routing visible in Linux;
- guest SSH route repair after Android DHCP changes;
- offline/local-network mode that remains useful without Android framework;
- connection handoff without leaking passphrases into logs or process argv;
- optional per-app network policy and metered-link awareness.

### 11.3 Personal continuity

- explicit clipboard bridge with MIME allowlist, size limit, sensitive-content
  expiry, and per-direction toggles;
- URL/open-with handoff both ways;
- bidirectional file share with progress, cancellation, collision policy, and
  destination choice;
- Android SAF provider exposing only a configured exchange directory;
- recent-transfer shelf in Linux and companion history with no private content
  in diagnostics;
- optional Android contacts/calendar access through user-granted, narrow data
  providers rather than mounting app data.

## 12. Companion application

The app is an operator console, installer, recovery tool, and Android-native
integration hub. It is not a root-shell frontend.

### 12.1 Information architecture

- **Now:** one honest system state, primary mode action, active display/session,
  and immediate recovery if needed;
- **Displays:** internal/external outputs, presenter, resolution, scale,
  rotation, refresh, summon/hide, and phone-as-touchpad;
- **Linux:** guest distro, session/compositor, applications, files, shell/SSH,
  compatibility, and Linux-first;
- **Hardware:** audio routes, input, controllers, power, thermal, network,
  storage, sensors, and capability evidence;
- **System:** install/update/rollback, diagnostics, logs, bug capsule,
  developer API, privacy, and about;
- **Recovery:** always reachable, minimal dependencies, exact action preview,
  and post-action proof.

### 12.2 State model

Replace scattered mutable properties and polling root shells with immutable
snapshots from the structured API. Every action has accepted/running/committed,
rolled-back, rejected, timed-out, and recovery-required states. Reconnect does
not lose an in-flight operation. Background refresh uses subscriptions and
freshness expiry, not aggressive polling.

### 12.3 Android-native surfaces

- dynamic shortcuts based on capability and current state;
- Quick Settings tile with live transition progress;
- share target, SAF provider, app links, and open-with targets;
- display attach receiver and remembered dock policy;
- widgets for state and safe actions where the platform permits;
- user-mediated intents and signature Binder API for trusted automation;
- Tasker/automation examples over the same permission checks;
- no arbitrary command extra, hidden root broadcast, or permanent-notification
  dependency.

### 12.4 Installer and updater

- preflight device/ROM/kernel/slot/Magisk/ReZygisk/storage/battery checks;
- signed manifest verification and component compatibility graph;
- download resume, hash verification, staging, and explicit destructive-action
  previews;
- automatic boot-image backup discovery and restore verification;
- atomic runtime activation with previous-version retention;
- post-boot health commit or automatic rollback;
- offline local-artifact path and USB recovery path;
- release channels with honest stable/experimental capability differences;
- exportable install receipt with hashes and recovery instructions.

## 13. Desktop experience

- Determination control centre using the guest agent D-Bus/API rather than
  host shell access;
- convergence shelf for transfers, Android links, recent sessions, and dock
  state;
- first-run setup for scale, keyboard, privacy, updates, audio, and recovery;
- wallpaper/accent handoff only with explicit permission and no private-image
  copying by default;
- adaptive internal/external layouts and sensible 1080p/1440p/4K scaling;
- lock screen, suspend policy, idle inhibition, night-light ownership, and
  colour management that never rewrites Android settings;
- desktop notifications independent of Android notification availability;
- accessibility stack, screen reader, high contrast, large text, switch input,
  and reduced motion;
- application compatibility dashboard for native Wayland, XWayland, Flatpak,
  portals, GPU path, camera, microphone, and known per-app quirks;
- session-safe “return to phone” and “restart shell” controls;
- sanitised bug capsule and latency overlay for developers.

## 14. Guest distributions and software

Define one portable guest contract covering init, services, packages, users,
sessions, libc, filesystem layout, security updates, and helper installation.

- Debian remains the release baseline until another distro passes every gate;
- Arch gains reproducible source pins, rollback snapshots, and graphical
  qualification before support status changes;
- Alpine remains a native-musl build: no hidden glibc/gcompat dependency;
- each distro receives the same static control, input, audio, and diagnostic
  helpers where ABI portability is required;
- distro package operations are transactional at the UI level and never
  presented as Android app installs;
- optional immutable/base-plus-overlay profiles allow disposable experiments;
- snapshots include manifest, distro identity, guest configuration, and restore
  compatibility checks;
- software catalogue entries declare architecture, display backend, GPU,
  portal, sandbox, and input requirements.

## 15. Power, thermal, battery, and storage

- profile-driven sip/balanced/performance modes with CPU/GPU/devfreq limits,
  scheduler choices, and explicit thermal trade-offs;
- battery source confidence and charger-node reconciliation;
- low-battery policy for internal and Linux-first sessions;
- charge-state correction without masking unrelated Android power state;
- thermal headroom, throttling, skin temperature, and power draw surfaced to
  the desktop and app;
- per-component wakeup accounting and idle shutdown;
- zram, PSI, low-memory, and guest reclaim policy;
- fstrim, guest disk growth, quota, low-space warnings, and snapshot budgets;
- no dangerous storage reclamation without exact preview and recoverable
  targets.

## 16. Portability programme

Recon becomes a capability compiler. It gathers boot layout, kernel features,
binder, SELinux, composer, allocator/mapper, native handles, GPU, DRM, displays,
input, audio, network, battery, thermal, storage, and Android framework traits.
It emits validated profile candidates, kernel decisions, LXC devices, guest
configuration, policy deltas, install compatibility, and unmet gates.

Device support is layered:

- Tier 0: recon only;
- Tier 1: guest/headless/network/SSH;
- Tier 2: internal display and input;
- Tier 3: stable round-trip and direct audio;
- Tier 4: concurrent external convergence;
- Tier 5: Linux-first and full release qualification.

The second reference device must differ materially—preferably GKI/AIDL
composer, a different GPU family, or a different boot layout—so the abstraction
is tested rather than admired.

## 17. Security and privacy

- maintain a threat model for malicious Android apps, compromised guest apps,
  network peers, malformed native handles, stale helpers, and partial updates;
- replace world-writable device access with stable groups or fd brokers where
  practical;
- verify peer credentials, signing identity, endpoint ownership, packet sizes,
  fd types, buffer dimensions, allocation totals, and outstanding work before
  expensive imports;
- separate presenter, audio, transition, recon, update, and file-transfer
  authority;
- keep secrets out of argv, logs, bug capsules, transfer history, and process
  environment;
- sign release manifests and atomically activate complete component sets;
- provide privacy controls for clipboard, files, microphone, camera, location,
  sensors, contacts, and media metadata;
- document the trusted-guest boundary honestly until containment is proven;
- add security regression tests to the normal host gate rather than treating
  them as a release-week ritual.

## 18. Diagnostics and developer platform

`det doctor --json` becomes a coherent offline snapshot with schema and
freshness. It includes identities, modes, operation journal, component health,
process/namespace identity, display path, frame/fence metrics, input ownership,
audio route, network, memory, battery, thermal, storage, update state, hook
health, capability verdicts, contradictions, and a ranked recovery suggestion.

Additional tools:

- `det events` for sequenced state changes;
- `det trace transition|presenter|audio|input` with bounded capture;
- `det capsule` for a sanitised support archive;
- `det qualify` for named static/device/stress gates;
- `det capabilities` for the exact support graph;
- `det benchmark` for transition, frame, input, audio, network, and storage;
- a protocol SDK and examples for trusted Android and guest clients;
- deterministic simulators for app development without root or a connected
  phone;
- machine-readable docs generated from protocol and capability schemas.

## 19. Performance programme

Measure PHONE, ENTERING, DESKTOP, EXITING, EXTERNAL, Linux-first idle, and mixed
workloads. Track critical-path time, wakeups, CPU/GPU residency, PSI, memory,
dmabuf/KGSL totals, frame production/latch/present/release, input latency,
audio latency/xruns/drift, network latency/loss/DNS, storage, thermal state, and
battery discharge.

Targets:

- warm internal enter p95 under 4 seconds, stretch under 2.5 seconds;
- Android interactive exit p95 under 4 seconds;
- read-only local RPC p99 under 10 ms;
- daemon idle RSS under 10 MiB and wakeups below one per 30 seconds;
- external 60 Hz missed-present rate below 0.1% in a two-hour mixed workload;
- keyboard/pointer input median under 12 ms and p99 under 30 ms;
- direct audio round-trip under 20 ms, stretch under 12 ms on supported routes;
- no per-frame native-handle imports and no unbounded queues;
- no battery claim without a reproducible comparative workload.

## 20. Release engineering and lifecycle

- one source manifest pins every external dependency and toolchain;
- reproducible build entry points cover kernel, boot, module, control binaries,
  guest helpers, rootfs additions, presenter, Zygisk ABIs, companion, recovery,
  and release metadata;
- every artifact is hashed, signed where appropriate, cross-checked against its
  ABI/device/profile contract, and verified after packaging;
- staged versions switch atomically and retain a known-good predecessor;
- post-boot health commits a new version only after phone recovery and required
  services are proven;
- downgrade refusal is explicit and separately overridable with recovery
  assets present;
- clean install, upgrade, rollback, restore, and uninstall are tested paths;
- release notes distinguish implemented, host-tested, device-observed,
  interactively verified, stress-qualified, and unsupported features;
- large hardware evidence can live outside normal Git objects while immutable
  hashes and manifests remain in the repository.

## 21. Delight that earns its keep

- a real “absolute determination” qualification badge after 50 clean cycles;
- build-ID colour bars for photographed external first-frame evidence;
- a soul-status CLI/app element driven by real health, never fake counters;
- dock-specific session profiles and instant summon;
- phone-as-touchpad with tasteful haptics;
- convergence shelf and zero-friction bidirectional sharing;
- session migration between internal and external outputs;
- developer latency HUD and fence timeline;
- release accent/wallpaper packs isolated from recovery and update state;
- deterministic optional transition variants disabled during recovery and the
  first run after update.

No easter egg runs as root, changes display calibration, hides failures, wakes
the device repeatedly, or delays a routine action.

## 22. Execution waves

### Wave A: freeze truth and protect recovery

- preserve current WIP and record source/module/app/guest/kernel identities;
- finish host validation and independent emergency restore;
- add missing shell/static tests for current lifecycle and helper changes;
- establish one capability vocabulary and plan document.

**Exit gate:** current proven phone↔desktop round-trip is unchanged and every
new component can be disabled independently.

### Wave B: capability and operation spine

- protocol v2 schemas;
- capability graph;
- operation journal/query;
- structured health and events;
- app immutable snapshot model;
- compatibility adapters for protocol v1 and marker files.

**Exit gate:** CLI, app, guest, and daemon describe one coherent state without
periodic app root shells.

### Wave C: authoritative transitions

- deploy daemon authority behind an explicit activation flag;
- journal every adapter step;
- add frame/input/session readiness and bounded rollback;
- implement recovery supervisor and fault injection;
- qualify daemon restart and ten hardware cycles before default activation.

**Exit gate:** 50 cycles and crash injection end in a known, explained state.

### Wave D: guest/session completion

- finish Phosh teardown and app-session contracts;
- complete Plasma compatibility winsys;
- add session manifests and broker;
- qualify portals, accessibility, Flatpak, files, network, input, and audio;
- add nested/headless recovery sessions.

**Exit gate:** Phosh and Plasma each pass application, transition, and soak
matrices with honest backend labels.

### Wave E: external convergence

- split presenter service architecture;
- complete buffer/fence protocol and colour-bar producer;
- show first DP frame while Android stays interactive;
- add compositor output, input return, scaling, hotplug, and reconnect;
- add phone-as-touchpad and per-display persistence.

**Exit gate:** two-hour external desktop, repeated cable cycles, working input
and audio, Android internal display continuously interactive.

### Wave F: deep Android integration

- structured Zygisk v2 forwarding;
- independent hook registry and diagnostics;
- SystemUI states/recovery/display affordances;
- task placement and display policy hooks;
- native share, SAF, shortcut, tile, intent, and automation surfaces.

**Exit gate:** framework OTA mismatch disables only affected hooks and leaves a
fully recoverable ordinary control path.

### Wave G: Linux-first daily driver

- compile boot service dependencies from recon/profile evidence;
- health-gated boot and retry budget;
- dock, power, call/alarm, lock, charging, and low-battery policies;
- conservative OTA fallback and dry-run report;
- long soak and failed-boot recovery.

**Exit gate:** repeated cold boots reach Linux or automatically recover to a
fully interactive phone without adb intervention.

### Wave H: hardware completeness

- direct audio routes and privacy;
- input/controller/haptics/sensors;
- network event service and desktop UX;
- power/thermal/storage policies;
- camera/capture brokers where support is feasible;
- accessibility qualification.

**Exit gate:** each public hardware feature carries route/device-specific
evidence and independent failure recovery.

### Wave I: portability and release

- recon compiler and tiered support matrix;
- hostile second reference device;
- atomic signed updates and rollback;
- clean install/upgrade/uninstall validation;
- reproducible release and generated capability documentation.

**Exit gate:** two materially different devices pass their declared tiers, and
a new installation can be built and recovered from public repository state.

## 23. Immediate implementation tranche

The first code tranche lands the pieces that unblock many later waves without
claiming hardware qualification:

1. add protocol support for typed component health, capability inventory,
   operation query, and event snapshots;
2. derive honest capability states from current observations and source
   manifests;
3. add `detctl capabilities`, `health`, and operation inspection;
4. expose coherent data through Zygisk and the companion without arbitrary
   shell commands;
5. add session manifests and a validator used by CLI/app/session launch;
6. strengthen internal readiness from socket-only to compositor frame/session
   evidence with rollback;
7. add an offline bug-capsule builder with redaction and bounded logs;
8. add host tests for the expanded protocol, capability graph, session
   manifests, shell helpers, and package manifests;
9. make the host validation gate exercise every new static contract;
10. document exactly which results still require the OnePlus 7, DP-alt hardware,
    physical audio routes, or interactive visual verification.

This tranche is intentionally broad: it improves the state spine, compositor
selection, app data model, diagnostics, testing, and release honesty together.
It does not switch the proven device to unqualified transition authority or
declare external convergence finished before a real DP frame exists.

## 24. Non-fake completion ledger

Every roadmap item is tracked as one of:

- **planned:** architecture and dependencies are written;
- **implemented:** source exists and is integrated;
- **host-tested:** deterministic local tests pass;
- **built:** target artifact compiles/packages;
- **device-observed:** machine evidence exists on the target;
- **interactive:** Melissa verified the human-visible behaviour;
- **stress-qualified:** declared cycle/soak/failure gate passes;
- **release-qualified:** reproducible install, upgrade, rollback, and recovery
  pass for a declared support profile.

Anything below release-qualified remains visible as such. Determination becomes
better than alternatives by being more capable and less mysterious—not by
renaming untested work “done.”
