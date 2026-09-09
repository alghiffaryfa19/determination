# Opal / Expressive

A Material 3 Expressive-inspired Quickshell, with Pixel-style quick settings, a tablet-style app shelf, dynamic color palettes and genuinely translucent compositor-blurred surfaces. This is an independent shell, not Google software.

## Start / restore

`opal on` starts the shell and temporarily stops/masks DMS. `opal off` restores DMS and your prior Hyprland styling/bindings. DMS is not removed or permanently disabled. The runtime mask and Hyprland style marker disappear at reboot. The original shell was backed up under `~/.local/state/opal/v1-*`.

## Install

From a checkout, run `./install.sh`. It installs missing dependencies through
pacman, dnf, or apt where those packages exist, installs the shell into
`~/.config/quickshell/opal`, and puts `opal` in `~/.local/bin`. For a Lua-based
Hyprland config, it also adds an idempotent, reversible runtime-marker hook to
`~/.config/hypr/hyprland.lua`; the hook only loads Opal bindings while Opal is
on. Existing shell and Hyprland config files are backed up under
`~/.local/state/opal/pre-deploy-*-install`; preferences are preserved. Use
`./install.sh --restart` to install and reload in one step, `--no-deps` to skip
package installation, or `--no-hyprland` to leave Hyprland untouched.

## Shortcuts and layouts

- Super+Space: launcher. Super+Comma: shade. Super+N: inbox.
- `opal phone` / Super+Ctrl+P: compact touch-sized app drawer, home clock, bottom Android-style navigation.
- `opal console` / Super+Ctrl+G: large game-first library, Steam Big Picture button, keyboard / joystick navigation.
- `opal desktop` / Super+Ctrl+D: restore desktop layout.
- `opal appearance`: personalize colors, light/dark, glass density, wallpaper composition, layout.
- `opal close`: dismiss overlay. `opal inspect`: read-only JSON diagnostics.
- All three layouts are shell layouts, not compositor display rotations or replacements for applications' own UI. Phone mode does not add an on-screen keyboard.

## Docking and convergence

Open Convergence from the shelf or Quick Settings. Flow uses each output's logical dimensions independently; per-output Auto / Desktop workspace / Touch home overrides are remembered by connector name. A newly attached output gets a 20-second, non-keyboard-exclusive docking welcome. Startup establishes a baseline without opening overlays. Connecting a monitor never automatically moves application windows or changes your chosen global layout; Enable Flow is explicit.

Convergence includes animated device previews, panel arrival motion, reduced-motion control, and working glass density. Touch home is wallpaper-first: clock, search, favorites, a compact now-playing row and recent-app shortcuts — no Quick Settings tiles or sliders. Wide displays put the clock beside the app area. The app switcher uses horizontally snapping cards with real window titles and close/return actions, not fabricated window screenshots. USB-C display-out, display arrangement, resolution, mirroring and application scaling depend on hardware and the compositor; Opal does not provide an Android docking service or phone-as-touchpad input injection. Physical hotplug still needs hardware verification.

## App switcher and phone display corners

Desktop Open, phone Recent and console App switcher share searchable window cards, workspace filtering, close/context actions and keyboard/controller navigation. Clicking a preview dismisses the keyboard-exclusive overlay before focusing the live window’s monitor and workspace. The checked adapter detects native Lua dispatchers (this installation) and retains a legacy CLI fallback; compositor errors are reported rather than silently ignored. App icons prefer an already-running window; Open new instance remains available in the context menu. Phone uses a height-bounded touch carousel; desktop and console use compact grids. Live Wayland screencopy previews are requested only for visible cards while the switcher is open, kept in GPU/session memory and never written to disk. Hyprland addresses resolve through a separately loaded optional adapter; unsupported or unavailable captures are labeled honestly. Physical capture behavior depends on the compositor and is not established by offscreen renders.

Choosing Phone targets the invoking display (remembered as phoneDisplay); other displays retain desktop layout. Flow still supports per-output overrides. The shell publishes resolved phone output names to `$XDG_RUNTIME_DIR/opal-phone-displays`; `hyprland.lua` applies `no_rounding` only to `m[output]` workspace selectors. Leaving phone layout or unplugging removes those selectors on config reload. Global desktop rounding is not set to zero.

## Shelf dragging

Drag taskbar icons horizontally to reorder them. The dragged item lifts, neighbors animate aside, and edges auto-scroll. Drop order is persisted separately from favorites and never moves application windows. A drag suppresses click-to-launch; releasing outside the strip cancels. Ctrl+Left/Right on a focused task also reorders it. New motion respects the reduced-motion preference; auto-hide stays inhibited while dragging or using a task context menu.

## Wallpaper studio

Appearance → Wallpaper studio opens a local thumbnail gallery with built-in artwork, folder browsing and individual image selection. The large preview includes a sample shell surface. Crop/fit and image dimming are draft-only until Apply; Reset restores the saved selection. Gallery discovery is bounded to 120 images / 3,000 entries / three directory levels, skips hidden files and symlink traversal, and never downloads assets. Default roots include Pictures, Pictures/Wallpapers, ~/wallpapers and system wallpaper directories. Image previews are decoded asynchronously at bounded thumbnail sizes. Wallpaper and preview settings are applied together in one preference write.

Phone-mode app drawers use a centered maximum-width area and at most seven columns on large displays, with separate category filters. The normal desktop launcher layout is unchanged.

## Launcher

App grid with fuzzy-ranked search, categories, recently launched apps, and pinned apps. Right-click or long-press to pin. Pins and recents are persisted; the shelf shows your pinned apps (a useful default set before you pin anything).

- Arrow keys: grid navigation. Enter: launch. Escape: close.
- `= (18 + 4) * 3`: safe arithmetic. Enter/click copies result using wl-copy. No eval or command execution.
- `> screenshot`, `> focus`, `> phone`: curated shell actions.
- `? search terms`: explicit Google search in your default browser.
- Apps / At a glance / Open / Style navigation rail (segmented toolbar in phone mode).
- Open lists and focuses live Hyprland windows; other compositors get an explicit unsupported message.

## Useful things

Working volume/mute and hardware backlight controls, integrated Wi-Fi and Bluetooth detail pages with radio power, scanning, network/password entry, device pairing and connect/disconnect, notifications with actions, DND, actual Wayland idle inhibition, MPRIS media controls/art, 25-minute focus timer with pause/reset/+5, month-browsable calendar, live CPU/RAM, power profiles, screenshot capture, lock and confirmed power operations. Backlight controls only appear when the kernel exposes a backlight device. External monitor DDC brightness is not implemented.

DND suppresses toasts but retains notifications. Inbox is session-only and is not written to disk. Preferences, favorites, recent app IDs: `~/.local/state/opal/preferences.json`. Focus timer is in-memory. UI defaults to Inter + CaskaydiaCove Nerd Font.

## Phone bars

Phone has a dedicated 48-pixel status bar rather than desktop tray controls: clock opens the inbox, unread/quiet status, sound/now-playing, and a combined Wi-Fi/battery Quick Settings target. Hold the clock for quiet mode and personalization; hold connectivity for Wi-Fi and docking. A running focus timer gets a compact shortcut. Back / Home / Recents remain the three-button set, with larger touch targets and Home hold-actions. Gesture navigation has explicit Back and Apps shortcuts; tap the handle for Home, slide sideways or hold for Recents. Back navigates within Opal, never injects an application's Back key. Both bars remain available on full-screen launcher and utility overlays; the shade retains its own controls.

## Console controllers

The Python adapter reads the Linux joystick API at `/dev/input/js*`, without grabbing devices or injecting input. Kernel button and axis maps identify face buttons, shoulders, Start/Guide, Select and D-pad; fixed indices are a fallback when map queries are unavailable. Standard layout: A accept, B back, X pin, Y search, left stick / D-pad navigate, LB/RB change category, Select opens Play hub, Start/Guide toggles the library. Choose Nintendo in Play hub → Setup to swap face-button actions and their hints. Stick navigation repeats after a short hold; triggers and the right stick are ignored. Keyboard arrows/Enter/Escape, Tab/Shift+Tab, F2 pin, F3 search and Menu also work.

Play hub has Library, Session, Sound and Setup sections. Left/right or LB/RB switches sections; up/down selects and accept activates. Volume, mute, music, session and layout toggles can be used without leaving the menu. Continue includes running games before recently launched games. A quiet play session suppresses popups and inhibits idle without changing saved DND settings; ending it restores the underlying behavior. Navigation is ignored outside console mode and, except Start/Guide, while the library/other overlays are closed. Game input is never intercepted, so a game may also receive controller buttons. Requires an accessible joystick device; no permissions are modified. Physical mappings still need hardware verification. The library, Play hub, search keyboard and app switcher support controllers; general settings dialogs remain touch/mouse/keyboard UI.

## Compatibility / dependencies

Quickshell + Qt Quick Controls + Wayland layer-shell + Python 3. No Hyprland QML imports: launcher, layouts, notifications, tray, preferences and widgets work on other layer-shell compositors. Workspaces/window focus use optional Hyprland CLI. Blur is compositor-provided, not a fake screenshot effect. This installation supplies rules for the installed Lua-config Hyprland; other compositors need their own blur rules. Not a GNOME or X11 panel.

Optional Linux tools: wpctl, playerctl, nmcli, bluetoothctl, brightnessctl, powerprofilesctl, grim, wl-copy, notify-send. Network and Bluetooth settings stay inside Quick Settings, using nmcli and bluetoothctl adapters. Wi-Fi supports visible personal/open networks and saved credentials; enterprise/hidden network configuration is not yet embedded. Bluetooth PIN/passkey confirmation still needs an existing system agent. Credentials are not saved by Opal (NetworkManager may retain its connection profile). Quick Settings includes microphone mute; advanced audio settings elsewhere still open pavucontrol. Screenshots go to Pictures/Screenshots. The media card may load the art URI supplied by your active player. Web search is only on explicit action. No weather or online recommendations are fabricated.

Not bundled: lock screen (uses existing hyprlock), polkit agent, an on-screen keyboard, screen recorder, or a full controller mapper. Existing DMS-only shortcuts outside the remapped set remain unavailable while DMS is paused.

## Source

`Theme.qml`, `Surface.qml`, `MButton.qml`, `QuickTile.qml`, `ExpressiveSlider.qml`, `Flower.qml`: design system. `Launcher.qml`, `QuickSettings.qml`, `Dashboard.qml`, `Appearance.qml`: screens. `Hub.qml`: UI state and IPC bridge. `backend.py`: safe JSON-lines adapters and atomic preferences. `shell.qml`: panel/layer layout. `hyprland.lua`: reversible compositor overrides.
