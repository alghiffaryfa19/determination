# Cooperative `system_server` for internal-panel desktop mode

Status: experimental design handoff

Owner: a future agent must implement this as a separately gated backend. The
qualified internal-panel path remains the freezer path until every gate below
passes on `guacamoleb`.

## The goal

Internal desktop mode must still stop SurfaceFlinger and release the internal
panel's single-client hwcomposer HAL to the guest. It may also hand the phone
codec to direct ALSA/PipeWire. Neither requirement means the entire Android
framework has to be stopped.

The target is a cooperative, headless `system_server`:

- SurfaceFlinger is stopped and restart-masked.
- The guest is the only internal-panel composer client.
- `system_server` remains running and treats the internal display as an
  intentional temporary handoff, not a fault which it must synchronously repair.
- Android's non-display services remain usable through constrained bridges.
- Android's UI does not render during the handoff; it has no SurfaceFlinger.

This is not concurrent internal composition. The panel remains exclusively
owned by the guest. It is a live Android service plane beside a guest-owned
display plane.

## Why the current path freezes `system_server`

`toggle/desktop-on` stops SurfaceFlinger, starts the SF restart suppressor, then
SIGSTOPs `system_server`. The latter is required today because its
`android.display` watchdog checker blocks after SurfaceFlinger disappears. Its
60-second block budget eventually makes framework Watchdog kill the process.

SIGCONT is not a recovery: it merely releases the accumulated timeout and the
process kills itself. `toggle/desktop-off` therefore kills the frozen process
and lets zygote create a fresh one after SurfaceFlinger returns. The lazy
`vendor.lineage_health` keeper on exit is load-bearing; do not remove it.

The freezer has been a successful Aqua stability compromise. It also removes
PackageManager, ContentProvider, notification, and ordinary framework Binder
availability from desktop mode. A concrete consequence was observed on
2026-09-08: Magisk's hidden-app superuser provider left one `app_process content
call` client per root command resident while `system_server` was frozen. They
all disappeared after `desktop-off` restored `system_server`.

## What a live `system_server` would unlock

| Capability | Cooperative internal mode | Boundary |
|---|---|---|
| PackageManager, intents, ContentProviders | Yes | Keep calls bounded; do not make guest apps depend on arbitrary Android APIs. |
| Magisk superuser policy/logging | Yes | Use the Aurora fixed-command bridge or `aurorad`, not an unbounded root shell. |
| NotificationManager, media sessions, battery/connectivity state | Yes | Bridge state and named actions to Opal; the guest renders it. |
| Telephony, alarms, Bluetooth, Wi-Fi and framework jobs | Yes | Give each a documented ownership/alert policy; they remain Android-owned. |
| Framework diagnostics | Yes | `dumpsys` and package inspection work during desktop mode. |
| SystemUI rendering | No | It needs SurfaceFlinger. Stop or quiesce its visual work; retain only state needed by bridges. |
| Android input delivery | No panel input | Guest `EVIOCGRAB` remains the ownership boundary. Do not remove it. |
| Android audio output | Not by default | AudioFlinger/audioserver may be quiesced while Linux owns the codec. System-server policy may remain alive. |
| Internal-panel composition | No | One panel, one hwcomposer client: the guest owns it until phone restore. |

## Non-negotiable constraints

1. Do not keep SurfaceFlinger alive on the internal panel. The downstream HIDL
   composer is single-client in this mode.
2. Do not replace the problem by lying to framework Watchdog. Marking
   `android.display` complete while it is genuinely stuck hides leaks and can
   leave an unbounded display queue behind.
3. Do not globally disable Watchdog, hook `kill`/`tgkill`, or SIGCONT the old
   process on exit. The old PLT kill-hook experiment registered but did not
   intercept the real kill path.
4. Do not issue arbitrary Magisk `su` jobs after display handoff. The root
   request path touches Android framework services. Use a named `aurorad`/Zygisk
   companion action or a pre-armed root-side operation instead.
5. Keep `desktop-off --emergency` independent of the new backend. A failed
   cooperative attempt must restore phone mode through the proven freezer/kill
   recovery sequence.
6. Do not substitute raw KMS, Mesa/Zink, or a nested compositor for the product
   libhybris/hwcomposer internal path.

## The implementation shape

The current Zygisk code only swallows `ctl.start` and `ctl.restart` requests for
SurfaceFlinger. That prevents an init respawn fight; it does not change Java
DisplayManager/WindowManager policy and therefore cannot make `system_server`
cooperative by itself.

Implement a versioned Java-level hook capability, loaded only in
`system_server`, with this contract:

1. Read an authenticated, generation-scoped handoff record from
   `/data/aurora/run/`.
2. Before SurfaceFlinger stops, put the default display into an explicit
   `internal-handoff` state.
3. At the exact SF-death/reconnect path identified by traces, return an
   asynchronous intentional-detach result instead of waiting for SurfaceFlinger
   or reissuing a start request.
4. Quiesce display-only traversal, input-focus, animation, and SystemUI visual
   work while retaining bounded non-display services.
5. On guest release, clear `internal-handoff`, restart SurfaceFlinger, force a
   display recomputation, and confirm a fresh Android frame before committing
   PHONE.

Use LSPosed or a small injected Java hook payload for the framework methods
identified by traces. A native Zygisk property hook remains useful for SF
restart masking, but is not a replacement for this policy hook. A framework
rebuild is not the product path.

## Required evidence before writing a hook

The only confirmed blocked identity is `android.display`; the exact Java call
stack must be captured on this ROM/build before naming a hook target. Do not
guess a `DisplayManagerService` method from another Android release.

Build an opt-in `cooperative-system-server` probe with all of these properties:

- It starts in phone mode and arms its complete rollback before stopping SF.
- It does **not** start `ss-freezer`.
- It records `logcat`, `dmesg`, process state, binder state where readable, and
  ART Java thread dumps before the 60-second watchdog window.
- It has a root-side, detached 35-second rollback deadline which restores the
  proven phone path even if the initiating client disappears.
- It never requires a post-handoff Magisk `su` call to collect evidence.
- It is not exposed in the companion UI and is refused unless an explicit local
  opt-in file exists.

Capture at least two thread dumps after SF is gone, then restore SurfaceFlinger
well before the watchdog deadline. The result must name the concrete blocked
method, its Binder peer, whether it retries or waits, and which queued work
continues to grow.

## Incremental qualification plan

1. **Trace only.** Run the bounded probe; restore phone mode automatically;
   archive the actual `android.display` stack and watchdog evidence.
2. **Narrow no-wait hook.** Hook only the identified intentional-detach path.
   Keep the current freezer as the immediate fallback if the hook cannot load,
   rejects the generation, or misses its deadline.
3. **Service audit.** Measure CPU, PSS, PSI, wakeups, Binder queue depth, and
   Magisk provider-client count. Explicitly quiesce any SystemUI/display task
   that spins or queues while SF is absent.
4. **Bridge proof.** Demonstrate a bounded notification/media/connectivity
   snapshot and named action through the Aurora companion/Opal bridge.
   No arbitrary command channel is permitted.
5. **Round trips.** Pass ten phone → guest → phone cycles, then a 30-minute
   internal session and an overnight idle session. Each must restore a visible
   Android frame, working touch, Wi-Fi, audio ownership, and a responsive
   PackageManager without reboot.
6. **Promote only then.** Make cooperative mode selectable behind a capability
   record. Do not replace the freezer default until repeated device evidence
   says it is safer.

## Success criteria

While the guest owns the panel:

- SF remains stopped and the guest retains the only hwcomposer client.
- `system_server` is runnable, has no blocked `android.display` watchdog
  checker, and does not respawn SurfaceFlinger.
- Magisk/provider clients complete and leave no resident `app_process` buildup.
- Non-display Android service CPU/wakeups stay bounded at idle.
- SystemUI does not attempt to render or accumulate SurfaceControl work.
- `desktop-off` produces a visible phone frame without killing a live,
  cooperative `system_server`; fallback still kills/restarts it if the
  cooperative state is ambiguous.

## Starting points in this repository

- `toggle/desktop-on`: current SF stop, restart suppressor, and freezer order.
- `toggle/desktop-off`: proven restore and lazy-health-HAL protection.
- `zygisk/jni/main.cpp`: current SF restart-property hook and fixed-command
  root companion.
- `zygisk/README.md`: injection boundary and intended companion bridge.
- `docs/troubleshooting.md`: proven watchdog and exit-wedge evidence.
- `docs/design-spec.md`: internal handoff invariants.
- `control/`: bounded `aurorad`/`auroractl` protocol; do not invent a second arbitrary
  root command transport.

## Explicit non-result

External DP convergence is the already-designed fully live Android mode. This
document does not claim that it makes the internal panel concurrent. It makes
the existing exclusive internal-panel mode less hostile to the Android services
that do not need to compose a frame.
