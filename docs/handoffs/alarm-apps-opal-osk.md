# Handoff: usable ALARM applications, installer parity, and Opal OSK

## 0. Read this before doing anything

This is the continuation handoff for Aurora's Arch Linux ARM / Opal work. It
separates observed results from proposals. It is not a graphical qualification
report or a claim that the application/keyboard work below is implemented.

### Latest user corrections and requirements

1. **There are no useful applications installed in the fresh ALARM guest.**
   This is not primarily an Opal launcher-indexing bug. Do not spend the next
   session rewriting app discovery instead of shipping actual applications.
2. **ALARM fixes must reach the installer.** A manual repair on this phone is
   not delivery. Fresh installation, reprovisioning, and packaged updates need
   the same supported runtime, input fixes, applications, and configuration.
3. **The OSK needs major improvements, both in Opal and for general use.** Work
   on the Opal source in `~/.local/state/opal/staging/`, not its installed copy
   and not only Aurora's vendored snapshot.
4. **No mode switches.** Do not stop SurfaceFlinger, acquire hwcomposer, launch
   the phone compositor, restart the framework, reboot, or schedule a restore
   timer. Use host tests and explicitly display-safe checks. This prohibition
   remains until the user authorizes a specific graphical test.
5. Do not deploy or restart the host's live Opal shell for testing. Its local
   instructions explicitly require permission before changing the desktop.
6. The compositor is **Hyprland**, installed under **`/opt/hyprland`**. Do not
   invent another product name for it.
7. The heart/SOUL/Undertale identity is retired. There are newer icon changes
   committed after this agent's original ribbon work; preserve them.

### What this handoff does not authorize

- Blanket package upgrades that overwrite the kernel-compatible init stack.
- Disabling browser sandboxes, SELinux globally, or guest privilege boundaries.
- Global input injection, evdev grabs, input-device permission changes, or
  clipboard-as-keystroke workarounds to fake an input method.
- Treating offscreen/software test renders as vendor-GPU or panel qualification.
- Cleaning up the large dirty repository, state directories, or backups.

## 1. Workspaces and ownership

### Aurora repository

`/home/melissa/decemberos`

Read `AGENTS.md`, `docs/design-spec.md`, `docs/recon-findings.md`,
`docs/graphics-architecture.md`, and `docs/arch-opal-bringup.md`.

This checkout has hundreds of pre-existing modified/deleted/untracked files,
including a broad project rename, installer work, and imported Omarchy sources.
A delete/add pair in `git status` often represents a rename, not lost source.
Do not use reset/clean or stage the whole tree. Review changes before editing.
Use repository-configured author identity for focused commits.

Latest commits observed at this handoff:

- `a89a7ad` Balance Aurora icon crown and crossbar placement
- `75f25da` Restore glass depth to Aurora's joined ribbon icon
- `dc14aff` Join Aurora crossbar into a continuous icon silhouette
- `6bf8caa` Soften Aurora icon ribbon joins
- `4e5cb7f` Add blended Aurora ribbon artwork and record Arch Opal bring-up gates

The four icon commits after `4e5cb7f` are subsequent work, not changes to undo.
A read-only review found that generated vectors match the canonical artwork.
The latest four icon revisions have not been independently device-verified by
this agent; do not infer the installed icon version from source HEAD alone.

### Actual Opal development workspace

`/home/melissa/.local/state/opal`

Read **`agents.md`** here; the filename is lowercase. Its `.git/` is empty and
this directory is **not a standalone Git checkout**. Do not initialize a new
repository or infer that this is disposable state.

Editable source: `staging/src/`
Tests: `staging/tests/`
Installer: `staging/tools/install.sh`
Documentation: `staging/README.md`

Installed shell: `~/.config/quickshell/opal`
Live CLI: `~/.local/bin/opal`

Running `opal` tests the installed shell, not staging. Do not run `opal on`,
`opal off`, or the installer to validate development edits. Preserve
`preferences.json`, `last-install-backup`, `hyprland.lua.before`, and all
`pre-deploy-*`, `pre-install-*`, and other restoration directories.

Opal comments must be one line and use ASD-STE100 Simplified Technical English.
Use existing theme primitives. Core QML must not gain mandatory Hyprland imports.
Do not open keyboard-exclusive overlays on startup, reload, or preference load.

### Aurora's vendored Opal copy

`/home/melissa/decemberos/guest/opal/`

This is a deployment snapshot, not the requested workspace for the OSK redesign.
Do not assume it is synchronized with staging. After tested upstream changes,
review and copy only the intended files, preserve Aurora adapters, and update
package inputs/manifests. Do not overwrite staging from the vendored snapshot.

## 2. Device facts and current confidence

Reference phone: OnePlus 7 / SM8150 / Adreno 640. Android remains PID1 and the
ALARM guest shares its downstream 4.14 kernel. Vendor graphics go through
libhybris, with Android gralloc native handles and fences. HWC is single-client.

Use official `/home/melissa/platform-tools/adb`. Never `adb root`.
Root command form: `adb shell "su -c '<entire command chain>'"`.
Availability/serial must be checked again; the cable has been unplugged and
reconnected during this work. The previously observed USB serial is `9f14afe3`.

Relevant phone paths:

- Active pointer: `/data/aurora/active-guest`
- Current ALARM root: `/data/aurora/guests/arch/rootfs`
- LXC command: `/data/aurora/lxc/bin/lxc-attach -P /data/aurora -n guest -- ...`
- Toolkit: `/data/aurora/bin`
- Persistent tool payload: `/data/aurora/guest-tools` -> `current/guest-tools`
- Payload version observed: `/data/aurora/current` -> `versions/12`
- Assets: `/data/aurora/guest-assets/opal`
- Guest configuration payload: `/data/aurora/guest-config`
- Session definitions: `/data/aurora/etc/sessions`
- Host device profile: `/data/aurora/etc/device.conf`
- Guest session user: `aurora`, uid 1000; runtime `/run/user/1000`

`guest-start` copies persistent guest tools/assets/configuration back into the
active guest. Updating only a guest file can be silently undone at next start.
Installer/module payload parity is therefore load-bearing, not optional polish.

### Verified, with bounded claims

- Root works and Arch boots. Firstboot provisioning completed; `ready=yes`.
  **That marker does not mean daily-use apps, full Opal, or OSK are qualified.**
- Both Android 16 hwcomposer compatibility libraries built and were installed.
- Arch-built libhybris passed 1,200 vendor-render/native-handle/fence/readback
  cycles with stable fd counts, including as unprivileged `aurora`.
- Hyprland's cached port binary reported version 0.49.0 and previously created
  a Wayland socket in a guarded desktop test. This is not an end-to-end pass.
- Current-source Quickshell 0.3.0 and its matching private Qt runtime were
  rebuilt and installed under `/opt/hyprland`; its version identifies Aurora.
- Both Qt Wayland platform plugins resolve dependencies when checked with the
  launcher's `LD_LIBRARY_PATH`. An earlier plain `ldd` omitted this environment
  and printed misleading missing-library output; do not regress that diagnosis.
- A later display-safe preflight and windowless QML-import probe succeeded.
  The probe loaded Qt Quick/Controls/Layouts/Models and Quickshell modules,
  printed `OPAL_QML_IMPORTS_OK`, and exited. It did not render an Opal desktop.
- A no-grab, display-safe libinput context accepted six devices: five
  keyboard-only devices plus `touchpanel`, which has touch and keyboard caps.
  SurfaceFlinger stayed running and uptime continued.

### Not verified / still incomplete

- A useful default application suite: **the user's current blocker**.
- Actual touch delivery, gestures, repeated session restore, and OSK interaction
  inside the complete Opal UI after the latest fixes.
- General application input-method compatibility, including XWayland.
- A complete clean-source Hyprland release build replacing all cached artifacts.
- End-to-end installer delivery of everything manually repaired on the phone.

### Reboot incident: do not minimize it

Earlier guarded mode-switch attempts used independent two-minute restore timers.
`desktop-off` deliberately kills frozen `system_server` to avoid a Watchdog
resume failure. That can look like a reboot, but a later recovery showed short
kernel uptime and boot reason `reboot`: **a full reboot did happen**. Pstore was
empty and the cause was not established. Logs alone do not prove whether it was
user-triggered, a crash, a lifecycle race, or another cause. Do not label it only
a cosmetic framework restart. Do not repeat those tests under the current ban.

## 3. ALARM application delivery: next priority

### Correct problem statement

A fresh rootfs with graphics/runtime dependencies is not a usable application
installation. Opal's `Hub.qml` reads `DesktopEntries.applications.values`; that
cannot display programs that do not exist. Do not add fake app tiles or a custom
scanner as the first response. First ship the applications.

`prepare-arch-sysroot.sh` currently stages a cross-build/dependency set including
`foot`, Phosh, and squeekboard. That does not prove those packages were included
in the rootfs actually installed on the phone. During earlier checks `foot` was
not in the active guest. The firstboot path installs runtime and Phosh groups,
not a defined, useful Opal application suite.

### Proposed initial app profile — verify before adopting

Create a named, declarative **Arch desktop applications** profile shared between
host image assembly and on-device provisioning. Candidate roles/packages:

| Role | Candidate | Required check |
|---|---|---|
| Terminal | `foot` | Wayland startup, font, keyboard, normal user shell |
| Browser | `firefox` | Current ARM64 package, sandbox, downstream-kernel and renderer compatibility |
| Files | `nautilus` or a deliberately chosen smaller alternative | Touch usability, open/save, removable paths |
| Text editor | `gnome-text-editor` | Touch selection, input-method support, save/open |
| Calculator | `gnome-calculator` | Touch layout and desktop entry |
| Image viewer | `loupe` | Current ARM64 availability and rendering |
| Documents | `papers` or an available qualified alternative | ARM64 availability, file associations |
| Archives | `file-roller` | Optional size budget; file integration |
| Supporting integration | `desktop-file-utils`, `xdg-utils`, `xdg-user-dirs`, fonts/icons | Actual desktop entries, MIME database, readable user directories |

These are proposals, **not a verified package list**. Check ALARM repositories
and app compatibility before promising defaults. Do not substitute x86 packages,
run an unsupported browser without its sandbox, or call software/Mesa rendering
a vendor graphics pass. Keep a small required base and separately selectable
extras if size/dependency costs are high. Do not install NetworkManager merely
because an app recommends it; Android currently owns phone networking.

### Implementation sequence

1. Inventory actual guest packages and desktop entries with read-only commands
   when the phone is available. Distinguish installed, missing, and unsupported.
2. Define one package profile with explicit required/optional roles and package
   mappings. Avoid duplicating incompatible lists in multiple shell scripts.
3. Wire it into the host rootfs build and firstboot/provision path, not only a
   one-off `pacman -S` command. The installed archive must contain the intended
   userspace, not a bare base while the enriched sysroot stays on the PC.
4. Add a versioned, idempotent migration for existing guests. Firstboot currently
   exits when `/etc/aurora-ready` exists; this phone will otherwise skip new work.
   Do not remove the marker or rerun unrelated setup blindly.
5. Preserve package signature verification and the systemd/libudev constraints
   below. Persist migration success only after required package/config checks.
6. Update desktop/MIME/icon/font caches in the correct execution environment.
   The PC cross-install path suppresses target scriptlets: define which
   post-install operations must run in the guest, and make them retryable.
7. Validate that desktop files resolve to real executables and become visible
   in the standard launcher model. Only investigate discovery if installed,
   valid entries still fail to appear.
8. Package and test this profile through the actual installer path. Then offer
   or perform the corresponding non-graphical guest update within user scope.

### Installer files to read and change deliberately

- `guest/aurora-platform`: logical package mapping and dependency groups.
- `guest/customize-portable-rootfs.sh`: generates `/root/aurora-firstboot`;
  installs helpers, account/groups, compatibility setup, readiness marker.
- `guest/prepare-arch-sysroot.sh`: signed ARM64 package staging on the host;
  target hooks/scriptlets suppressed; includes packages for cross compilation.
- `guest/build-portable-rootfs.sh`, `guest/prepare-arch-source.py`: base creation.
- `guest/build-arch-desktop.sh`: libhybris, libgbinder, wlroots, Phoc cross-build.
- `guest/build-arch-systemd.sh`: pinned 257.13 source build and private libudev.
- `installer/arch.py`: current stages are toolchain/source/packages/graphics/init.
  Read the caller and final bundle assembly; **do not assume** these stages
  produce a complete Hyprland/Opal/application image by themselves.
- `installer/pipeline.py`, `installer/automation.py`, `installer/core.py`:
  cache keys, outputs, assembly, failure reporting, deploy flow.
- `installer/install-device.sh`: runtime/rootfs/module deployment boundary.
- `toggle/guest-distro`: provisioning and slot lifecycle.
- `toggle/guest-start`: persistent payload copies and runtime preparation.
- `magisk-module/build-module.sh`, `magisk-module/customize.sh`: deployed tools,
  assets, session definitions, configuration, and update parity.

### Application acceptance criteria

- A fresh supported Arch install has the agreed real applications.
- An already-provisioned guest receives the profile once and reruns safely.
- No held init/system library is replaced by an explicit package request.
- No target binary runs on the PC during cross-rootfs staging.
- Missing required packages produce actionable failures, not a false ready flag.
- Desktop entries, icons, MIME integration, and non-root ownership are checked.
- Tests cover interrupted install, rerun, absent optional apps, and selected
  profile preservation. Graphical app launch waits for separate authorization.

## 4. ALARM fixes that must be distributed

| Fix | What happened | Source / remaining installer work |
|---|---|---|
| Preserve compatible systemd | Explicit `pacman -S systemd` bypassed IgnorePkg and tried to replace the qualified init | `aurora-platform` now skips that explicit target when installed; runtime regression test exists. Ensure all provisioning/update paths honor it. |
| Private libudev 257.13 | Current Arch libudev enumerated zero devices (`scan_rc=-49`); 257.13 found all 13 nodes | Tested phone library came from Debian 257.13-1~deb13u1. Source-built Arch 257.13 now stages `opt/hyprland/lib/compat/libudev.so.1`; pipeline output includes it. Verify final archive inclusion and qualify that exact artifact before substitution. |
| OnePlus touchscreen quirk | Profile omitted it; libinput rejected invalid zero-range axes | Host config selects `oneplus-touchpanel-zero-axes`; `generate-guest-config` writes `/usr/share/libinput/99-aurora.quirks`. Ensure the installer selects the known device profile instead of losing this setting in generic discovery. |
| Input udev database | No normal udev daemon classification in the container | Keep `aurora-input-udevdb` readable/traversable for uid 1000 and run before input consumers. Do not chmod hardware nodes to work around a missing group. |
| Runtime identity | Seat/input permissions require the right groups | Preserve uid 1000, `android_input` gid 1004, distro seatd socket group, runtime directory mode, and non-root launch. |
| Qt platform runtime | Development packages were present but the Wayland plugin was missing | `Containerfile.quickshell-cross` includes runtime packages. Build script checks Wayland plugin presence and bundles matching private Qt libraries/plugins/QML with `qt.conf`. Add these artifacts to installer outputs and hashes. |
| Hyprland runtime path | Source/runtime naming was migrated | Ship `/opt/hyprland`, updated wrappers/manifests/config, and migration logic for existing installs; update persistent payload, not only guest files. |
| HWC source availability | Gitiles archives returned HTTP 503 | `hwc2-compat/build.sh` has pinned-tag Git archive fallback; keep checks and manifests, never use unreviewed random binaries. |
| HWC diagnostic API | `present()` return type no longer matched pinned libhybris | Fill test now uses a void override with explicit failed-frame handling; both diagnostics build. |
| Magisk boot root | Earlier replacement kernel lost legacy initramfs marker handling | Root-repair work predates this continuation; preserve its installer regression tests and backups. Do not reflash to solve applications/OSK. |

The quirk generator uses its own file and must not overwrite a user's
`/etc/libinput/local-overrides.quirks`. Existing generic device-discovery tests
intentionally avoid inventing unverified hardware quirks. Select the already
known OnePlus hardware profile; do not infer this workaround for every device.

### Source-versus-device distinction

The phone's successful enumeration used the Debian-built libudev binary copied
privately, not the newly staged Arch source-built version. Both are 257.13, but
that is not proof of identical behavior. Record and test the shipped binary's
hash. Do not replace Arch's `/usr/lib/libudev.so.1` globally.

The compositor still comes from a cached port build with a compatibility wrapper
for its earlier environment-variable contract. Quickshell was rebuilt from the
current source and now uses `AURORA_OPAL_GLES`. A release must distinguish those
provenance states instead of presenting the cache as a clean reproducible build.

## 5. OSK: current implementation and actual gaps

### Two separate products of work

**A. Opal's own text fields:** a shell-local virtual keyboard edits QML fields.

**B. Other applications:** a real Wayland input method must negotiate focus,
content purpose, surrounding text, preedit/commit, visibility, and keyboard
surface placement with the compositor and clients.

Improving A alone is not a system-wide keyboard. Launching squeekboard alone
is not an expressive Opal-integrated keyboard. Plan and test both.

### Staging implementation observed

- `staging/src/SearchKeyboard.qml`: a small signal-emitting rectangular key
  grid. Boolean shift/numbers, four rows, fixed height (244 or 320), controller
  index navigation, insert/erase/accept/dismiss signals. It does not implement
  a Wayland input method or app-wide text entry.
- `MobileHome.qml`: owns `keyboardOpen`, includes SearchKeyboard, and appends
  characters to the end of the search string. Erase uses `.slice(0,-1)`.
- `ConsoleHome.qml`: includes SearchKeyboard for controller search; also appends
  and slices at the end. Existing D-pad/A/B navigation must remain functional.
- `ClipboardPanel.qml`: includes the same keyboard for filtering, with the same
  append/slice behavior. Preserve clipboard privacy and exact stored text.
- `Launcher.qml`: has a real search TextField but no corresponding embedded
  keyboard in the implementation read. Do not assume the MobileHome keyboard
  solves launcher overlays, passwords, or other settings fields.
- `shell.qml`: controls layer-shell focus. Homes are nonexclusive, explicit
  overlays may be exclusive. Preserve startup and focus invariants.
- `Hub.qml`: state/backend protocol; `Theme.qml`, `Surface.qml`, `MButton.qml`,
  `Glyph.qml`: design primitives. There is no established universal OSK state
  owner yet in the reviewed implementation.

The staging README explicitly says phone layout does not add a system OSK and
lists the OSK as not bundled. Update this only as capabilities genuinely land.

### Aurora-specific existing keyboard

- `guest/aurora-osk`: toggles squeekboard via the **session** D-Bus service
  `sm.puri.OSK0`, using gdbus or busctl and checking current visibility.
- `guest/hyprland-opal.conf`: starts squeekboard with the client Wayland EGL
  platform and binds `SUPER+K` to the helper.
- `guest/aurora-session-launch`: session bus/runtime/graphics environment.
- `guest/tests/osk-test.sh`: helper behavior tests.

There has been no new OSK implementation in staging in this continuation yet.
Only inspection was performed before the user requested this handoff. Do not
claim a keyboard redesign is already underway in modified QML files.

## 6. OSK implementation plan

### Phase A — shared editing contract and usable shell-local keyboard

1. Define a single explicit keyboard controller bound to an eligible QML text
   target. Track show/hide, layout, purpose, modifiers, and return action.
2. Insert at the cursor and replace selections. Backspace/delete must respect
   Qt text boundaries and Unicode; do not delete one UTF-16 code unit blindly.
   Include non-BMP emoji, combining characters, selected ranges, and middle-of-
   string editing in tests. Use a tested text-edit adapter instead of duplicating
   string manipulation in every view.
3. Keep the text field focused when tapping keys. Keyboard buttons must not
   become the text-input target. Dismissal must not close unrelated UI or leave
   the overlay keyboard-exclusive when it should release focus.
4. Support one-shot Shift, explicit caps-lock, numbers and symbols, sane return
   labels/actions (Search/Done/Go/Next), and input-purpose-aware layouts for
   numbers, email, URL, and passwords.
5. Implement held Backspace repeat with cancellation on release, pointer exit,
   hide, focus change, and component destruction. No orphan repeat timers.
6. Add useful editing controls: cursor movement, selection-aware delete, clear
   with an explicit action where appropriate, and optional spacebar cursor
   scrubbing confined to the active field. Do not inject global keys.
7. Reuse the controller/keyboard in launcher search, MobileHome, console search,
   clipboard filtering, and appropriate network/settings text fields. Preserve
   existing controller navigation and physical keyboard shortcuts.
8. Improve keyboard proportions: broad spacebar, clear action key, separate
   modifier styling, usable edge padding, thumb-friendly rows, and a stable
   toolbar. Test actual narrow-phone widths, not only a roomy desktop preview.
9. Add key-press feedback, controlled visual preview, clear pressed/caps states,
   and reduced-motion behavior. No real input text may be sent to logs.
10. Keep app results and focused fields visible above the keyboard. Add scrolling
    or viewport adjustment rather than covering the field or collapsing the
    entire app drawer. Test portrait, landscape, one-handed, desktop, console,
    and multiple scales. Do not promise 44px targets in a layout whose width
    cannot physically hold ten such keys; choose and document sensible sizing.

### Phase B — system-wide keyboard integration

1. Inventory compositor input-method/text-input/virtual-keyboard protocol
   support read-only from source or previously captured protocol lists. Do not
   start a compositor to answer this under the current restriction.
2. Prefer an existing reliable input-method backend while evaluating the custom
   UI boundary. Decide explicitly whether to improve squeekboard integration,
   use another qualified input-method daemon, or implement a native protocol
   service. A QML `TextField` keyboard cannot automatically type into other apps.
3. Define the narrow IPC contract between Opal controls and the input-method
   service: capabilities, visibility, purpose, layout, and errors. Do not send
   password text or general surrounding text through shell logging/status paths.
4. Use protocol-backed focus, preedit/commit, enter actions, and surrounding-text
   edits. Do not use xdotool, ydotool, global uinput, or clipboard replacement as
   a substitute. Do not enable an unrestricted keystroke-injection endpoint.
5. Ensure correct layer placement/output selection and space reservation. A
   keyboard cannot take exclusive focus away from the application it serves.
6. Handle physical-keyboard policy, manual toggle, focus loss, empty targets,
   application death, screen changes, orientation, and session exit cleanly.
7. Disable suggestions/history/learning/previews appropriately for passwords
   and sensitive fields. Do not persist typed text. Clipboard insertion must be
   explicit and must preserve existing clipboard privacy rules.
8. Evaluate language switching, long-press accents, punctuation, composition,
   accessibility, and optional local predictions after the editing/focus core is
   reliable. Do not promise swipe typing or multilingual prediction without an
   actual backend and tests.
9. Package backend dependencies, service/session wiring, environment, layout
   assets, and user permissions into Aurora's installer. Make unsupported
   compositor/app cases visible rather than silently pretending input worked.

### Focus and privacy acceptance gates

- No keyboard or exclusive overlay appears at boot/reload/preferences load.
- Explicit text-field action can show it; dismiss is reliable and reversible.
- Physical keyboard use and controller navigation continue to work.
- No duplicate character on touch release after a long press or drag.
- Repeat stops on all cancellation paths.
- Cursor/selection/Unicode editing is correct.
- Password entry never enters logs, preferences, clipboard history, or telemetry.
- In-app OSK and system input-method tests are reported separately.
- Missing optional backend/tools produce a clear unavailable state.
- No actual client-input claim is made until separately authorized live testing.

## 7. Safe testing workflow

### Opal staging only

From `~/.local/state/opal/staging/`:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tests/test_notifications.py
bash tests/render-offscreen.sh
```

Read these runners first. Notification tests use a private D-Bus/offscreen
Quickshell. Render tests use a temporary HOME/runtime, software rendering, and
disconnected service endpoints. Inspect resulting images for the changed
layouts. Do not run `src/shell.qml` or `src/backend.py` directly against the real
session. An offscreen test is UI validation, not vendor-GPU qualification.

Add isolated QML OSK tests with real TextFields/TextAreas and event sequences,
not only static source greps. Include portrait/light/dark/landscape/controller
screenshots and numeric/password/selection/Unicode/cancellation fixtures.

### Aurora host checks

`sh tools/check-host.sh` passed earlier before the newest external source
changes. Do not represent that as a fresh run against arbitrary future edits.

Relevant individual tests:

- `guest/tests/platform-runtime-test.sh`
- `toggle/tests/guest-input-config-test.sh`
- `guest/tests/hyprland-launch-test.sh`
- `guest/tests/hyprland-naming-test.py`
- `guest/tests/opal-runtime-test.sh` (added in subsequent work)
- `guest/tests/osk-test.sh`
- `guest/tests/portable-rootfs-test.sh`
- `installer/tests/` pipeline/profile/migration tests to extend

The renamed graphics patches applied cleanly to fresh pinned checkouts and a
second run was idempotent. This is not equivalent to a complete compositor build.

### Device-safe checks, only if connected and within current scope

Read package inventory, paths, ownership, dependencies, session state, and input
classification. Current `aurora-opal check` runs dependency/version checks; read
its implementation before using it in case it changes. Do not use `start`.
Do not rerun device tests solely because the cable appeared; finish host work
first and respect the no-mode-switch constraint.

Never use `desktop-on`, direct HWC diagnostics, Hyprland startup, `opal on/off`,
or timers that call `desktop-off` as a harmless probe. They change ownership or
restart framework components.

## 8. Evidence and artifact map

Directory: `/home/melissa/decemberos/artifacts/opal-arch-bringup/`

- `buffer-smoke.log`, `preflight.log`: native-buffer tests and compositor version.
- `udev-comparison.log`: zero nodes with system libudev versus 13 with 257.13.
- `input-display-safe.log`: six accepted libinput devices including touchscreen.
- `resumed-preflight.log`: updated non-root runtime dependency/input checks.
- `qml-import-probe.qml`, `qml-import-probe.log`: windowless imports, no GUI pass.
- `recovery-state.log`, `recovery-logs.txt`: reboot evidence and uncertainty.
- `host-tests.log`: earlier host suite pass.
- `hyprland-patch-check.log`: patch application check (may be empty on success).
- `quickshell-current-build.log`: current-source rebuild and install staging.
- `quickshell-current-runtime.tar.gz`: prepared private Qt/Quickshell bundle.
- `current-runtime-installed.log`: initial install; its plain ldd check lacked
  the launcher environment and was superseded by resumed-preflight evidence.
- `opal-payload-before.tar.gz`: prior persistent tools/config/session backup.
- `companion-blended-build.log`: older blended icon APK build, not necessarily
  the latest externally committed crown/crossbar revision.

Build locations:

- `build/arch-desktop/sysroot`: enriched cross-build sysroot, not automatically
  the installed rootfs. Verify assembly and payload lineage.
- `build/arch-systemd/install`: source-built compatible init/libudev outputs.
- `build/opal-quickshell-current/install/opt/hyprland`: rebuilt shell/runtime.
- `build/opal-quickshell-current/runtime-packages.tsv`: build package versions.
- `build/hyprland-rename-check`: clean pinned patch-check working trees.
- Older compositor build directories retain historical names; do not rename
  cached build trees blindly because recorded compiler paths are embedded.

## 9. Concrete next-agent checklist

### Start

- [ ] Read this document, the latest user messages, both workspace instructions,
      and the current diffs. Do not rely on a stale context summary alone.
- [ ] Confirm no background build/deploy from another agent is modifying the
      files you intend to touch. Do not kill someone else's work.
- [ ] Preserve the latest icon commits and user changes.

### Applications and installer

- [ ] Confirm fresh ALARM package inventory, not merely launcher model contents.
- [ ] Agree on/implement a small real default application profile.
- [ ] Unify profile use in image assembly, firstboot, and versioned reprovision.
- [ ] Audit final artifact assembly: app packages, private libudev, Qt plugins,
      Hyprland, Opal assets, helpers, device quirk and manifests must travel.
- [ ] Add regression tests for retained init pin, profile upgrades, interrupted
      provisioning, required executables/desktop files, and artifact cache keys.
- [ ] Review session-wide Phosh defaults in `setup-compatibility.sh` before
      applying them to a Hyprland/Opal profile; do not accidentally retain the
      wrong desktop/portal identity just because firstboot is Phosh-oriented.

### OSK

- [ ] Implement and test a shared, selection-aware local editing adapter.
- [ ] Replace the cramped search-only grid with a reusable expressive keyboard.
- [ ] Integrate launcher/mobile/console/clipboard/settings fields deliberately.
- [ ] Define a real system-input-method backend plan and capability boundary.
- [ ] Carry required backend/service/layout changes into Aurora's installer.
- [ ] Render isolated previews and test focus, repeat, Unicode and privacy.
- [ ] Ask for authorization before any live shell deployment or graphical test.

### Completion report

State exactly which source files changed, which installer paths now include the
fixes, which host tests passed, which packages are actually installed, and which
live graphics/input behavior remains untested. Do not turn package presence,
version output, or an offscreen import into a claim that the complete desktop
and OSK work on the phone.
